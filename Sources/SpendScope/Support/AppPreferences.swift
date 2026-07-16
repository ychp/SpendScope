import SwiftUI

enum AppPreferenceKeys {
    static let keepsDashboardOnTop = "dashboard.keepsOnTop"
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
