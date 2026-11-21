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
