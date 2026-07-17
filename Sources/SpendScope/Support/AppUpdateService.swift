import AppKit
import CryptoKit
import Foundation
import Observation

struct AppVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    let components: [Int]
    let prerelease: String?

    init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        guard let numberPart = parts.first else { return nil }

        let parsedComponents = numberPart.split(separator: ".", omittingEmptySubsequences: false)
            .compactMap { Int($0) }
        guard !parsedComponents.isEmpty,
              parsedComponents.count == numberPart.split(separator: ".", omittingEmptySubsequences: false).count else {
            return nil
        }

        components = parsedComponents
        prerelease = parts.count > 1 ? String(parts[1]) : nil
    }

    var description: String {
        let base = components.map(String.init).joined(separator: ".")
        return prerelease.map { "\(base)-\($0)" } ?? base
    }

    static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil): return false
        case (.some, nil): return true
        case (nil, .some): return false
        case let (.some(left), .some(right)): return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

struct AppRelease: Equatable, Sendable {
    let version: AppVersion
    let pageURL: URL
    let installerURL: URL
    let installerName: String
    let digest: String?
    let checksumURL: URL?
}

enum AppUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(checkedAt: Date)
    case available(AppRelease)
    case downloading(AppRelease)
    case ready(AppRelease, installerURL: URL)
    case failed(String)

    var availableRelease: AppRelease? {
        switch self {
        case .available(let release), .downloading(let release), .ready(let release, _):
            release
        case .idle, .checking, .upToDate, .failed:
            nil
        }
    }
}

protocol AppReleaseProviding: Sendable {
    func latestRelease() async throws -> AppRelease
    func downloadInstaller(for release: AppRelease) async throws -> URL
}

actor GitHubAppReleaseClient: AppReleaseProviding {
    private let session: URLSession
    private let fileManager: FileManager
    private let latestReleaseURL = URL(string: "https://github.com/ychp/SpendScope/releases/latest")!
    private let installerName = "SpendScope-macOS-unsigned.dmg"

    init(session: URLSession = .shared, fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager
    }

    func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: latestReleaseURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("SpendScope", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        try validate(response)
        guard let pageURL = response.url else { throw AppUpdateError.invalidResponse }
        guard pageURL.pathComponents.contains("tag") else {
            throw AppUpdateError.noPublishedRelease
        }
        let tagName = pageURL.lastPathComponent
        guard let version = AppVersion(tagName) else {
            throw AppUpdateError.invalidVersion(tagName)
        }
        let assetBaseURL = URL(
            string: "https://github.com/ychp/SpendScope/releases/latest/download/"
        )!
        return AppRelease(
            version: version,
            pageURL: pageURL,
            installerURL: assetBaseURL.appendingPathComponent(installerName),
            installerName: installerName,
            digest: nil,
            checksumURL: assetBaseURL.appendingPathComponent("\(installerName).sha256")
        )
    }

    func downloadInstaller(for release: AppRelease) async throws -> URL {
        let (temporaryURL, response) = try await session.download(from: release.installerURL)
        try validate(response)

        let expectedDigest = try await expectedDigest(for: release)
        if let expectedDigest {
            let actualDigest = try sha256(of: temporaryURL)
            guard actualDigest.caseInsensitiveCompare(expectedDigest) == .orderedSame else {
                throw AppUpdateError.checksumMismatch
            }
        }

        let updatesDirectory = try updatesDirectoryURL()
        let destination = updatesDirectory.appendingPathComponent(
            "SpendScope-\(release.version.description).dmg",
            isDirectory: false
        )
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func expectedDigest(for release: AppRelease) async throws -> String? {
        if let digest = release.digest?.lowercased(), digest.hasPrefix("sha256:") {
            return String(digest.dropFirst("sha256:".count))
        }
        guard let checksumURL = release.checksumURL else { return nil }
        let (data, response) = try await session.data(from: checksumURL)
        try validate(response)
        guard let contents = String(data: data, encoding: .utf8),
              let digest = contents.split(whereSeparator: { $0.isWhitespace }).first,
              digest.count == 64 else {
            throw AppUpdateError.invalidChecksum
        }
        return String(digest)
    }

    private func updatesDirectoryURL() throws -> URL {
        let caches = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = caches
            .appendingPathComponent("SpendScope", isDirectory: true)
            .appendingPathComponent("Updates", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw AppUpdateError.invalidResponse
        }
    }
}

enum AppUpdateError: LocalizedError, Sendable {
    case invalidResponse
    case noPublishedRelease
    case invalidVersion(String)
    case installerMissing
    case invalidChecksum
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "更新服务器暂时不可用"
        case .noPublishedRelease: "尚无已发布版本"
        case .invalidVersion(let version): "无法识别版本号 \(version)"
        case .installerMissing: "最新版本没有可用的 macOS 安装包"
        case .invalidChecksum: "安装包校验信息无效"
        case .checksumMismatch: "安装包校验失败，请改用手动下载"
        }
    }
}

@MainActor
@Observable
final class AppUpdateService {
    private(set) var state: AppUpdateState = .idle
    private(set) var automaticallyChecksForUpdates: Bool
    private(set) var automaticallyDownloadsUpdates: Bool

    let currentVersion: AppVersion

    private let provider: any AppReleaseProviding
    private let defaults: UserDefaults
    private var hasStarted = false

    init(
        currentVersion: AppVersion = AppVersion(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        )!,
        provider: any AppReleaseProviding = GitHubAppReleaseClient(),
        defaults: UserDefaults = .standard
    ) {
        self.currentVersion = currentVersion
        self.provider = provider
        self.defaults = defaults
        automaticallyChecksForUpdates = defaults.object(
            forKey: AppPreferenceKeys.automaticallyChecksForUpdates
        ) as? Bool ?? true
        automaticallyDownloadsUpdates = defaults.object(
            forKey: AppPreferenceKeys.automaticallyDownloadsUpdates
        ) as? Bool ?? false
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        guard automaticallyChecksForUpdates else { return }
        Task { await checkForUpdates() }
    }

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        automaticallyChecksForUpdates = isEnabled
        defaults.set(isEnabled, forKey: AppPreferenceKeys.automaticallyChecksForUpdates)
        if isEnabled, case .idle = state {
            Task { await checkForUpdates() }
        }
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        automaticallyDownloadsUpdates = isEnabled
        defaults.set(isEnabled, forKey: AppPreferenceKeys.automaticallyDownloadsUpdates)
        guard isEnabled, case .available(let release) = state else { return }
        Task { await downloadUpdate(release: release, openWhenReady: false) }
    }

    func checkForUpdates() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let release = try await provider.latestRelease()
            if release.version > currentVersion {
                state = .available(release)
                if automaticallyDownloadsUpdates {
                    await downloadUpdate(release: release, openWhenReady: false)
                }
            } else {
                state = .upToDate(checkedAt: Date())
            }
        } catch AppUpdateError.noPublishedRelease {
            state = .upToDate(checkedAt: Date())
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func updateNow() async {
        switch state {
        case .available(let release):
            await downloadUpdate(release: release, openWhenReady: true)
        case .ready(_, let installerURL):
            openInstaller(installerURL)
        case .downloading, .checking, .idle, .upToDate, .failed:
            break
        }
    }

    func openReleasePage() {
        let url = state.availableRelease?.pageURL
            ?? URL(string: "https://github.com/ychp/SpendScope/releases/latest")!
        NSWorkspace.shared.open(url)
    }

    private func downloadUpdate(release: AppRelease, openWhenReady: Bool) async {
        state = .downloading(release)
        do {
            let installerURL = try await provider.downloadInstaller(for: release)
            state = .ready(release, installerURL: installerURL)
            if openWhenReady {
                openInstaller(installerURL)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func openInstaller(_ url: URL) {
        NSWorkspace.shared.open(url)
    }
}
