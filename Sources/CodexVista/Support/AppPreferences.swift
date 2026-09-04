import SwiftUI

enum AppPreferenceKeys {
    static let colorScheme = "appearance.colorScheme"
    static let skin = "appearance.skin"
    static let keepsDashboardOnTop = "dashboard.keepsOnTop"
    static let dashboardCloseBehavior = "dashboard.closeBehavior"
    static let automaticRefreshEnabled = "data.automaticRefreshEnabled"
    static let usageRemindersEnabled = "usageReminders.enabled"
    static let remindsAtTwentyPercent = "usageReminders.thresholds.twenty"
    static let remindsAtTenPercent = "usageReminders.thresholds.ten"
    static let remindsAtFivePercent = "usageReminders.thresholds.five"
    static let usageReminderCheckpoint = "usageReminders.checkpoint.v1"
    static let showsLivePreview = "menuBar.showsLivePreview"
    static let summaryPlacement = "menuBar.summaryPlacement"
    static let showsResetCountdown = "menuBar.showsResetCountdown"
    static let quotaDisplay = "menuBar.quotaDisplay"
    static let firstSubscriptionDate = "subscription.firstSubscribedAt"
    static let automaticallyChecksForUpdates = "updates.automaticallyChecks"
    static let automaticallyDownloadsUpdates = "updates.automaticallyDownloads"
}

enum AppTooltipConfiguration {
    static func apply(to defaults: UserDefaults = .standard) {
        defaults.set(500, forKey: "NSInitialToolTipDelay")
    }
}

enum AppColorSchemePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    static func resolved(from rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .system
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(forKey: AppPreferenceKeys.colorScheme) else {
            return .system
        }
        return resolved(from: rawValue)
    }
}

enum AppSkinPreference: String, CaseIterable, Identifiable, Sendable {
    case standard
    case ink

    var id: Self { self }
    var title: String { self == .ink ? "水墨" : "经典" }

    func effectiveColorScheme(for preference: AppColorSchemePreference) -> ColorScheme? {
        self == .ink ? .light : preference.colorScheme
    }

    static func resolved(from rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .standard
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        resolved(from: defaults.string(forKey: AppPreferenceKeys.skin) ?? "")
    }
}

enum SubscriptionCyclePreference {
    static func load(from defaults: UserDefaults = .standard) -> Date? {
        guard defaults.object(forKey: AppPreferenceKeys.firstSubscriptionDate) != nil else {
            return nil
        }
        let timestamp = defaults.double(forKey: AppPreferenceKeys.firstSubscriptionDate)
        guard timestamp.isFinite, timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: timestamp)
    }
}

struct SubscriptionCycle: Equatable, Sendable {
    let start: Date
    let end: Date
}

enum SubscriptionCycleCalculator {
    static func cycle(
        containing date: Date,
        firstSubscribedAt: Date,
        calendar: Calendar
    ) -> SubscriptionCycle? {
        guard firstSubscribedAt <= date else { return nil }

        let firstComponents = calendar.dateComponents([.year, .month], from: firstSubscribedAt)
        let dateComponents = calendar.dateComponents([.year, .month], from: date)
        guard let firstYear = firstComponents.year,
              let firstMonth = firstComponents.month,
              let dateYear = dateComponents.year,
              let dateMonth = dateComponents.month else {
            return nil
        }

        var cycleIndex = max(0, (dateYear - firstYear) * 12 + dateMonth - firstMonth)
        guard var start = boundary(
            cycleIndex: cycleIndex,
            firstSubscribedAt: firstSubscribedAt,
            calendar: calendar
        ) else {
            return nil
        }

        if start > date {
            cycleIndex -= 1
            guard cycleIndex >= 0,
                  let previousStart = boundary(
                    cycleIndex: cycleIndex,
                    firstSubscribedAt: firstSubscribedAt,
                    calendar: calendar
                  ) else {
                return nil
            }
            start = previousStart
        }

        guard let end = boundary(
            cycleIndex: cycleIndex + 1,
            firstSubscribedAt: firstSubscribedAt,
            calendar: calendar
        ) else {
            return nil
        }
        return SubscriptionCycle(start: start, end: end)
    }

    private static func boundary(
        cycleIndex: Int,
        firstSubscribedAt: Date,
        calendar: Calendar
    ) -> Date? {
        calendar.date(byAdding: .month, value: cycleIndex, to: firstSubscribedAt)
    }
}

enum DashboardCloseBehavior: String, CaseIterable, Identifiable, Sendable {
    case closeDashboard
    case quitApplication

    var id: Self { self }

    var terminatesApplication: Bool {
        self == .quitApplication
    }

    static func resolved(from rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? .closeDashboard
    }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let rawValue = defaults.string(
            forKey: AppPreferenceKeys.dashboardCloseBehavior
        ) else {
            return .closeDashboard
        }
        return resolved(from: rawValue)
    }
}

enum QuotaDisplayPreference: String, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    var id: Self { self }
}

enum SummaryPlacementPreference: String, CaseIterable, Identifiable, Sendable {
    case notch
    case menuBar

    var id: Self { self }

    static func load(from defaults: UserDefaults = .standard) -> Self {
        Self(rawValue: defaults.string(forKey: AppPreferenceKeys.summaryPlacement) ?? "") ?? .menuBar
    }
}

struct MenuBarLabelConfiguration: Equatable, Sendable {
    let showsLivePreview: Bool
    let quotaDisplay: QuotaDisplayPreference
    let showsFiveHour: Bool
    let showsWeekly: Bool
    let showsResetCountdown: Bool

    static let standard = MenuBarLabelConfiguration(
        showsLivePreview: true,
        quotaDisplay: .remaining,
        showsFiveHour: false,
        showsWeekly: true,
        showsResetCountdown: true
    )
}
