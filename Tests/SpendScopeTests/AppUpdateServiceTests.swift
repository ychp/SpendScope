import Foundation
import Testing
@testable import SpendScope

struct AppVersionTests {
    @Test func parsesTagsAndComparesComponents() throws {
        let current = try #require(AppVersion("v0.1.0"))
        let patch = try #require(AppVersion("0.1.1"))
        let shortened = try #require(AppVersion("0.1"))

        #expect(current < patch)
        #expect(current == shortened)
        #expect(current.description == "0.1.0")
    }

    @Test func stableVersionSupersedesPrerelease() throws {
        let prerelease = try #require(AppVersion("1.0.0-beta.2"))
        let stable = try #require(AppVersion("1.0.0"))

        #expect(prerelease < stable)
    }

    @Test func rejectsMalformedVersions() {
        #expect(AppVersion("release") == nil)
        #expect(AppVersion("1..0") == nil)
    }
}

@MainActor
struct AppUpdateServiceTests {
    @Test func reportsNewerRelease() async throws {
        let release = try makeRelease(version: "0.2.0")
        let service = AppUpdateService(
            currentVersion: try #require(AppVersion("0.1.0")),
            provider: StubReleaseProvider(release: release),
            defaults: isolatedDefaults()
        )

        await service.checkForUpdates()

        #expect(service.state == .available(release))
    }

    @Test func reportsCurrentVersionAsUpToDate() async throws {
        let release = try makeRelease(version: "0.1.0")
        let service = AppUpdateService(
            currentVersion: try #require(AppVersion("0.1.0")),
            provider: StubReleaseProvider(release: release),
            defaults: isolatedDefaults()
        )

        await service.checkForUpdates()

        guard case .upToDate = service.state else {
            Issue.record("Expected the app to be up to date")
            return
        }
    }

    @Test func treatsMissingPublishedReleaseAsUpToDate() async throws {
        let service = AppUpdateService(
            currentVersion: try #require(AppVersion("0.1.0")),
            provider: StubReleaseProvider(error: AppUpdateError.noPublishedRelease),
            defaults: isolatedDefaults()
        )

        await service.checkForUpdates()

        guard case .upToDate = service.state else {
            Issue.record("Expected no published release to be treated as up to date")
            return
        }
    }

    private func makeRelease(version: String) throws -> AppRelease {
        AppRelease(
            version: try #require(AppVersion(version)),
            pageURL: URL(string: "https://example.com/release")!,
            installerURL: URL(string: "https://example.com/SpendScope.dmg")!,
            installerName: "SpendScope.dmg",
            digest: nil,
            checksumURL: nil
        )
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "AppUpdateServiceTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }
}

private struct StubReleaseProvider: AppReleaseProviding {
    let release: AppRelease?
    let error: AppUpdateError?

    init(release: AppRelease) {
        self.release = release
        error = nil
    }

    init(error: AppUpdateError) {
        release = nil
        self.error = error
    }

    func latestRelease() async throws -> AppRelease {
        if let error { throw error }
        return release!
    }

    func downloadInstaller(for release: AppRelease) async throws -> URL {
        URL(fileURLWithPath: "/tmp/SpendScope.dmg")
    }
}
