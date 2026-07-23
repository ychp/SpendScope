import SwiftUI
import SystemConfiguration

enum AppPreferenceKeys {
    static let keepsDashboardOnTop = "dashboard.keepsOnTop"
    static let dashboardCloseBehavior = "dashboard.closeBehavior"
    static let automaticRefreshEnabled = "data.automaticRefreshEnabled"
    static let quotaRefreshRequiresProxy = "data.quotaRefreshRequiresProxy"
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

enum QuotaRefreshProxyPolicy {
    static func requiresEnabledProxy(from defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: AppPreferenceKeys.quotaRefreshRequiresProxy) as? Bool ?? false
    }
}

enum LocalProxyStatus {
    private static let enabledKeys = [
        kSCPropNetProxiesHTTPEnable as String,
        kSCPropNetProxiesHTTPSEnable as String,
        kSCPropNetProxiesSOCKSEnable as String,
        kSCPropNetProxiesProxyAutoConfigEnable as String,
        kSCPropNetProxiesProxyAutoDiscoveryEnable as String
    ]

    static func isEnabled() -> Bool {
        guard let settings = SCDynamicStoreCopyProxies(nil) as? [String: Any] else {
            return false
        }
        return isEnabled(in: settings)
    }

    static func isEnabled(in settings: [String: Any]) -> Bool {
        enabledKeys.contains { key in
            if let value = settings[key] as? Bool {
                return value
            }
            return (settings[key] as? NSNumber)?.boolValue ?? false
        }
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
