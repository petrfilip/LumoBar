import Foundation

/// Localization helpers for dynamic strings (format strings, computed model strings).
/// Static SwiftUI `Text("key")` / `.help("key")` calls look up keys automatically.
enum L10n {

    // MARK: - LampsView dynamic strings

    static func syncTime(_ time: String) -> String {
        String(format: NSLocalizedString("lamps.sync.time", comment: ""), time)
    }

    static func hiddenLamps(_ count: Int) -> String {
        String(format: NSLocalizedString("lamps.hidden.count", comment: ""), count)
    }

    static func onlineLamps(_ count: Int) -> String {
        String(format: NSLocalizedString("lamps.online.count", comment: ""), count)
    }

    static func captureState(_ count: Int) -> String {
        String(format: NSLocalizedString("lamps.capture.state", comment: ""), count)
    }

    static func groupSelected(_ count: Int) -> String {
        String(format: NSLocalizedString("lamps.group.selected", comment: ""), count)
    }

    static func sceneApplyPreset(_ title: String) -> String {
        String(format: NSLocalizedString("lamps.scene.apply.preset", comment: ""), title)
    }

    static func sceneApplyCapture(_ title: String) -> String {
        String(format: NSLocalizedString("lamps.scene.apply.capture", comment: ""), title)
    }

    static func sceneApplyAmbiance(_ title: String) -> String {
        String(format: NSLocalizedString("lamps.scene.apply.ambiance", comment: ""), title)
    }

    // MARK: - Sync

    static func providersConnected(_ names: String) -> String {
        String(format: NSLocalizedString("setup.providers.connected", comment: ""), names)
    }
    static var colorWhite: String   { NSLocalizedString("lamps.color.white", comment: "") }

    /// Tooltip names for `HSVColor.quickColors`, in the same order.
    static func quickColorName(_ color: HSVColor) -> String {
        let keys = ["lamps.color.white", "lamps.color.red", "lamps.color.amber",
                    "lamps.color.green", "lamps.color.blue", "lamps.color.purple"]
        guard let index = HSVColor.quickColors.firstIndex(of: color), index < keys.count else { return "" }
        return NSLocalizedString(keys[index], comment: "")
    }
    static var syncUpdating: String { NSLocalizedString("lamps.sync.updating", comment: "") }
    static var syncAuto: String     { NSLocalizedString("lamps.sync.auto", comment: "") }
    static var syncNever: String    { NSLocalizedString("sync.never", comment: "") }
    static var lampsHideOfflineHelp: String { NSLocalizedString("lamps.hide.offline.help", comment: "") }
    static var lampsShowAllHelp: String     { NSLocalizedString("lamps.show.all.help", comment: "") }

    // MARK: - Room strings

    static var roomAllOn: String          { NSLocalizedString("room.all.on", comment: "") }
    static var roomAllOff: String         { NSLocalizedString("room.all.off", comment: "") }
    static var roomAdd: String            { NSLocalizedString("room.add", comment: "") }
    static var roomEdit: String           { NSLocalizedString("room.edit", comment: "") }
    static var roomDelete: String         { NSLocalizedString("room.delete", comment: "") }
    static var roomUnassigned: String     { NSLocalizedString("room.unassigned", comment: "") }
    static var roomManage: String         { NSLocalizedString("room.manage", comment: "") }
    static var roomNamePlaceholder: String { NSLocalizedString("room.name.placeholder", comment: "") }
    static var roomPremiumMessage: String { NSLocalizedString("room.premium.message", comment: "") }

    // MARK: - Focus Mode strings

    static var focusTitle: String                { NSLocalizedString("focus.title", comment: "") }
    static var focusSubtitle: String             { NSLocalizedString("focus.subtitle", comment: "") }
    static var focusMappingAdd: String           { NSLocalizedString("focus.mapping.add", comment: "") }
    static var focusMappingEdit: String          { NSLocalizedString("focus.mapping.edit", comment: "") }
    static var focusMappingDelete: String        { NSLocalizedString("focus.mapping.delete", comment: "") }
    static var focusIdentifierPlaceholder: String { NSLocalizedString("focus.identifier.placeholder", comment: "") }
    static var focusScenePlaceholder: String     { NSLocalizedString("focus.scene.placeholder", comment: "") }
    static var focusMappingEnable: String        { NSLocalizedString("focus.mapping.enable", comment: "") }
    static var focusMappingDisabled: String      { NSLocalizedString("focus.mapping.disabled", comment: "") }
    static var focusEmptyMessage: String         { NSLocalizedString("focus.empty.message", comment: "") }
    static var focusPremiumMessage: String       { NSLocalizedString("focus.premium.message", comment: "") }

    // MARK: - Lamp status (computed String properties)

    static var statusOffline: String { NSLocalizedString("lamp.status.offline", comment: "") }
    static var statusOn: String      { NSLocalizedString("lamp.status.on", comment: "") }
    static var statusOff: String     { NSLocalizedString("lamp.status.off", comment: "") }
    static var tempWarm: String      { NSLocalizedString("lamp.temp.warm", comment: "") }
    static var tempCold: String      { NSLocalizedString("lamp.temp.cold", comment: "") }

    // MARK: - SettingsView dynamic subtitles

    static var routeSettingsActive:     String { NSLocalizedString("route.settings.sub.active", comment: "") }
    static var routeSettingsRequired:   String { NSLocalizedString("route.settings.sub.required", comment: "") }
    static var routeProvidersSubtitle:  String { NSLocalizedString("route.providers.subtitle", comment: "") }
    static var routeTuyaSubtitle:       String { NSLocalizedString("route.tuya.subtitle", comment: "") }
    static var routeHueConnected:       String { NSLocalizedString("route.hue.sub.connected", comment: "") }
    static var routeHueDisconnected:    String { NSLocalizedString("route.hue.sub.disconnected", comment: "") }
    static var routeLifxConnected:      String { NSLocalizedString("route.lifx.sub.connected", comment: "") }
    static var routeLifxDisconnected:   String { NSLocalizedString("route.lifx.sub.disconnected", comment: "") }
    static var routeGoveeConnected:     String { NSLocalizedString("route.govee.sub.connected", comment: "") }
    static var routeGoveeDisconnected:  String { NSLocalizedString("route.govee.sub.disconnected", comment: "") }
    static var routeYeeNone:            String { NSLocalizedString("route.yeelight.sub.none", comment: "") }
    static var routeNanoleafNone:       String { NSLocalizedString("route.nanoleaf.sub.none", comment: "") }
    static var routeWizNone:            String { NSLocalizedString("route.wiz.sub.none", comment: "") }
    static var routeShortcutsSubtitle:  String { NSLocalizedString("route.shortcuts.subtitle", comment: "") }
    static var routeAutomationsNone:    String { NSLocalizedString("route.automations.sub.none", comment: "") }
    static var routeCircadianDisabled:  String { NSLocalizedString("route.circadian.sub.disabled", comment: "") }
    static var routeUpdatesSubtitle:    String { NSLocalizedString("route.updates.subtitle", comment: "") }
    static var routeAboutSubtitle:      String { NSLocalizedString("route.about.subtitle", comment: "") }

    static func routeYeeConnected(_ count: Int) -> String {
        String(format: NSLocalizedString("route.yeelight.sub.connected", comment: ""), count)
    }
    static func routeNanoleafConnected(_ count: Int) -> String {
        String(format: NSLocalizedString("route.nanoleaf.sub.connected", comment: ""), count)
    }
    static func routeWizConnected(_ count: Int) -> String {
        String(format: NSLocalizedString("route.wiz.sub.connected", comment: ""), count)
    }
    static func routeAutomationsActive(_ active: Int, _ total: Int) -> String {
        String(format: NSLocalizedString("route.automations.sub.active", comment: ""), active, total)
    }
    static func routeCircadianActive(_ count: Int) -> String {
        String(format: NSLocalizedString("route.circadian.sub.active", comment: ""), count)
    }
    static func routeDevices(_ count: Int) -> String {
        String(format: NSLocalizedString("route.devices.subtitle", comment: ""), count)
    }
    static func providersSubtitle(connected: Int, upcoming: Int) -> String {
        String(format: NSLocalizedString("providers.subtitle", comment: ""), connected, upcoming)
    }
    static func devicesSubtitle(total: Int, online: Int) -> String {
        String(format: NSLocalizedString("devices.subtitle", comment: ""), total, online)
    }
    static func updatesSubtitle(version: String, build: String) -> String {
        String(format: NSLocalizedString("updates.subtitle", comment: ""), version, build)
    }
    static func automationsActive(_ count: Int) -> String {
        String(format: NSLocalizedString("automations.active.count", comment: ""), count)
    }
    static func updatesLastCheck(_ time: String) -> String {
        String(format: NSLocalizedString("updates.last.check", comment: ""), time)
    }

    // MARK: - Provider subtitles (for computed strings)

    static var providerConnected:   String { NSLocalizedString("provider.connected", comment: "") }
    static var providerTuya:        String { NSLocalizedString("provider.tuya", comment: "") }
    static var providerHue:         String { NSLocalizedString("provider.hue", comment: "") }
    static var providerLifx:        String { NSLocalizedString("provider.lifx", comment: "") }
    static var providerGovee:       String { NSLocalizedString("provider.govee", comment: "") }
    static var providerYeelight:    String { NSLocalizedString("provider.yeelight", comment: "") }
    static var providerNanoleaf:    String { NSLocalizedString("provider.nanoleaf", comment: "") }
    static var providerWiz:         String { NSLocalizedString("provider.wiz", comment: "") }

    // MARK: - Providers with count

    static func yeeConnected(_ count: Int) -> String {
        String(format: NSLocalizedString("yeelight.connected.count", comment: ""), count)
    }
    static func nanoleafConnected(_ count: Int) -> String {
        String(format: NSLocalizedString("nanoleaf.connected.count", comment: ""), count)
    }
    static func wizConnected(_ count: Int) -> String {
        String(format: NSLocalizedString("wiz.connected.count", comment: ""), count)
    }

    // MARK: - License / Premium

    static var licenseFree:              String { NSLocalizedString("license.free", comment: "") }
    static var licensePremium:           String { NSLocalizedString("license.premium", comment: "") }
    static var licenseEarlyAccess:       String { NSLocalizedString("license.early.access", comment: "") }
    static var licenseStatusFree:        String { NSLocalizedString("license.status.free", comment: "") }
    static var licenseStatusEarlyAccess: String { NSLocalizedString("license.status.early.access", comment: "") }
    static var licenseStatusPremium:     String { NSLocalizedString("license.status.premium", comment: "") }
    static var licenseNone:              String { NSLocalizedString("license.none", comment: "") }

    // MARK: - Automation actions

    static var actionPowerOff:       String { NSLocalizedString("action.power.off.all", comment: "") }
    static var actionPowerOn:        String { NSLocalizedString("action.power.on.all", comment: "") }
    static var actionApplyProfile:   String { NSLocalizedString("action.apply.profile", comment: "") }
    static var actionEnableAdaptive: String { NSLocalizedString("action.enable.adaptive", comment: "") }
    static var actionDisableAdaptive:String { NSLocalizedString("action.disable.adaptive", comment: "") }

    static func actionScene(_ name: String) -> String {
        String(format: NSLocalizedString("action.scene", comment: ""), name)
    }

    // MARK: - Shortcut actions

    static var shortcutPowerOff: String { NSLocalizedString("shortcut.power.off.all", comment: "") }
    static var shortcutPowerOn:  String { NSLocalizedString("shortcut.power.on.all", comment: "") }
    static var shortcutFocus:    String { NSLocalizedString("shortcut.scene.focus", comment: "") }
    static var shortcutRelax:    String { NSLocalizedString("shortcut.scene.relax", comment: "") }
    static var shortcutNeon:     String { NSLocalizedString("shortcut.scene.neon", comment: "") }
    static var shortcutNight:    String { NSLocalizedString("shortcut.scene.night", comment: "") }

    // MARK: - Scene presets

    static var sceneNight: String { NSLocalizedString("scene.night", comment: "") }

    // MARK: - Automation weekdays

    static var everyDay: String { NSLocalizedString("automation.everyday", comment: "") }

    static var dayLetters: [String] {
        [
            NSLocalizedString("day.mon.letter", comment: ""),
            NSLocalizedString("day.tue.letter", comment: ""),
            NSLocalizedString("day.wed.letter", comment: ""),
            NSLocalizedString("day.thu.letter", comment: ""),
            NSLocalizedString("day.fri.letter", comment: ""),
            NSLocalizedString("day.sat.letter", comment: ""),
            NSLocalizedString("day.sun.letter", comment: "")
        ]
    }

    static var dayNames: [String] {
        [
            NSLocalizedString("day.mon", comment: ""),
            NSLocalizedString("day.tue", comment: ""),
            NSLocalizedString("day.wed", comment: ""),
            NSLocalizedString("day.thu", comment: ""),
            NSLocalizedString("day.fri", comment: ""),
            NSLocalizedString("day.sat", comment: ""),
            NSLocalizedString("day.sun", comment: "")
        ]
    }

    // MARK: - App context menu

    static var menuOpen: String { NSLocalizedString("menu.open", comment: "") }
    static var menuCheckUpdates: String { NSLocalizedString("menu.check.updates", comment: "") }
    static var menuQuit: String { NSLocalizedString("menu.quit", comment: "") }

    static func menuAbout(version: String) -> String {
        String(format: NSLocalizedString("menu.about", comment: ""), version)
    }

    // MARK: - Status banner messages (AppState)

    private static func s(_ key: String) -> String { NSLocalizedString(key, comment: "") }

    // Rooms
    static var roomsSaveFailed: String  { s("status.rooms.save.failed") }
    static var roomNoOnlineLamp: String { s("status.room.no.online") }
    static var roomNoOnlineRGB: String  { s("status.room.no.rgb") }
    static func roomPower(_ on: Bool) -> String { s(on ? "status.room.on" : "status.room.off") }
    static func roomSceneApplied(_ scene: String) -> String {
        String(format: s("status.room.scene.applied"), scene)
    }
    static var focusSaveFailed: String  { s("status.focus.save.failed") }

    // Premium upsells
    static var premiumScenes: String      { s("status.premium.scenes") }
    static var premiumGroups: String      { s("status.premium.groups") }
    static var premiumAutomations: String { s("status.premium.automations") }
    static var premiumAdaptive: String    { s("status.premium.adaptive") }

    // Sync / providers
    static func lampsSynced(_ count: Int) -> String {
        String(format: s("status.lamps.synced"), count)
    }
    static var lampsNoneFound: String { s("status.lamps.none.found") }
    static var settingsSaved: String { s("status.settings.saved") }
    static var settingsSavedNoneFound: String { s("status.settings.saved.none.found") }
    /// `provider` is a brand name (Hue, LIFX, …) and is not translated.
    static func settingsUnreadable(_ provider: String) -> String {
        String(format: s("status.settings.unreadable"), provider)
    }
    static func lifxConnected(_ count: Int) -> String {
        String(format: s("status.lifx.connected"), count)
    }
    static func goveeConnected(_ count: Int) -> String {
        String(format: s("status.govee.connected"), count)
    }
    static var yeelightIPRequired: String { s("status.yeelight.ip.required") }
    static func yeelightAdded(_ count: Int) -> String {
        String(format: s("status.yeelight.added"), count)
    }
    static var yeelightRemoved: String { s("status.yeelight.removed") }
    static var nanoleafIPRequired: String { s("status.nanoleaf.ip.required") }
    static func nanoleafAdded(_ count: Int) -> String {
        String(format: s("status.nanoleaf.added"), count)
    }
    static var nanoleafRemoved: String { s("status.nanoleaf.removed") }
    static var wizIPRequired: String { s("status.wiz.ip.required") }
    static func wizAdded(_ count: Int) -> String {
        String(format: s("status.wiz.added"), count)
    }
    static var wizRemoved: String { s("status.wiz.removed") }
    static var hueNoneFound: String { s("status.hue.none.found") }
    static func hueBridgesFound(_ count: Int) -> String {
        String(format: s("status.hue.found"), count)
    }
    static var hueBridgeSelected: String  { s("status.hue.selected") }
    static var hueBridgeConnected: String { s("status.hue.connected") }
    static var hueBridgeRequired: String  { s("error.hue.bridge.required") }
    static var tuyaCredentialsIncomplete: String { s("error.tuya.credentials.incomplete") }

    // Lamps, groups, scenes
    static var selectRGBLamp: String { s("status.select.rgb") }
    static var selectLamp: String    { s("status.select.lamp") }
    static func colorApplied(_ count: Int) -> String {
        String(format: s("status.color.applied"), count)
    }
    static func groupPower(_ on: Bool) -> String { s(on ? "status.group.on" : "status.group.off") }
    static func allLampsPower(_ on: Bool) -> String { s(on ? "status.all.on" : "status.all.off") }
    static var sceneNameRequired: String { s("status.scene.name.required") }
    static func sceneUpdated(_ name: String) -> String { String(format: s("status.scene.updated"), name) }
    static func sceneCreated(_ name: String) -> String { String(format: s("status.scene.created"), name) }
    static func sceneApplied(_ name: String) -> String { String(format: s("status.scene.applied"), name) }
    static var sceneDeleted: String { s("status.scene.deleted") }
    static var scenesUnreadable: String { s("status.scenes.unreadable") }
    static var ambianceNoRGB: String { s("status.ambiance.no.rgb") }
    static func ambianceAppliedToAll(_ title: String) -> String {
        String(format: s("status.ambiance.applied.all"), title)
    }
    static func ambianceApplied(_ title: String, count: Int) -> String {
        String(format: s("status.ambiance.applied.count"), title, count)
    }

    // License
    static var premiumPurchaseRegistered: String { s("status.premium.purchase.registered") }
    static var premiumActivated: String   { s("status.premium.activated") }
    static var premiumNotDetected: String { s("status.premium.not.detected") }
    static var localStateReset: String    { s("status.local.state.reset") }
    static var licenseNotValidated: String { s("status.license.not.validated") }
    static var licenseUnreadable: String  { s("status.license.unreadable") }

    // Settings saved
    static var shortcutsSaved: String { s("status.shortcuts.saved") }
    static func automationSaved(_ name: String) -> String {
        String(format: s("status.automation.saved"), name)
    }
    static var automationDeleted: String { s("status.automation.deleted") }
    static var adaptiveSaved: String { s("status.adaptive.saved") }

    // Views
    static func circadianKeyframeBrightness(_ percent: Int) -> String {
        String(format: s("circadian.keyframe.brightness"), percent)
    }
}
