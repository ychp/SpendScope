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
                "5h \(snapshot.quotas[0].remainingPercent)% · 7d \(snapshot.quotas[1].remainingPercent)%",
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
