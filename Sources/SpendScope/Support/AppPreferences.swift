import SwiftUI

enum AppPreferenceKeys {
    static let keepsDashboardOnTop = "dashboard.keepsOnTop"
    static let dashboardCloseBehavior = "dashboard.closeBehavior"
    static let automaticRefreshEnabled = "data.automaticRefreshEnabled"
    static let usageRemindersEnabled = "usageReminders.enabled"
    static let remindsFiveHour = "usageReminders.quotas.fiveHour"
    static let remindsWeekly = "usageReminders.quotas.weekly"
    static let remindsAtTwentyPercent = "usageReminders.thresholds.twenty"
    static let remindsAtTenPercent = "usageReminders.thresholds.ten"
    static let remindsAtFivePercent = "usageReminders.thresholds.five"
    static let usageReminderCheckpoint = "usageReminders.checkpoint.v1"
    static let showsLivePreview = "menuBar.showsLivePreview"
    static let showsResetCountdown = "menuBar.showsResetCountdown"
    static let quotaDisplay = "menuBar.quotaDisplay"
    static let showsFiveHour = "menuBar.showsFiveHour"
    static let showsWeekly = "menuBar.showsWeekly"
    static let automaticallyChecksForUpdates = "updates.automaticallyChecks"
    static let automaticallyDownloadsUpdates = "updates.automaticallyDownloads"
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

struct MenuBarLabelConfiguration: Equatable, Sendable {
    let showsLivePreview: Bool
    let quotaDisplay: QuotaDisplayPreference
    let showsFiveHour: Bool
    let showsWeekly: Bool
    let showsResetCountdown: Bool

    static let standard = MenuBarLabelConfiguration(
        showsLivePreview: true,
        quotaDisplay: .remaining,
        showsFiveHour: true,
        showsWeekly: true,
        showsResetCountdown: true
    )
}
