import Foundation

struct CodexAccountRateLimits: Equatable, Sendable {
    let planRaw: String?
    let windows: [RawQuotaWindow]
    let observedAt: Date

    func applying(
        to snapshot: DashboardSnapshot,
        now: Date,
        calendar: Calendar
    ) -> DashboardSnapshot {
        let nowMilliseconds = Int64((now.timeIntervalSince1970 * 1_000).rounded(.towardZero))
        let observedAtMilliseconds = Int64(
            (observedAt.timeIntervalSince1970 * 1_000).rounded(.towardZero)
        )
        let observations = QuotaNormalizer.normalize(
            windows,
            plan: PlanResolver.resolve(rawValue: planRaw),
            observedAtMilliseconds: observedAtMilliseconds
        )
        let quotas = observations.compactMap { observation -> QuotaSnapshot? in
            guard observation.remaining.isFinite,
                  (0...1).contains(observation.remaining),
                  let resetsAtMilliseconds = observation.resetsAtMilliseconds,
                  resetsAtMilliseconds > nowMilliseconds else {
                return nil
            }
            let identity: (id: String, title: String)
            switch observation.kind {
            case .fiveHour:
                identity = ("5h", "5 小时")
            case .weekly:
                identity = ("7d", "7 天")
            }
            return QuotaSnapshot(
                id: identity.id,
                title: identity.title,
                remaining: observation.remaining,
                resetText: QuotaResetFormatter.string(
                    resetsAtMilliseconds: resetsAtMilliseconds,
                    now: now,
                    calendar: calendar
                ),
                resetsAt: Date(
                    timeIntervalSince1970: TimeInterval(resetsAtMilliseconds) / 1_000
                ),
                observedAt: observedAt,
                isOfficialAccountQuota: true
            )
        }
        return DashboardSnapshot(
            planName: planDisplayName ?? snapshot.planName,
            updatedText: snapshot.updatedText,
            periods: snapshot.periods,
            quotas: quotas,
            models: snapshot.models,
            dailyUsage: snapshot.dailyUsage,
            activityRankings: snapshot.activityRankings,
            projectUsage: snapshot.projectUsage,
            issues: snapshot.issues
        )
    }

    private var planDisplayName: String? {
        guard let planRaw else { return nil }
        switch PlanResolver.resolve(rawValue: planRaw).kind {
        case .free: return "Free"
        case .plus: return "Plus"
        case .proLite: return "Pro 5x"
        case .pro20x: return "Pro 20x"
        }
    }
}

protocol CodexAccountRateLimitReading: Sendable {
    func read() async throws -> CodexAccountRateLimits
}

struct CodexAppServerRateLimitReader: CodexAccountRateLimitReading, Sendable {
    private let executableURL: URL
    private let commandTimeout: DispatchTimeInterval
    private let now: @Sendable () -> Date

    init(
        executableURL: URL,
        commandTimeout: DispatchTimeInterval = .seconds(10),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.executableURL = executableURL
        self.commandTimeout = commandTimeout
        self.now = now
    }

    static func discover(fileManager: FileManager = .default) -> Self? {
        let home = fileManager.homeDirectoryForCurrentUser
        let candidates = [
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            home.appendingPathComponent(".local/bin/codex").path,
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        guard let path = candidates.first(where: fileManager.isExecutableFile(atPath:)) else {
            return nil
        }
        return Self(executableURL: URL(fileURLWithPath: path))
    }

    func read() async throws -> CodexAccountRateLimits {
        let executableURL = executableURL
        let commandTimeout = commandTimeout
        let observedAt = now()
        return try await Task.detached(priority: .utility) {
            let data = try Self.runAppServer(
                executableURL: executableURL,
                commandTimeout: commandTimeout
            )
            return try Self.parse(data: data, observedAt: observedAt)
        }.value
    }

    static func parse(data: Data, observedAt: Date) throws -> CodexAccountRateLimits {
        let decoder = JSONDecoder()
        for line in data.split(separator: 0x0A) {
            guard let response = try? decoder.decode(RateLimitResponse.self, from: Data(line)),
                  response.id == 2,
                  let rateLimits = response.result?.rateLimits else {
                continue
            }
            let windows: [RawQuotaWindow] = [rateLimits.primary, rateLimits.secondary]
                .compactMap { window -> RawQuotaWindow? in
                guard let window,
                      let windowMinutes = window.windowDurationMins,
                      windowMinutes <= Int64(Int.max),
                      windowMinutes >= Int64(Int.min) else {
                    return nil
                }
                return RawQuotaWindow(
                    windowMinutes: Int(windowMinutes),
                    usedPercent: window.usedPercent,
                    resetsAtSeconds: window.resetsAt
                )
                }
            guard !windows.isEmpty else { throw ReaderError.missingRateLimits }
            return CodexAccountRateLimits(
                planRaw: rateLimits.planType,
                windows: windows,
                observedAt: observedAt
            )
        }
        throw ReaderError.missingRateLimits
    }

    private static func runAppServer(
        executableURL: URL,
        commandTimeout: DispatchTimeInterval
    ) throws -> Data {
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        let completion = DispatchSemaphore(value: 0)
        let outputCapture = AppServerOutputCapture()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outputCapture.append(data) }
        }
        process.terminationHandler = { _ in
            outputCapture.processTerminated()
            completion.signal()
        }

        do {
            try process.run()
            let requests = """
            {"id":1,"method":"initialize","params":{"clientInfo":{"name":"SpendScope","version":"0.1.1"},"capabilities":{}}}
            {"id":2,"method":"account/rateLimits/read","params":null}

            """
            try standardInput.fileHandleForWriting.write(contentsOf: Data(requests.utf8))
        } catch {
            if process.isRunning { process.terminate() }
            throw ReaderError.launchFailed
        }

        guard outputCapture.wait(timeout: commandTimeout) == .success else {
            try? standardInput.fileHandleForWriting.close()
            process.terminate()
            if completion.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
            standardOutput.fileHandleForReading.readabilityHandler = nil
            throw ReaderError.timedOut
        }
        try? standardInput.fileHandleForWriting.close()
        if process.isRunning, completion.wait(timeout: .now() + 1) == .timedOut {
            process.terminate()
            if completion.wait(timeout: .now() + 1) == .timedOut, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = completion.wait(timeout: .now() + 1)
            }
        }
        standardOutput.fileHandleForReading.readabilityHandler = nil
        let data = outputCapture.data
        guard !data.isEmpty else { throw ReaderError.commandFailed }
        return data
    }

    private struct RateLimitResponse: Decodable {
        let id: Int?
        let result: Result?

        struct Result: Decodable {
            let rateLimits: RateLimits
        }

        struct RateLimits: Decodable {
            let planType: String?
            let primary: Window?
            let secondary: Window?
        }

        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Int64?
            let resetsAt: Int64?
        }
    }

    enum ReaderError: Error {
        case launchFailed
        case timedOut
        case commandFailed
        case missingRateLimits
    }
}

private final class AppServerOutputCapture: @unchecked Sendable {
    private let lock = NSLock()
    private let responseReady = DispatchSemaphore(value: 0)
    private var storage = Data()
    private var hasSignaled = false

    var data: Data {
        lock.withLock { storage }
    }

    func append(_ data: Data) {
        lock.withLock {
            storage.append(data)
            guard !hasSignaled, hasCompleteResponse else { return }
            hasSignaled = true
            responseReady.signal()
        }
    }

    func processTerminated() {
        lock.withLock {
            guard !hasSignaled else { return }
            hasSignaled = true
            responseReady.signal()
        }
    }

    func wait(timeout: DispatchTimeInterval) -> DispatchTimeoutResult {
        responseReady.wait(timeout: .now() + timeout)
    }

    private var hasCompleteResponse: Bool {
        storage.split(separator: 0x0A).contains { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line)),
                  let dictionary = object as? [String: Any],
                  let id = dictionary["id"] as? NSNumber else {
                return false
            }
            return id.intValue == 2 && (dictionary["result"] != nil || dictionary["error"] != nil)
        }
    }
}
