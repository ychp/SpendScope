import SwiftUI
import SystemConfiguration

enum AppPreferenceKeys {
    static let keepsDashboardOnTop = "dashboard.keepsOnTop"
    static let dashboardCloseBehavior = "dashboard.closeBehavior"
    static let automaticRefreshEnabled = "data.automaticRefreshEnabled"
    static let quotaRefreshRequiresProxy = "data.quotaRefreshRequiresProxy"
    static let usageRemindersEnabled = "usageReminders.enabled"
    static let remindsAtTwentyPercent = "usageReminders.thresholds.twenty"
    static let remindsAtTenPercent = "usageReminders.thresholds.ten"
    static let remindsAtFivePercent = "usageReminders.thresholds.five"
    static let usageReminderCheckpoint = "usageReminders.checkpoint.v1"
    static let showsLivePreview = "menuBar.showsLivePreview"
    static let showsResetCountdown = "menuBar.showsResetCountdown"
    static let quotaDisplay = "menuBar.quotaDisplay"
    static let firstSubscriptionDate = "subscription.firstSubscribedAt"
    static let automaticallyChecksForUpdates = "updates.automaticallyChecks"
    static let automaticallyDownloadsUpdates = "updates.automaticallyDownloads"
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
        showsFiveHour: false,
        showsWeekly: true,
        showsResetCountdown: true
    )
}
