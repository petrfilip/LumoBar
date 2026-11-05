import Darwin
import Foundation

/// A Yeelight bulb seen on the LAN (SSDP search reply or multicast NOTIFY advertisement).
struct YeelightDiscoveredBulb: Identifiable, Equatable, Hashable {
    /// Yeelight device id (e.g. `0x000000000015243f`), lowercased. Stable across IP changes.
    let id: String
    let host: String
    let port: Int
    let model: String
    let name: String
    let firmware: String

    var displayName: String {
        if !name.isEmpty { return name }
        return model.isEmpty ? "Yeelight" : "Yeelight \(model)"
    }

    var address: String { "\(host):\(port)" }
}

/// SSDP-based Yeelight discovery over plain BSD UDP sockets (multicast needs no entitlement
/// on macOS; the system only asks for Local Network permission, see
/// `NSLocalNetworkUsageDescription`).
enum YeelightDiscovery {
    private static let groupAddress = "239.255.255.250"
    private static let groupPort: UInt16 = 1982

    private static let searchMessage =
        "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1982\r\nMAN: \"ssdp:discover\"\r\nST: wifi_bulb\r\n\r\n"

    /// Sends an M-SEARCH on every active IPv4 multicast interface and collects replies (and any
    /// NOTIFY advertisements heard meanwhile) for `duration` seconds, deduplicated by device id.
    static func search(duration: TimeInterval = 3) async throws -> [YeelightDiscoveredBulb] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try blockingSearch(duration: duration))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Parsing

    /// Parses an SSDP reply (`HTTP/1.1 200 OK`) or `NOTIFY` advertisement. Returns nil for
    /// anything that is not a Yeelight bulb announcement (including our own looped-back search).
    static func parse(_ message: String, senderHost: String? = nil) -> YeelightDiscoveredBulb? {
        var headers: [String: String] = [:]
        for rawLine in message.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if headers[key] == nil { headers[key] = value }
        }

        guard let rawID = headers["id"], !rawID.isEmpty else { return nil }
        if let nts = headers["nts"]?.lowercased(), nts.contains("byebye") { return nil }

        var host = senderHost
        var port = 55443
        if let location = headers["location"], location.lowercased().hasPrefix("yeelight://") {
            let authority = location.dropFirst("yeelight://".count)
            let parts = authority.split(separator: ":", maxSplits: 1)
            if let h = parts.first, !h.isEmpty { host = String(h) }
            if parts.count == 2 {
                // A reply with an unparsable or out-of-range port is not a usable bulb: drop it.
                guard let p = Int(parts[1]), YeelightAddress.isValidPort(p) else { return nil }
                port = p
            }
        }
        guard let resolvedHost = host, !resolvedHost.isEmpty else { return nil }

        return YeelightDiscoveredBulb(
            id: rawID.lowercased(),
            host: resolvedHost,
            port: port,
            model: headers["model"] ?? "",
            name: headers["name"] ?? "",
            firmware: headers["fw_ver"] ?? ""
        )
    }

    // MARK: - Sockets

    private static func ipv4(_ text: String) -> in_addr? {
        var address = in_addr()
        return inet_pton(AF_INET, text, &address) == 1 ? address : nil
    }

    private static func groupSockaddr() -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = groupPort.bigEndian
        addr.sin_addr = ipv4(groupAddress) ?? in_addr()
        return addr
    }

    /// Local IPv4 addresses of interfaces that are up, multicast-capable and not loopback.
    private static func multicastInterfaceAddresses() -> [in_addr] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }

        var result: [in_addr] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_MULTICAST != 0, flags & IFF_LOOPBACK == 0,
                  let sa = entry.pointee.ifa_addr, sa.pointee.sa_family == sa_family_t(AF_INET)
            else { continue }
            let address = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            result.append(address)
        }
        return result
    }

    private static func blockingSearch(duration: TimeInterval) throws -> [YeelightDiscoveredBulb] {
        let sender = socket(AF_INET, SOCK_DGRAM, 0)
        guard sender >= 0 else {
            throw LampControlError.yeelight(NSLocalizedString("error.yeelight.search.failed", comment: ""))
        }
        defer { close(sender) }

        var bindAddr = sockaddr_in()
        bindAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        bindAddr.sin_family = sa_family_t(AF_INET)
        bindAddr.sin_addr.s_addr = INADDR_ANY
        bindAddr.sin_port = 0
        let bindResult = withUnsafePointer(to: &bindAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(sender, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw LampControlError.yeelight(NSLocalizedString("error.yeelight.search.failed", comment: ""))
        }

        var ttl: UInt8 = 4
        setsockopt(sender, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        let interfaces = multicastInterfaceAddresses()
        // Best effort: also hear NOTIFY advertisements (bulbs multicast them to the group).
        let advertisements = makeAdvertisementSocket(interfaces: interfaces)
        defer { if advertisements >= 0 { close(advertisements) } }

        var seen: [String: YeelightDiscoveredBulb] = [:]
        var order: [String] = []
        let deadline = Date().addingTimeInterval(duration)
        var sendTimes = [0.0, 1.0].map { Date().addingTimeInterval($0) }
        var anySendSucceeded = false
        var attemptedSend = false

        while true {
            let now = Date()
            if now >= deadline { break }

            if let next = sendTimes.first, now >= next {
                sendTimes.removeFirst()
                attemptedSend = true
                if sendSearch(on: sender, interfaces: interfaces) { anySendSucceeded = true }
            }

            var fds = [pollfd(fd: sender, events: Int16(POLLIN), revents: 0)]
            if advertisements >= 0 {
                fds.append(pollfd(fd: advertisements, events: Int16(POLLIN), revents: 0))
            }
            var waitUntil = deadline
            if let next = sendTimes.first, next < waitUntil { waitUntil = next }
            let timeoutMs = Int32(max(1, min(500, waitUntil.timeIntervalSince(now) * 1000)))

            let ready = poll(&fds, nfds_t(fds.count), timeoutMs)
            guard ready > 0 else { continue }

            for fd in fds where fd.revents & Int16(POLLIN) != 0 {
                guard let (text, source) = receive(from: fd.fd),
                      let bulb = parse(text, senderHost: source)
                else { continue }
                if seen[bulb.id] == nil { order.append(bulb.id) }
                seen[bulb.id] = bulb
            }
        }

        if attemptedSend && !anySendSucceeded && seen.isEmpty {
            throw LampControlError.yeelight(NSLocalizedString("error.yeelight.search.failed", comment: ""))
        }
        return order.compactMap { seen[$0] }
    }

    /// Returns true when the M-SEARCH could be sent on at least one interface.
    private static func sendSearch(on fd: Int32, interfaces: [in_addr]) -> Bool {
        var destination = groupSockaddr()
        let payload = Array(searchMessage.utf8)
        var succeeded = false

        func send() {
            let sent = withUnsafePointer(to: &destination) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, payload, payload.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if sent >= 0 { succeeded = true }
        }

        if interfaces.isEmpty {
            send()
        } else {
            for var interface in interfaces {
                setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &interface, socklen_t(MemoryLayout<in_addr>.size))
                send()
            }
        }
        return succeeded
    }

    private static func receive(from fd: Int32) -> (String, String)? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var from = sockaddr_in()
        var fromLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let count = withUnsafeMutablePointer(to: &from) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLength)
            }
        }
        guard count > 0 else { return nil }

        var address = from.sin_addr
        var hostBuffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        inet_ntop(AF_INET, &address, &hostBuffer, socklen_t(INET_ADDRSTRLEN))
        let text = String(decoding: buffer[0..<count], as: UTF8.self)
        return (text, String(cString: hostBuffer))
    }

    /// Socket bound to the SSDP port and joined to the group on every interface. Returns -1
    /// when that is not possible (e.g. another app owns the port without SO_REUSEPORT).
    private static func makeAdvertisementSocket(interfaces: [in_addr]) -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return -1 }

        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = INADDR_ANY
        addr.sin_port = groupPort.bigEndian
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { close(fd); return -1 }

        var joined = false
        for interface in interfaces {
            var membership = ip_mreq(imr_multiaddr: ipv4(groupAddress) ?? in_addr(), imr_interface: interface)
            if setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size)) == 0 {
                joined = true
            }
        }
        if !joined {
            var membership = ip_mreq(imr_multiaddr: ipv4(groupAddress) ?? in_addr(), imr_interface: in_addr(s_addr: INADDR_ANY))
            joined = setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &membership, socklen_t(MemoryLayout<ip_mreq>.size)) == 0
        }
        guard joined else { close(fd); return -1 }
        return fd
    }
}
