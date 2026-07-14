import SwiftUI

@main
struct SpendScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let snapshot = DashboardSnapshot.preview

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(snapshot: snapshot)
        } label: {
            Label(
                snapshot.menuBarQuotaLabel,
                systemImage: "chart.bar.fill"
            )
        }
        .menuBarExtraStyle(.window)

        Window("SpendScope", id: "dashboard") {
            DashboardView(snapshot: snapshot)
        }
        .defaultSize(width: 920, height: 620)

        Settings {
            SettingsView()
        }
    }
}
