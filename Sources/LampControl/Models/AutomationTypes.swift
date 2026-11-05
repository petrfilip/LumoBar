import Foundation

enum AutomationAction: Codable, Equatable, Hashable {
    case powerOffAll
    case powerOnAll
    case applyScenePreset(id: String)
    case applyProfile(id: UUID)
    case enableAdaptiveLighting
    case disableAdaptiveLighting

    var title: String {
        switch self {
        case .powerOffAll:              return L10n.actionPowerOff
        case .powerOnAll:               return L10n.actionPowerOn
        case .applyScenePreset(let id): return L10n.actionScene(LightScenePreset.preset(id: id)?.title ?? id.capitalized)
        case .applyProfile:             return L10n.actionApplyProfile
        case .enableAdaptiveLighting:   return L10n.actionEnableAdaptive
        case .disableAdaptiveLighting:  return L10n.actionDisableAdaptive
        }
    }

    var icon: String {
        switch self {
        case .powerOffAll:            return "power"
        case .powerOnAll:             return "power.circle.fill"
        case .applyScenePreset:       return "paintpalette.fill"
        case .applyProfile:           return "square.stack.3d.up.fill"
        case .enableAdaptiveLighting: return "sun.and.horizon.fill"
        case .disableAdaptiveLighting:return "sun.and.horizon"
        }
    }
}

struct Automation: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var isEnabled: Bool = true
    var hour: Int
    var minute: Int
    var weekdays: Set<Int> = []   // empty = every day; 1=Mon … 7=Sun
    var action: AutomationAction
    var lastFiredDate: Date?

    var timeString: String {
        String(format: "%02d:%02d", hour, minute)
    }

    var weekdaysLabel: String {
        if weekdays.isEmpty { return L10n.everyDay }
        return weekdays.sorted().compactMap { L10n.dayNames[safe: $0 - 1] }.joined(separator: ", ")
    }

    func shouldFire(at date: Date, calendar: Calendar) -> Bool {
        guard isEnabled else { return false }
        let comps = calendar.dateComponents([.hour, .minute, .weekday], from: date)
        guard comps.hour == hour, comps.minute == minute else { return false }
        if !weekdays.isEmpty {
            let wd = ((comps.weekday ?? 1) + 5) % 7 + 1
            guard weekdays.contains(wd) else { return false }
        }
        return true
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard index >= 0, index < count else { return nil }
        return self[index]
    }
}
