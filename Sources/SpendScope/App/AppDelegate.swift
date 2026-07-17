import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DashboardStore.live()
    let updateService = AppUpdateService()
    lazy var usageReminderController = UsageReminderController(store: store)

    private var statusItemController: StatusItemController?
    private var openDashboardAction: (() -> Void)?
    private var openSettingsAction: (() -> Void)?

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        statusItemController = StatusItemController(
            store: store,
            updateService: updateService,
            onOpenDashboard: { [weak self] in self?.openDashboard() },
            onOpenSettings: { [weak self] in self?.openSettings() }
        )
        usageReminderController.start()
        updateService.start()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        usageReminderController.applicationDidBecomeActive()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        guard notification.request.content.categoryIdentifier
                == UsageReminderNotification.categoryIdentifier else {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let isUsageReminder = request.content.categoryIdentifier
            == UsageReminderNotification.categoryIdentifier
            || request.identifier.hasPrefix(UsageReminderNotification.identifierPrefix)
        completionHandler()
        guard isUsageReminder else { return }
        Task { @MainActor [weak self] in
            self?.openDashboard()
        }
    }
}
