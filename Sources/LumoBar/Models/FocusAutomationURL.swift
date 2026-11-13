import Foundation

/// `lampcontrol://focus?mode=<identifier>` — driven by Shortcuts automations
/// ("When <Focus> turns on/off" → "Open URLs"), because macOS exposes no API
/// that tells a third-party app *which* Focus is active.
enum FocusAutomationURL {
    static let scheme = "lampcontrol"
    static let host = "focus"
    /// Reserved mode value that clears the current Focus.
    static let offMode = "off"

    enum Event: Equatable {
        case activate(mode: String)
        case off
    }

    /// Parses an incoming URL. Returns nil if it is not a well-formed focus URL.
    static func parse(_ url: URL) -> Event? {
        guard url.scheme?.lowercased() == scheme,
              url.host?.lowercased() == host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "mode" })?.value
        else { return nil }

        let mode = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !mode.isEmpty else { return nil }
        return mode.caseInsensitiveCompare(offMode) == .orderedSame ? .off : .activate(mode: mode)
    }

    /// Builds the URL string to paste in a Shortcuts "Open URLs" action.
    static func urlString(forMode mode: String) -> String {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [URLQueryItem(name: "mode", value: mode)]
        return components.string ?? "\(scheme)://\(host)?mode=\(mode)"
    }
}
