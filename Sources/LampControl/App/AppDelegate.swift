import AppKit
import Combine
import QuartzCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let appState = AppState()
    private var cancellables = Set<AnyCancellable>()
    private let globalShortcutService = GlobalShortcutService()
    private var contextMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        appState.updateService.start()
        configureShortcuts()
        appState.startAutomationScheduler()
        appState.startCircadianService()
    }

    private func configurePopover() {
        popover.contentSize = appState.preferredPopoverSize
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: ControlCenterView().environmentObject(appState))
        appState.closePopover = { [weak self] in self?.popover.performClose(nil) }

        // PERF: previously we re-ran `updatePopoverSize` on every `objectWillChange`
        // (debounced 180ms). On a live system with sync polling this triggers a
        // continuous resize/layout loop in SwiftUI — main cause of the 3 FPS popover.
        // We now resize only on key layout-affecting events.
        Publishers.MergeMany(
            appState.$selectedTab.map { _ in () }.eraseToAnyPublisher(),
            appState.$expandedLampIds.map { _ in () }.eraseToAnyPublisher(),
            appState.$isGroupPanelExpanded.map { _ in () }.eraseToAnyPublisher(),
            appState.$message.map { _ in () }.eraseToAnyPublisher(),
            appState.$hideOfflineLamps.map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            self?.updatePopoverSize(animated: false)
        }
        .store(in: &cancellables)

        // Resize when the lamp list shape changes (count / visibility), not on every property update.
        appState.$lamps
            .map { lamps in lamps.map { "\($0.id):\($0.online)" }.joined(separator: ",") }
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePopoverSize(animated: false)
            }
            .store(in: &cancellables)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusItemIcon(for: item)
        item.button?.imagePosition = .imageOnly
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item

        // PERF: only refresh status item icon when state truly impacting the icon changes.
        Publishers.MergeMany(
            appState.$lamps
                .map { lamps in lamps.contains { $0.power && $0.online } }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher(),
            appState.$circadianSettings
                .map { $0.isEnabled }
                .removeDuplicates()
                .map { _ in () }
                .eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
        .sink { [weak self] _ in
            if let item = self?.statusItem {
                self?.updateStatusItemIcon(for: item)
            }
        }
        .store(in: &cancellables)
    }
    
    private func updateStatusItemIcon(for item: NSStatusItem) {
        let hasActiveLamp = appState.lamps.contains { $0.power && $0.online }
        let isCircadianActive = appState.circadianSettings.isEnabled
        
        let symbolName = hasActiveLamp ? "lightbulb.fill" : "lightbulb"
        item.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LampControl")
        
        // Tint color based on state
        if hasActiveLamp {
            item.button?.contentTintColor = NSColor(red: 0.96, green: 0.67, blue: 0.16, alpha: 1.0)
        } else if isCircadianActive {
            item.button?.contentTintColor = NSColor(red: 0.96, green: 0.77, blue: 0.26, alpha: 1.0)
        } else {
            item.button?.contentTintColor = nil
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        guard let button = statusItem?.button else { return }

        let menu = NSMenu()

        let openItem = NSMenuItem(title: L10n.menuOpen, action: #selector(togglePopover), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let updateItem = NSMenuItem(title: L10n.menuCheckUpdates, action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        updateItem.isEnabled = appState.updateService.canCheckForUpdates
        menu.addItem(updateItem)

        let aboutItem = NSMenuItem(title: L10n.menuAbout(version: appState.updateService.currentVersion), action: nil, keyEquivalent: "")
        aboutItem.isEnabled = false
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: L10n.menuQuit, action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        contextMenu = menu
        statusItem?.menu = menu
        button.performClick(nil)
        statusItem?.menu = nil
    }

    private func configureShortcuts() {
        globalShortcutService.onAction = { [weak self] action in
            Task { @MainActor in self?.appState.executeShortcutAction(action) }
        }
        globalShortcutService.start(with: appState.shortcutSettings.bindings)

        NotificationCenter.default.addObserver(forName: .shortcutSettingsDidChange, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.globalShortcutService.start(with: self.appState.shortcutSettings.bindings)
            }
        }
    }

    @objc private func checkForUpdates() {
        appState.updateService.checkForUpdates()
    }

    @objc private func quitApp() {
        appState.quit()
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            updatePopoverSize(animated: false)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func updatePopoverSize(animated: Bool) {
        let size = appState.preferredPopoverSize

        guard popover.contentSize != size else { return }

        if animated, popover.isShown {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.10
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                popover.contentSize = size
            }
        } else {
            popover.contentSize = size
        }
    }
}
