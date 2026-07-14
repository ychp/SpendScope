import SwiftUI

@main
struct SpendScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = DashboardStore.live()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(store: store)
        } label: {
            Label(
                store.menuBarLabel,
                systemImage: "chart.bar.fill"
            )
        }
        .menuBarExtraStyle(.window)

        Window("SpendScope", id: "dashboard") {
            DashboardView(store: store)
        }
        .defaultSize(width: 920, height: 620)

        Settings {
            SettingsView(store: store)
        }
    }
}
