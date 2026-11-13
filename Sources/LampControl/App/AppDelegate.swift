import AppKit
import Combine
import OSLog
import QuartzCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let appState = AppState()
    private var cancellables = Set<AnyCancellable>()
    private var contextMenu: NSMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configurePopover()
        configureStatusItem()
        appState.updateService.start()
        appState.startAutomationScheduler()
        appState.startCircadianService()
    }

    /// Handles `lampcontrol://focus?mode=<identifier|off>` (Shortcuts automations).
    /// Deliberately does not touch the popover or activate the app.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == FocusAutomationURL.scheme {
            appState.handleFocusURL(url)
        }
    }

    private func configurePopover() {
        popover.contentSize = appState.preferredPopoverSize
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        let hosting = NSHostingController(rootView: ControlCenterView().environmentObject(appState))
        // The popover size is driven explicitly by `updatePopoverSize`. Letting the
        // hosting controller also publish SwiftUI's ideal size made the popover
        // resize itself right after `show`, which shifted it away from the icon.
        hosting.sizingOptions = []
        popover.contentViewController = hosting
        appState.closePopover = { [weak self] in self?.popover.performClose(nil) }

        // Keep the popover as tall as SwiftUI's frame (`preferredPopoverSize`).
        // Enumerating the publishers that affect the height (tab, expanded rows,
        // search text, rooms, auto-sync banner...) kept missing some, so instead
        // every state change schedules one check that compares the computed size
        // with the current content size and only sets it when they differ.
        // PERF: the check is skipped while the popover is hidden (background sync
        // polling costs nothing; `togglePopover` sizes it before showing) and
        // throttled, with a trailing pass so the final state is always applied.
        appState.objectWillChange
            .throttle(for: .milliseconds(120), scheduler: RunLoop.main, latest: true)
            .sink { [weak self] _ in
                // `objectWillChange` fires before the new values are stored: read
                // them on the next main-queue turn.
                DispatchQueue.main.async {
                    guard let self, self.popover.isShown else { return }
                    self.updatePopoverSize(animated: false)
                }
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
            // Signature of what the icon shows: the leading active lamp and its
            // color / white temperature, so color changes repaint the icon too.
            Publishers.CombineLatest(appState.$lamps, appState.$lampOrderIds)
                // @Published emits before the property is set: use the emitted values.
                .map { lamps, order -> String in
                    guard let lamp = Self.leadingActiveLamp(in: lamps, order: order) else { return "off" }
                    let color = lamp.color.map { "\($0.h),\($0.s)" } ?? "-"
                    return "\(lamp.id)|\(lamp.workMode ?? "-")|\(color)|\(lamp.temperature ?? -1)"
                }
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

    /// First powered-on, online lamp in the user's lamp order.
    private static func leadingActiveLamp(in lamps: [LampDevice], order: [String]) -> LampDevice? {
        let active = lamps.filter { $0.power && $0.online }
        guard !order.isEmpty else { return active.first }
        let orderIndex = Dictionary(order.enumerated().map { ($1, $0) },
                                    uniquingKeysWith: { first, _ in first })
        return active.min { (orderIndex[$0.id] ?? Int.max) < (orderIndex[$1.id] ?? Int.max) }
    }

    private func updateStatusItemIcon(for item: NSStatusItem) {
        let activeLamp = Self.leadingActiveLamp(in: appState.lamps, order: appState.lampOrderIds)
        let isCircadianActive = appState.circadianSettings.isEnabled

        // A lit lamp: show a bulb filled with the color it is emitting.
        if let activeLamp,
           let tint = StatusItemIcon.tint(for: activeLamp),
           let image = StatusItemIcon.image(fill: tint) {
            item.button?.image = image
            item.button?.contentTintColor = nil
            return
        }

        let symbolName = activeLamp != nil ? "lightbulb.fill" : "lightbulb"
        item.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LampControl")

        // Tint color based on state
        if activeLamp != nil {
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
            let (view, rect) = popoverAnchor(for: button)
            // Size for the display the popover will open on *before* showing
            // it: resizing right after `show` made it jump / reposition.
            if let screen = view.window?.screen,
               appState.popoverScreenVisibleHeight != screen.visibleFrame.height {
                appState.popoverScreenVisibleHeight = screen.visibleFrame.height
            }
            updatePopoverSize(animated: false)
            popover.show(relativeTo: rect, of: view, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            logPopoverPlacement(anchor: rect, in: view, phase: "show")

            // Safety net: once layout has settled (first show on a display with
            // a different scale, late SwiftUI layout), re-anchor the popover so
            // it never stays shifted next to the icon.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.popover.isShown else { return }
                self.popover.positioningRect = rect
                self.logPopoverPlacement(anchor: rect, in: view, phase: "settled")
            }
        }
    }

    private static let popoverLog = Logger(subsystem: "fr.hugoinformatique.lampcontrol", category: "Popover")

    /// Logs where the popover ended up relative to its anchor, to diagnose
    /// placement reports: `log show --predicate 'category == "Popover"' --last 10m`
    private func logPopoverPlacement(anchor rect: NSRect, in view: NSView, phase: String) {
        guard let anchorWindow = view.window,
              let popoverFrame = popover.contentViewController?.view.window?.frame else { return }
        let anchorFrame = anchorWindow.convertToScreen(view.convert(rect, to: nil))
        let offset = popoverFrame.midX - anchorFrame.midX
        Self.popoverLog.info("""
        \(phase, privacy: .public) anchor=\(NSStringFromRect(anchorFrame), privacy: .public) \
        popover=\(NSStringFromRect(popoverFrame), privacy: .public) dx=\(offset, privacy: .public) \
        screen=\(anchorWindow.screen?.localizedName ?? "?", privacy: .public) \
        scale=\(anchorWindow.screen?.backingScaleFactor ?? 0, privacy: .public) \
        mouse=\(NSStringFromPoint(NSEvent.mouseLocation), privacy: .public)
        """)
    }

    /// Invisible window used to anchor the popover on the right display.
    private lazy var anchorWindow: NSWindow = {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        return window
    }()

    /// With several displays every menu bar shows the status item, but the
    /// button's window lives on one of them (typically the last active one)
    /// at the moment of the click — anchoring to it opened the popover on
    /// the "other" monitor. When the click happened in another display's menu
    /// bar, anchor to an invisible window placed right under the cursor there.
    private func popoverAnchor(for button: NSStatusBarButton) -> (NSView, NSRect) {
        let fallback: (NSView, NSRect) = (button, button.bounds)
        guard let buttonWindow = button.window else { return fallback }

        let mouse = NSEvent.mouseLocation
        guard let clickScreen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
              clickScreen != buttonWindow.screen
        else { return fallback }

        // Only when the click is in that screen's menu bar (not e.g. "Open"
        // chosen from the context menu).
        let menuBarHeight = max(NSStatusBar.system.thickness, clickScreen.frame.maxY - clickScreen.visibleFrame.maxY)
        guard mouse.y >= clickScreen.frame.maxY - menuBarHeight - 2 else { return fallback }

        let buttonFrame = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = NSRect(
            x: mouse.x - buttonFrame.width / 2,
            y: clickScreen.frame.maxY - menuBarHeight,
            width: buttonFrame.width,
            height: menuBarHeight
        )
        anchorWindow.setFrame(frame, display: false)
        anchorWindow.orderFrontRegardless()
        guard let content = anchorWindow.contentView else { return fallback }
        return (content, content.bounds)
    }

    func popoverDidClose(_ notification: Notification) {
        anchorWindow.orderOut(nil)
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
