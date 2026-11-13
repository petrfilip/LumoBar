import Foundation

/// Where LampControl keeps its files. The folder name is part of the on-disk format: existing
/// users' data lives there, so it must never change.
enum AppDirectories {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LampControl", isDirectory: true)
    }
}

/// What a store did to keep a file it could not (fully) read, so the user can be told once.
struct DataRecovery: Equatable {
    enum Kind: Equatable {
        /// The whole file was unreadable: it was moved aside and defaults are used.
        case unreadable
        /// Some entries were unreadable and dropped: the original was copied aside first.
        case partial(skipped: Int)
    }

    let fileName: String
    let backupName: String
    let kind: Kind
}

/// Collects `DataRecovery` events while the stores load, for `AppState` to show once.
final class RecoveryLog {
    static let shared = RecoveryLog()

    private let lock = NSLock()
    private var events: [DataRecovery] = []

    func record(_ event: DataRecovery) {
        lock.lock(); defer { lock.unlock() }
        events.append(event)
    }

    /// Returns the events recorded since the last call and forgets them.
    func drain() -> [DataRecovery] {
        lock.lock(); defer { lock.unlock() }
        defer { events = [] }
        return events
    }
}

// MARK: - Tolerant decoding

/// Counts the array elements `decodeLossyArray` / `LossyList` had to skip during one decode.
final class SkippedCounter {
    var count = 0
}

extension CodingUserInfoKey {
    static let skippedElements = CodingUserInfoKey(rawValue: "LampControl.skippedElements")!
}

/// One array element that may fail to decode (an unknown enum value, a missing field) without
/// failing the whole array.
private struct LossyElement<Element: Decodable>: Decodable {
    let value: Element?

    init(from decoder: Decoder) throws {
        do {
            value = try Element(from: decoder)
        } catch {
            value = nil
            (decoder.userInfo[.skippedElements] as? SkippedCounter)?.count += 1
            NSLog("LampControl: skipped an unreadable \(Element.self) entry: \(error)")
        }
    }
}

extension KeyedDecodingContainer {
    /// Decodes an array element by element, skipping (and counting) entries that fail. A missing
    /// or `null` key gives `defaultValue`.
    func decodeLossyArray<Element: Decodable>(_ type: Element.Type, forKey key: Key,
                                              default defaultValue: [Element] = []) throws -> [Element] {
        guard contains(key), try !decodeNil(forKey: key) else { return defaultValue }
        return try decode([LossyElement<Element>].self, forKey: key).compactMap(\.value)
    }
}

/// A top-level JSON array that survives bad elements.
struct LossyList<Element: Codable>: Codable {
    var items: [Element]

    init(_ items: [Element]) { self.items = items }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        items = try container.decode([LossyElement<Element>].self).compactMap(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(items)
    }
}

// MARK: - JSONFileStore

/// One JSON file in the support folder.
///
/// Corrupt-file policy (the same for every persisted file):
/// - **Missing file**: the default value is returned; nothing is written.
/// - **Unreadable file** (not valid JSON, or not the expected shape): the file is *moved* to
///   `<name>.corrupt-<timestamp>.json` next to it, never deleted or overwritten, a `DataRecovery`
///   is recorded for the UI to show once, and the app continues with the default. Because the
///   file is gone from its original name, the next `save` writes a fresh file without losing the
///   old one. If the file cannot be moved, `load` throws and `save` keeps refusing until the move
///   succeeds, so the original is never overwritten either.
/// - **Partly unreadable file** (some array entries skipped by `decodeLossyArray` / `LossyList`,
///   e.g. an enum case written by a newer version): the good entries are returned and the
///   untouched original is *copied* to `<name>.corrupt-<timestamp>.json` (once per distinct
///   content) so the skipped entries stay recoverable.
/// - **I/O error while reading** (permissions, ...): `load` throws and touches nothing.
final class JSONFileStore<Value: Codable> {
    let url: URL
    private let directory: URL
    private let baseName: String
    private let defaultValue: Value
    private let recovery: RecoveryLog
    private let now: () -> Date
    private var moveAsidePending = false

    init(directory: URL = AppDirectories.support, fileName: String, defaultValue: Value,
         recovery: RecoveryLog = .shared, now: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.url = directory.appendingPathComponent(fileName)
        self.baseName = (fileName as NSString).deletingPathExtension
        self.defaultValue = defaultValue
        self.recovery = recovery
        self.now = now
    }

    /// Whether the file exists (even if it is empty or unreadable).
    var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    func load() throws -> Value {
        guard exists else { return defaultValue }
        let data = try Data(contentsOf: url)

        let counter = SkippedCounter()
        let decoder = JSONDecoder()
        decoder.userInfo[.skippedElements] = counter
        let value: Value
        do {
            value = try decoder.decode(Value.self, from: data)
        } catch {
            NSLog("LampControl: \(url.lastPathComponent) is unreadable: \(error)")
            try moveAside(kind: .unreadable)
            return defaultValue
        }
        if counter.count > 0 {
            keepCopy(of: data, skipped: counter.count)
        }
        return value
    }

    func save(_ value: Value) throws {
        if moveAsidePending {
            try moveAside(kind: .unreadable)
        }
        let data = try JSONEncoder().encode(value)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    // MARK: Backups

    private func backupURL() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: now())
        var candidate = directory.appendingPathComponent("\(baseName).corrupt-\(stamp).json")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName).corrupt-\(stamp)-\(n).json")
            n += 1
        }
        return candidate
    }

    private func moveAside(kind: DataRecovery.Kind) throws {
        let target = backupURL()
        do {
            try FileManager.default.moveItem(at: url, to: target)
            moveAsidePending = false
        } catch {
            moveAsidePending = true
            throw error
        }
        recovery.record(DataRecovery(fileName: url.lastPathComponent, backupName: target.lastPathComponent, kind: kind))
    }

    private func keepCopy(of data: Data, skipped: Int) {
        let existing = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in existing where name.hasPrefix("\(baseName).corrupt-") {
            if let old = try? Data(contentsOf: directory.appendingPathComponent(name)), old == data {
                return   // this exact content was already backed up (and reported) by an earlier launch
            }
        }
        let target = backupURL()
        do {
            try data.write(to: target, options: .atomic)
            recovery.record(DataRecovery(fileName: url.lastPathComponent, backupName: target.lastPathComponent,
                                         kind: .partial(skipped: skipped)))
        } catch {
            NSLog("LampControl: could not back up \(url.lastPathComponent): \(error)")
        }
    }
}

/// `JSONFileStore` for a top-level array whose bad elements are skipped, not fatal.
final class JSONListStore<Element: Codable> {
    private let file: JSONFileStore<LossyList<Element>>

    init(directory: URL = AppDirectories.support, fileName: String,
         recovery: RecoveryLog = .shared, now: @escaping () -> Date = Date.init) {
        file = JSONFileStore(directory: directory, fileName: fileName, defaultValue: LossyList([]),
                             recovery: recovery, now: now)
    }

    var exists: Bool { file.exists }
    var url: URL { file.url }
    func load() throws -> [Element] { try file.load().items }
    func save(_ items: [Element]) throws { try file.save(LossyList(items)) }
}
