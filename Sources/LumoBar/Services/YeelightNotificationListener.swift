import Foundation
import Network

/// Keeps ONE persistent TCP connection to a Yeelight bulb and surfaces the `props`
/// notifications the bulb pushes to every open connection whenever its state changes
/// (wall switch, Yeelight app, other LAN clients…).
///
/// Threading: every piece of mutable state is confined to the private serial `queue`
/// (also used as the `NWConnection` callback queue). `onEvent` is invoked on that queue;
/// the owner is responsible for hopping to whatever actor it needs.
///
/// Reconnection: when the connection fails to open (bulb off / unreachable) or drops, a
/// new attempt is scheduled with exponential backoff (1 s, 2 s, 4 s … capped at 60 s).
/// A connection that was established and then drops is retried after ~1 s without being
/// reported as "unreachable", so a Wi-Fi blip does not flicker the lamp offline; only a
/// failed *connect attempt* is reported.
final class YeelightNotificationListener {
    enum Event {
        /// Full property snapshot (answer to the `get_prop` sent right after connecting).
        case snapshot([String: String])
        /// Changed properties only, from a `props` notification.
        case delta([String: String])
        /// A connect attempt failed or timed out. `failures` counts consecutive failures.
        case unreachable(failures: Int)
        /// An established connection was lost (a reconnect is already scheduled).
        case disconnected
    }

    static let maxBackoff: TimeInterval = 60
    private static let connectTimeout: TimeInterval = 8
    static let snapshotRequestID = 7_700_001

    let bulbID: String

    private let queue: DispatchQueue
    private let onEvent: (Event) -> Void

    // Queue-confined state.
    private var host: String
    private var port: Int
    private var running = false
    private var connection: NWConnection?
    private var generation = 0
    private var isReady = false
    /// True once this connection delivered a snapshot, i.e. it was really healthy.
    private var gotSnapshot = false
    private var buffer = Data()
    private var failures = 0
    private var backoff: TimeInterval = 1
    private var retryWork: DispatchWorkItem?
    private var timeoutWork: DispatchWorkItem?

    init(bulbID: String, host: String, port: Int, onEvent: @escaping (Event) -> Void) {
        self.bulbID = bulbID
        self.host = host
        self.port = port
        self.onEvent = onEvent
        self.queue = DispatchQueue(label: "cz.tix.lumobar.yeelight-listener.\(bulbID)")
    }

    func start() {
        queue.async { [self] in
            guard !running else { return }
            running = true
            failures = 0
            backoff = 1
            connect()
        }
    }

    func stop() {
        queue.async { [self] in
            running = false
            teardown()
        }
    }

    /// Points the listener at a new address (bulb got a new DHCP lease) and reconnects now.
    func updateEndpoint(host: String, port: Int) {
        queue.async { [self] in
            guard self.host != host || self.port != port else { return }
            self.host = host
            self.port = port
            guard running else { return }
            reconnectNowLocked()
        }
    }

    /// Drops the current connection (if any) and reconnects immediately, e.g. after wake.
    func reconnectNow() {
        queue.async { [self] in
            guard running else { return }
            reconnectNowLocked()
        }
    }

    // MARK: - Connection lifecycle (queue-confined)

    private func reconnectNowLocked() {
        teardown()
        backoff = 1
        connect()
    }

    private func connect() {
        guard running, connection == nil else { return }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            scheduleRetry()
            return
        }

        generation += 1
        let gen = generation
        isReady = false
        gotSnapshot = false
        buffer.removeAll(keepingCapacity: true)

        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 30
        tcp.keepaliveInterval = 10
        tcp.keepaliveCount = 3
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)

        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            self?.handle(state: state, generation: gen)
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == gen, !self.isReady else { return }
            self.connectionLost()
        }
        timeoutWork = timeout
        queue.asyncAfter(deadline: .now() + Self.connectTimeout, execute: timeout)

        conn.start(queue: queue)
    }

    private func handle(state: NWConnection.State, generation gen: Int) {
        guard gen == generation, let conn = connection else { return }
        switch state {
        case .ready:
            isReady = true
            timeoutWork?.cancel()
            sendSnapshotRequest(on: conn, generation: gen)
            receive(on: conn, generation: gen)
        case .waiting, .failed:
            // `.waiting` means "no route / refused, will keep retrying": we do our own backoff.
            connectionLost()
        default:
            break
        }
    }

    private func sendSnapshotRequest(on conn: NWConnection, generation gen: Int) {
        let payload: [String: Any] = [
            "id": Self.snapshotRequestID,
            "method": "get_prop",
            "params": YeelightLightProvider.propertyKeys
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: payload) else { return }
        data.append(contentsOf: [0x0D, 0x0A])
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, self.generation == gen else { return }
            if error != nil { self.connectionLost() }
        })
    }

    private func receive(on conn: NWConnection, generation gen: Int) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self, self.generation == gen else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainBuffer()
            }
            if error != nil || isComplete {
                self.connectionLost()
                return
            }
            self.receive(on: conn, generation: gen)
        }
    }

    private func drainBuffer() {
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line: Data(line))
        }
        // Defensive: never let a garbage stream without newlines grow unbounded.
        if buffer.count > 64 * 1024 { buffer.removeAll() }
    }

    private func handle(line: Data) {
        guard let event = Self.event(fromLine: line) else { return }
        if case .snapshot = event {
            failures = 0
            backoff = 1
            gotSnapshot = true
        }
        onEvent(event)
    }

    /// Pure decoding of one newline-delimited JSON line from the bulb: a `props` notification
    /// becomes `.delta`, the answer to our snapshot request becomes `.snapshot`; anything else is nil.
    static func event(fromLine line: Data) -> Event? {
        guard !line.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any]
        else { return nil }

        if let method = object["method"] as? String {
            guard method == "props", let params = object["params"] as? [String: Any] else { return nil }
            let converted = stringify(params)
            return converted.isEmpty ? nil : .delta(converted)
        }

        if let id = object["id"] as? Int, id == snapshotRequestID,
           let result = object["result"] as? [Any] {
            let values = result.map { stringify($0) }
            return .snapshot(YeelightLightProvider.propertyDictionary(fromGetProp: values))
        }
        return nil
    }

    private func connectionLost() {
        // Only a connection that delivered data counts as healthy: a bulb that
        // accepts and immediately closes (e.g. all 4 connection slots taken)
        // must back off instead of being retried every second forever.
        let wasReady = isReady && gotSnapshot
        teardown()
        guard running else { return }

        if wasReady {
            onEvent(.disconnected)
            // Quick first retry for a dropped (previously healthy) connection.
            scheduleRetry(delay: 1)
        } else {
            failures += 1
            onEvent(.unreachable(failures: failures))
            scheduleRetry()
        }
    }

    private func scheduleRetry(delay explicit: TimeInterval? = nil) {
        retryWork?.cancel()
        let base: TimeInterval
        if let explicit {
            base = explicit
        } else {
            base = backoff
            backoff = min(Self.maxBackoff, backoff * 2)
        }
        let jitter = base * Double.random(in: -0.1...0.1)
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        retryWork = work
        queue.asyncAfter(deadline: .now() + max(0.5, base + jitter), execute: work)
    }

    private func teardown() {
        retryWork?.cancel()
        retryWork = nil
        timeoutWork?.cancel()
        timeoutWork = nil
        generation += 1   // invalidates every callback of the previous connection
        isReady = false
        if let connection {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connection = nil
        buffer.removeAll(keepingCapacity: true)
    }

    // MARK: - Helpers

    static func stringify(_ params: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in params {
            out[key] = stringify(value)
        }
        return out
    }

    static func stringify(_ value: Any) -> String {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return "\(value)"
        }
    }
}
