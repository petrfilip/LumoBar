import Foundation

/// Shared URLSessions with sane request timeouts. `URLSession.shared` waits 60 s, which lets a
/// dead LAN device block the UI and the command queues for a minute.
enum ServiceSession {
    /// LAN devices (Hue bridge, Nanoleaf): they answer within milliseconds or not at all.
    static let lan = make(timeout: 5)
    /// Cloud APIs (LIFX, Govee, Tuya): allow for slow links and server latency.
    static let cloud = make(timeout: 15)

    /// `timeout` bounds both the idle time of a request and the whole resource transfer.
    static func make(timeout: TimeInterval, protocolClasses: [AnyClass]? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        if let protocolClasses { configuration.protocolClasses = protocolClasses }
        return URLSession(configuration: configuration)
    }
}

/// Lock-protected lamp table shared by the providers. The providers are called concurrently
/// (polls, commands, group actions), so the plain dictionaries they used before could be
/// mutated from several tasks at once.
final class LampCache: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: LampDevice] = [:]

    subscript(id: String) -> LampDevice? {
        lock.lock(); defer { lock.unlock() }
        return storage[id]
    }

    /// Replaces the whole table (after a poll).
    func replace(with lamps: [LampDevice]) {
        let table = Dictionary(firstWins: lamps.map { ($0.nativeID, $0) })
        lock.lock(); defer { lock.unlock() }
        storage = table
    }

    /// Applies `mutate` atomically to one lamp. Returns nil when the lamp is unknown.
    func update(_ id: String, _ mutate: (inout LampDevice) -> Void) -> LampDevice? {
        lock.lock(); defer { lock.unlock() }
        guard var lamp = storage[id] else { return nil }
        mutate(&lamp)
        storage[id] = lamp
        return lamp
    }
}

extension Dictionary {
    /// Builds a dictionary from pairs whose keys come from settings or the network and may
    /// repeat (`Dictionary(uniqueKeysWithValues:)` traps on a duplicate). The first value wins.
    init<S: Sequence>(firstWins pairs: S) where S.Element == (Key, Value) {
        self.init(pairs, uniquingKeysWith: { first, _ in first })
    }
}

extension Sequence {
    /// Drops later elements whose key was already seen, keeping the original order.
    func uniqued<K: Hashable>(by key: (Element) -> K) -> [Element] {
        var seen = Set<K>()
        return filter { seen.insert(key($0)).inserted }
    }
}
