import Foundation

enum UsageReminderQuota: String, CaseIterable, Codable, Hashable, Sendable {
    case fiveHour = "5h"
    case weekly = "7d"

    var title: String {
        switch self {
        case .fiveHour: "5H"
        case .weekly: "7d"
        }
    }
}

enum UsageReminderThreshold: Int, CaseIterable, Codable, Hashable, Sendable {
    case twenty = 20
    case ten = 10
    case five = 5

    static let defaultValues = Set(Self.allCases)
}

struct UsageReminderConfiguration: Equatable, Sendable {
    let isEnabled: Bool
    let quotas: Set<UsageReminderQuota>
    let thresholds: Set<UsageReminderThreshold>

    static let standard = UsageReminderConfiguration(
        isEnabled: false,
        quotas: Set(UsageReminderQuota.allCases),
        thresholds: UsageReminderThreshold.defaultValues
    )

    static func load(from defaults: UserDefaults) -> UsageReminderConfiguration {
        var quotas: Set<UsageReminderQuota> = []
        if defaults.boolValue(forKey: AppPreferenceKeys.remindsFiveHour, default: true) {
            quotas.insert(.fiveHour)
        }
        if defaults.boolValue(forKey: AppPreferenceKeys.remindsWeekly, default: true) {
            quotas.insert(.weekly)
        }

        var thresholds: Set<UsageReminderThreshold> = []
        if defaults.boolValue(forKey: AppPreferenceKeys.remindsAtTwentyPercent, default: true) {
            thresholds.insert(.twenty)
        }
        if defaults.boolValue(forKey: AppPreferenceKeys.remindsAtTenPercent, default: true) {
            thresholds.insert(.ten)
        }
        if defaults.boolValue(forKey: AppPreferenceKeys.remindsAtFivePercent, default: true) {
            thresholds.insert(.five)
        }

        return UsageReminderConfiguration(
            isEnabled: defaults.boolValue(
                forKey: AppPreferenceKeys.usageRemindersEnabled,
                default: false
            ),
            quotas: quotas.isEmpty ? Set(UsageReminderQuota.allCases) : quotas,
            thresholds: thresholds.isEmpty ? UsageReminderThreshold.defaultValues : thresholds
        )
    }
}

struct UsageReminderCheckpoint: Codable, Equatable, Sendable {
    static let currentVersion = 1

    struct QuotaState: Codable, Equatable, Sendable {
        var resetsAtMilliseconds: Int64
        var deliveredThresholds: Set<Int>
        var lastObservedAtMilliseconds: Int64
        var lastRemaining: Double
    }

    var version: Int
    var quotas: [String: QuotaState]

    static let empty = UsageReminderCheckpoint(
        version: currentVersion,
        quotas: [:]
    )
}

enum UsageReminderCheckpointCodec {
    static func decode(_ data: Data?) -> UsageReminderCheckpoint {
        guard let data,
              let checkpoint = try? JSONDecoder().decode(UsageReminderCheckpoint.self, from: data),
              checkpoint.version == UsageReminderCheckpoint.currentVersion else {
            return .empty
        }
        return checkpoint
    }

    static func encode(_ checkpoint: UsageReminderCheckpoint) -> Data? {
        try? JSONEncoder().encode(checkpoint)
    }
}

struct UsageReminderEvent: Equatable, Sendable {
    let quota: UsageReminderQuota
    let remainingPercent: Int
    let threshold: UsageReminderThreshold
    let resetsAtMilliseconds: Int64
    let resetDescription: String
}

struct UsageReminderEvaluation: Equatable, Sendable {
    let events: [UsageReminderEvent]
    let baselineCheckpoint: UsageReminderCheckpoint
    let deliveredCheckpoint: UsageReminderCheckpoint
}

enum UsageReminderEvaluator {
    static func evaluate(
        quotas: [QuotaSnapshot],
        configuration: UsageReminderConfiguration,
        checkpoint: UsageReminderCheckpoint,
        now: Date
    ) -> UsageReminderEvaluation {
        guard configuration.isEnabled else {
            return UsageReminderEvaluation(
                events: [],
                baselineCheckpoint: checkpoint,
                deliveredCheckpoint: checkpoint
            )
        }

        let snapshots = Dictionary(uniqueKeysWithValues: quotas.compactMap { snapshot in
            UsageReminderQuota(rawValue: snapshot.id).map { ($0, snapshot) }
        })
        var baseline = checkpoint.version == UsageReminderCheckpoint.currentVersion
            ? checkpoint
            : .empty
        var delivered = baseline
        var events: [UsageReminderEvent] = []

        for quota in UsageReminderQuota.allCases where configuration.quotas.contains(quota) {
            guard let snapshot = snapshots[quota],
                  snapshot.remaining.isFinite,
                  (0...1).contains(snapshot.remaining),
                  let resetsAt = snapshot.resetsAt,
                  resetsAt > now,
                  let observedAt = snapshot.observedAt else {
                continue
            }

            let resetMilliseconds = milliseconds(resetsAt)
            let observedMilliseconds = milliseconds(observedAt)
            let previous = baseline.quotas[quota.rawValue]
            if let previous,
               observedMilliseconds < previous.lastObservedAtMilliseconds {
                continue
            }

            var baselineState: UsageReminderCheckpoint.QuotaState
            if let previous, previous.resetsAtMilliseconds == resetMilliseconds {
                baselineState = previous
                baselineState.lastObservedAtMilliseconds = max(
                    previous.lastObservedAtMilliseconds,
                    observedMilliseconds
                )
                baselineState.lastRemaining = snapshot.remaining
            } else {
                baselineState = UsageReminderCheckpoint.QuotaState(
                    resetsAtMilliseconds: resetMilliseconds,
                    deliveredThresholds: [],
                    lastObservedAtMilliseconds: observedMilliseconds,
                    lastRemaining: snapshot.remaining
                )
            }
            baseline.quotas[quota.rawValue] = baselineState
            delivered.quotas[quota.rawValue] = baselineState

            let reached = configuration.thresholds.filter { threshold in
                snapshot.remaining <= Double(threshold.rawValue) / 100
                    && !baselineState.deliveredThresholds.contains(threshold.rawValue)
            }
            guard let mostUrgent = reached.min(by: { $0.rawValue < $1.rawValue }) else {
                continue
            }

            var deliveredState = baselineState
            deliveredState.deliveredThresholds.formUnion(
                UsageReminderThreshold.allCases
                    .filter { $0.rawValue >= mostUrgent.rawValue }
                    .map(\.rawValue)
            )
            delivered.quotas[quota.rawValue] = deliveredState
            events.append(UsageReminderEvent(
                quota: quota,
                remainingPercent: snapshot.remainingPercent,
                threshold: mostUrgent,
                resetsAtMilliseconds: resetMilliseconds,
                resetDescription: snapshot.resetDescription(now: now) ?? "即将重置"
            ))
        }

        return UsageReminderEvaluation(
            events: events,
            baselineCheckpoint: baseline,
            deliveredCheckpoint: delivered
        )
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }
}

struct UsageReminderNotification: Equatable, Sendable {
    static let categoryIdentifier = "usage-reminder"
    static let identifierPrefix = "usage-reminder-v1"

    let identifier: String
    let title: String
    let body: String

    init?(events: [UsageReminderEvent]) {
        guard !events.isEmpty else { return nil }
        let ordered = events.sorted { lhs, rhs in
            UsageReminderQuota.allCases.firstIndex(of: lhs.quota) ?? 0
                < UsageReminderQuota.allCases.firstIndex(of: rhs.quota) ?? 0
        }
        identifier = Self.identifierPrefix + "." + ordered.map {
            "\($0.quota.rawValue)-\($0.resetsAtMilliseconds)-\($0.threshold.rawValue)"
        }.joined(separator: ".")
        title = "Codex 额度提醒"
        body = ordered.map {
            "\($0.quota.title) 剩余 \($0.remainingPercent)%，\($0.resetDescription)。"
        }.joined(separator: "\n")
    }
}

private extension UserDefaults {
    func boolValue(forKey key: String, default defaultValue: Bool) -> Bool {
        object(forKey: key) as? Bool ?? defaultValue
    }
}
