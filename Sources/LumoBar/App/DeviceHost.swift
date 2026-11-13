import Foundation

/// Identity of a LAN device by its address, used to reject adding the same WiZ / Nanoleaf
/// device twice (a duplicate would also create two lamps with the same id).
enum DeviceHost {
    /// Trimmed and lower-cased: hostnames are case-insensitive, IPs have no letters but "::A" style IPv6 does.
    static func normalized(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func isDuplicate(_ host: String, among existing: [String]) -> Bool {
        let wanted = normalized(host)
        return existing.contains { normalized($0) == wanted }
    }
}
