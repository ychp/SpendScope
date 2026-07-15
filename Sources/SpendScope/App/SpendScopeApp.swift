import SwiftUI

@main
struct SpendScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppPreferenceKeys.appearance) private var appearanceRaw = AppearancePreference.system.rawValue

    var body: some Scene {
        Window("SpendScope", id: "dashboard") {
            DashboardView(store: appDelegate.store)
                .preferredColorScheme(preferredColorScheme)
                .background(StatusItemSceneBridge(appDelegate: appDelegate))
        }
        .defaultSize(width: 920, height: 620)

        Settings {
            SettingsView(store: appDelegate.store)
                .preferredColorScheme(preferredColorScheme)
        }
    }

    private var preferredColorScheme: ColorScheme? {
        AppearancePreference(rawValue: appearanceRaw)?.colorScheme
    }

}

private struct StatusItemSceneBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                appDelegate.updateSceneActions(
                    openDashboard: {
                        openWindow(id: "dashboard")
                        NSApp.activate(ignoringOtherApps: true)
                    },
                    openSettings: {
                        openSettings()
                        NSApp.activate(ignoringOtherApps: true)
                    }
                )
            }
    }
}
