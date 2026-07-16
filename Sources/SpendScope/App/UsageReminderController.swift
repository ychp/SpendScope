import AppKit
import Observation
import UserNotifications

enum UsageReminderAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
protocol UsageNotificationClient: AnyObject {
    func authorizationStatus() async -> UsageReminderAuthorizationStatus
    func requestAuthorization() async throws -> Bool
    func deliver(_ notification: UsageReminderNotification) async throws
}

@MainActor
final class SystemUsageNotificationClient: UsageNotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UsageReminderAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral: return .authorized
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func deliver(_ notification: UsageReminderNotification) async throws {
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body
        content.sound = .default
        content.categoryIdentifier = UsageReminderNotification.categoryIdentifier
        content.userInfo = ["destination": "dashboard"]
        let request = UNNotificationRequest(
            identifier: notification.identifier,
            content: content,
            trigger: nil
        )
        try await center.add(request)
    }
}

@MainActor
@Observable
final class UsageReminderController {
    private(set) var authorizationStatus: UsageReminderAuthorizationStatus = .notDetermined

    @ObservationIgnored private let store: DashboardStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notificationClient: any UsageNotificationClient
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var needsEvaluation = false
    @ObservationIgnored private var evaluationTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?

    init(
        store: DashboardStore,
        defaults: UserDefaults = .standard,
        notificationClient: (any UsageNotificationClient)? = nil
    ) {
        self.store = store
        self.defaults = defaults
        self.notificationClient = notificationClient ?? SystemUsageNotificationClient()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observeStore()
        Task { @MainActor [weak self] in
            await self?.refreshAuthorizationStatus()
            self?.scheduleEvaluation()
        }
    }

    func configurationDidChange(requestAuthorizationIfNeeded: Bool = false) {
        if requestAuthorizationIfNeeded {
            requestPermissionIfNeeded()
        } else {
            scheduleEvaluation()
        }
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await notificationClient.authorizationStatus()
    }

    func applicationDidBecomeActive() {
        Task { @MainActor [weak self] in
            await self?.refreshAuthorizationStatus()
            self?.scheduleEvaluation()
        }
    }

    func openNotificationSettings() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ychp.SpendScope"
        let encodedBundleID = bundleID.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed
        ) ?? bundleID
        let appURL = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(encodedBundleID)"
        )
        if let appURL, NSWorkspace.shared.open(appURL) {
            return
        }
        if let fallback = URL(
            string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ) {
            NSWorkspace.shared.open(fallback)
        }
    }

    private func requestPermissionIfNeeded() {
        permissionTask?.cancel()
        permissionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await refreshAuthorizationStatus()
            if authorizationStatus == .notDetermined {
                _ = try? await notificationClient.requestAuthorization()
                await refreshAuthorizationStatus()
            }
            scheduleEvaluation()
        }
    }

    private func observeStore() {
        withObservationTracking {
            _ = store.state
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                self?.observeStore()
                self?.scheduleEvaluation()
            }
        }
    }

    private func scheduleEvaluation() {
        needsEvaluation = true
        guard evaluationTask == nil else { return }
        evaluationTask = Task { @MainActor [weak self] in
            await self?.drainEvaluations()
        }
    }

    private func drainEvaluations() async {
        while needsEvaluation, !Task.isCancelled {
            needsEvaluation = false
            await evaluateCurrentSnapshot()
        }
        evaluationTask = nil
        if needsEvaluation {
            scheduleEvaluation()
        }
    }

    private func evaluateCurrentSnapshot() async {
        let configuration = UsageReminderConfiguration.load(from: defaults)
        guard configuration.isEnabled, let snapshot = store.snapshot else { return }

        let checkpoint = UsageReminderCheckpointCodec.decode(
            defaults.data(forKey: AppPreferenceKeys.usageReminderCheckpoint)
        )
        let evaluation = UsageReminderEvaluator.evaluate(
            quotas: snapshot.quotas,
            configuration: configuration,
            checkpoint: checkpoint,
            now: Date()
        )
        save(evaluation.baselineCheckpoint)
        guard !evaluation.events.isEmpty else { return }

        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized,
              let notification = UsageReminderNotification(events: evaluation.events) else {
            return
        }
        do {
            try await notificationClient.deliver(notification)
            save(evaluation.deliveredCheckpoint)
        } catch {
            // Keep the baseline checkpoint so the same threshold can retry later.
        }
    }

    private func save(_ checkpoint: UsageReminderCheckpoint) {
        guard let data = UsageReminderCheckpointCodec.encode(checkpoint) else { return }
        defaults.set(data, forKey: AppPreferenceKeys.usageReminderCheckpoint)
    }

    isolated deinit {
        evaluationTask?.cancel()
        permissionTask?.cancel()
    }
}
