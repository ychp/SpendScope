import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DashboardStore.live()

    private var statusItemController: StatusItemController?
    private var openDashboardAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusItemController = StatusItemController(
            store: store,
            onOpenDashboard: { [weak self] in self?.openDashboard() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
    }

    func updateSceneActions(
        openDashboard: @escaping () -> Void,
        openSettings: @escaping () -> Void
    ) {
        openDashboardAction = openDashboard
        openSettingsAction = openSettings
    }

    private func openDashboard() {
        if let openDashboardAction {
            openDashboardAction()
            return
        }
        NSApp.windows.first { $0.title == "SpendScope" }?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSettings() {
        if let openSettingsAction {
            openSettingsAction()
            return
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
