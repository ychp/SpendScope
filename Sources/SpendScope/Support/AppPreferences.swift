import SwiftUI

enum AppPreferenceKeys {
    static let appearance = "appearance"
    static let quotaDisplay = "menuBar.quotaDisplay"
    static let showsFiveHour = "menuBar.showsFiveHour"
    static let showsWeekly = "menuBar.showsWeekly"
    static let showsToday = "menuBar.showsToday"
}

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
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
}

enum QuotaDisplayPreference: String, CaseIterable, Identifiable, Sendable {
    case used
    case remaining

    var id: Self { self }
}

struct MenuBarLabelConfiguration: Equatable, Sendable {
    let quotaDisplay: QuotaDisplayPreference
    let showsFiveHour: Bool
    let showsWeekly: Bool
    let showsToday: Bool

    static let standard = MenuBarLabelConfiguration(
        quotaDisplay: .remaining,
        showsFiveHour: true,
        showsWeekly: true,
        showsToday: false
    )
}
