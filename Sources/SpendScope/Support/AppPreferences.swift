import SwiftUI

enum AppPreferenceKeys {
    static let statusItemDisplayMode = "menuBar.displayMode"
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

enum StatusItemDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case rich
    case classic

    var id: Self { self }
}

struct MenuBarLabelConfiguration: Equatable, Sendable {
    let quotaDisplay: QuotaDisplayPreference
    let showsFiveHour: Bool
    let showsWeekly: Bool
    let showsResetCountdown: Bool

    static let standard = MenuBarLabelConfiguration(
        quotaDisplay: .remaining,
        showsFiveHour: true,
        showsWeekly: true,
        showsResetCountdown: true
    )
}
