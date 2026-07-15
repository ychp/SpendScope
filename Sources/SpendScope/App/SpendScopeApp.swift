import SwiftUI

@main
struct SpendScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = DashboardStore.live()
    @AppStorage(AppPreferenceKeys.appearance) private var appearanceRaw = AppearancePreference.system.rawValue
    @AppStorage(AppPreferenceKeys.quotaDisplay) private var quotaDisplayRaw = QuotaDisplayPreference.remaining.rawValue
    @AppStorage(AppPreferenceKeys.showsFiveHour) private var showsFiveHour = true
    @AppStorage(AppPreferenceKeys.showsWeekly) private var showsWeekly = true
    @AppStorage(AppPreferenceKeys.showsToday) private var showsToday = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(store: store)
                .preferredColorScheme(preferredColorScheme)
        } label: {
            Label(
                store.menuBarLabel(configuration: menuBarConfiguration),
                systemImage: "chart.bar.fill"
            )
        }
        .menuBarExtraStyle(.window)

        Window("SpendScope", id: "dashboard") {
            DashboardView(store: store)
                .preferredColorScheme(preferredColorScheme)
        }
        .defaultSize(width: 920, height: 620)

        Settings {
            SettingsView(store: store)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        AppearancePreference(rawValue: appearanceRaw)?.colorScheme
    }

    private var menuBarConfiguration: MenuBarLabelConfiguration {
        MenuBarLabelConfiguration(
            quotaDisplay: QuotaDisplayPreference(rawValue: quotaDisplayRaw) ?? .remaining,
            showsFiveHour: showsFiveHour,
            showsWeekly: showsWeekly,
            showsToday: showsToday
        )
    }
}
