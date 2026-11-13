import AppKit

@main
struct LumoBarMain {
    @MainActor
    static func main() {
        // First of all, before anything reads a setting: the stores, the defaults and Sparkle all
        // load while the `AppState` is created, and the import fills them. Runs once.
        let legacyImport = LegacyImport().runIfNeeded()

        let app = NSApplication.shared
        let delegate = AppDelegate(legacyImport: legacyImport)

        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
