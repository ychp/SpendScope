import SwiftUI

@main
struct SpendScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppPreferenceKeys.keepsDashboardOnTop) private var keepsDashboardOnTop = false

    var body: some Scene {
        Window("SpendScope", id: "dashboard") {
            DashboardView(store: appDelegate.store)
                .preferredColorScheme(.light)
                .background(
                    AppWindowLevelBridge(
                        level: AppWindowLevelPolicy.level(
                            for: .dashboard,
                            keepsDashboardOnTop: keepsDashboardOnTop
                        )
                    )
                )
                .background(StatusItemSceneBridge(appDelegate: appDelegate))
        }
        .defaultSize(width: 920, height: 620)

        Settings {
            SettingsView(
                store: appDelegate.store,
                reminderController: appDelegate.usageReminderController,
                updateService: appDelegate.updateService
            )
                .preferredColorScheme(.light)
                .background(
                    AppWindowLevelBridge(
                        level: AppWindowLevelPolicy.level(
                            for: .settings,
                            keepsDashboardOnTop: keepsDashboardOnTop
                        )
                    )
                )
        }
    }
}

enum AppWindowRole {
    case dashboard
    case settings
}

@MainActor
enum AppWindowLevelPolicy {
    static func level(
        for role: AppWindowRole,
        keepsDashboardOnTop: Bool
    ) -> NSWindow.Level {
        guard keepsDashboardOnTop else { return .normal }
        switch role {
        case .dashboard: return .floating
        case .settings: return .modalPanel
        }
    }
}

private final class AppWindowLevelView: NSView {
    var level: NSWindow.Level = .normal {
        didSet { updateWindowLevel() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateWindowLevel()
    }

    private func updateWindowLevel() {
        guard let window else { return }
        window.level = level
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private struct AppWindowLevelBridge: NSViewRepresentable {
    let level: NSWindow.Level

    func makeNSView(context: Context) -> AppWindowLevelView {
        let view = AppWindowLevelView()
        view.level = level
        return view
    }

    func updateNSView(_ nsView: AppWindowLevelView, context: Context) {
        nsView.level = level
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
