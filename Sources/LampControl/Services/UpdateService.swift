import Combine
import Foundation
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` and exposes its preferences
/// as `@Published` bindings so SwiftUI toggles can read AND persist them.
///
/// The previous version held the toggles in plain @Published properties with
/// no link back to Sparkle: the UI changed, nothing happened, and the values
/// reset to `false` on every launch. We now read the current Sparkle state on
/// init and forward every change back to `SPUUpdater`, which persists the
/// settings in `UserDefaults` automatically (under the SUEnableAutomaticChecks
/// / SUAutomaticallyUpdate keys).
@MainActor
final class UpdateService: NSObject, ObservableObject {
    @Published private(set) var lastCheckedAt: Date?

    @Published var automaticChecksEnabled: Bool {
        didSet {
            guard !syncingFromSparkle else { return }
            updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        }
    }

    @Published var automaticDownloadsEnabled: Bool {
        didSet {
            guard !syncingFromSparkle else { return }
            updaterController.updater.automaticallyDownloadsUpdates = automaticDownloadsEnabled
        }
    }

    /// False when the bundle has no valid Sparkle EdDSA public key — e.g. a
    /// build from source, where CI never injected `SUPublicEDKey`. Sparkle
    /// cannot verify updates then and shows "Unable to Check for Updates" on
    /// every launch, so the updater is not started at all.
    let isAvailable: Bool

    private let updaterController: SPUStandardUpdaterController
    private var syncingFromSparkle = false
    private var cancellables = Set<AnyCancellable>()

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    var currentBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    var feedURL: String {
        updaterController.updater.feedURL?.absoluteString ?? ""
    }

    var canCheckForUpdates: Bool {
        isAvailable && updaterController.updater.canCheckForUpdates
    }

    /// A Sparkle EdDSA public key is a base64-encoded 32-byte Ed25519 key.
    private static var hasValidPublicKey: Bool {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let data = Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return data.count == 32
    }

    override init() {
        let available = Self.hasValidPublicKey
        self.isAvailable = available
        let controller = SPUStandardUpdaterController(
            startingUpdater: available,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        // Seed the published properties from Sparkle's persisted state so the
        // toggles reflect reality immediately after launch.
        self.automaticChecksEnabled    = available && controller.updater.automaticallyChecksForUpdates
        self.automaticDownloadsEnabled = available && controller.updater.automaticallyDownloadsUpdates
        super.init()

        // Reflect Sparkle's last update check date back into the UI.
        controller.updater.publisher(for: \.lastUpdateCheckDate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] date in self?.lastCheckedAt = date }
            .store(in: &cancellables)
    }

    func start() {
        guard isAvailable else { return }
        // The updater is already running (started in init via `startingUpdater: true`).
        // If automatic checks are enabled, kick off one check now so the user gets
        // an answer when they open the popover after launch — the daily Sparkle
        // schedule alone can leave them waiting hours.
        if updaterController.updater.automaticallyChecksForUpdates,
           updaterController.updater.canCheckForUpdates {
            updaterController.updater.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard isAvailable else { return }
        updaterController.checkForUpdates(nil)
        lastCheckedAt = Date()
    }
}
