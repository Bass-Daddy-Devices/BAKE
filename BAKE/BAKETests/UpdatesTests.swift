import Foundation
import Security
import Testing
@testable import BAKE

/// The update setup as shipped: these run inside the signed BAKE.app.
struct UpdateConfigurationTests {
    private func info(_ key: String) -> Any? {
        Bundle.main.object(forInfoDictionaryKey: key)
    }

    private func entitlement(_ key: String) -> Any? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil)
    }

    @Test func feedIsBakesHTTPSAppcast() {
        #expect(info("SUFeedURL") as? String == "https://bake.bass-daddy.com/appcast.xml")
    }

    @Test func publicKeyIsAnEd25519Key() throws {
        let key = try #require(info("SUPublicEDKey") as? String)
        let data = try #require(Data(base64Encoded: key))
        #expect(data.count == 32)
    }

    @Test func sparklesSandboxServicesAreOn() {
        #expect(info("SUEnableDownloaderService") as? Bool == true)
        #expect(info("SUEnableInstallerLauncherService") as? Bool == true)
    }

    @Test func appCanReachSparklesInstaller() throws {
        let names = try #require(entitlement("com.apple.security.temporary-exception.mach-lookup.global-name") as? [String])
        #expect(names.contains("com.bassdaddydevices.BAKE-spks"))
        #expect(names.contains("com.bassdaddydevices.BAKE-spki"))
    }

    /// BAKE stays offline: only Sparkle's Downloader service touches the network.
    @Test func appHasNoNetworkAccess() {
        #expect(entitlement("com.apple.security.network.client") == nil)
    }
}

/// Stands in for Sparkle, recording what BAKE asks of it.
final class FakeUpdater: UpdaterDriving {
    var canCheckForUpdates = true
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = false
    private(set) var startCount = 0
    private(set) var checkCount = 0
    private var onCanCheckChange: ((Bool) -> Void)?

    func start() { startCount += 1 }
    func checkForUpdates() { checkCount += 1 }

    func observeCanCheckForUpdates(_ change: @escaping (Bool) -> Void) -> AnyObject {
        onCanCheckChange = change
        return NSObject()
    }

    /// What Sparkle does while a check runs (false) and when it ends (true).
    func setCanCheckForUpdates(_ value: Bool) {
        canCheckForUpdates = value
        onCanCheckChange?(value)
    }
}

@MainActor
struct AppUpdaterTests {
    @Test func releaseBuildsStartSparkleAtLaunch() {
        let fake = FakeUpdater()
        _ = AppUpdater(driver: fake, startsImmediately: true)
        #expect(fake.startCount == 1)
    }

    /// Debug builds never check on their own, but Check for Updates… still works.
    @Test func debugBuildsStartSparkleOnTheFirstManualCheck() {
        let fake = FakeUpdater()
        let updater = AppUpdater(driver: fake, startsImmediately: false)
        #expect(fake.startCount == 0)
        #expect(updater.canCheckForUpdates)

        updater.checkForUpdates()
        updater.checkForUpdates()

        #expect(fake.startCount == 1)
        #expect(fake.checkCount == 2)
    }

    @Test func settingsReadAndWriteSparkles() {
        let fake = FakeUpdater()
        fake.automaticallyChecksForUpdates = false
        fake.automaticallyDownloadsUpdates = true
        let updater = AppUpdater(driver: fake, startsImmediately: true)
        #expect(updater.automaticallyChecksForUpdates == false)
        #expect(updater.automaticallyDownloadsUpdates == true)

        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = false

        #expect(fake.automaticallyChecksForUpdates == true)
        #expect(fake.automaticallyDownloadsUpdates == false)
    }

    @Test func checkCommandIsDisabledWhileACheckRuns() {
        let fake = FakeUpdater()
        let updater = AppUpdater(driver: fake, startsImmediately: true)
        #expect(updater.canCheckForUpdates)

        fake.setCanCheckForUpdates(false)
        #expect(updater.canCheckForUpdates == false)

        fake.setCanCheckForUpdates(true)
        #expect(updater.canCheckForUpdates)
    }
}
