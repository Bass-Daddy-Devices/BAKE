import Foundation
import Observation
import Sparkle
import SwiftUI

/// The parts of Sparkle's updater BAKE uses, so tests can stand in for it.
protocol UpdaterDriving: AnyObject {
    var canCheckForUpdates: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    func start()
    func checkForUpdates()
    /// Calls `change` whenever `canCheckForUpdates` changes, for as long as the returned token is kept.
    func observeCanCheckForUpdates(_ change: @escaping (Bool) -> Void) -> AnyObject
}

/// BAKE's updater: backs BAKE › Check for Updates… and Settings › Updates.
@Observable
final class AppUpdater {
    @ObservationIgnored private let driver: UpdaterDriving
    @ObservationIgnored private var observation: AnyObject?
    private var started = false
    private var driverCanCheck = false

    /// False while a check is already running. Before Sparkle starts (Debug builds), a check is always allowed.
    var canCheckForUpdates: Bool { !started || driverCanCheck }

    var automaticallyChecksForUpdates: Bool {
        didSet { driver.automaticallyChecksForUpdates = automaticallyChecksForUpdates }
    }

    var automaticallyDownloadsUpdates: Bool {
        didSet { driver.automaticallyDownloadsUpdates = automaticallyDownloadsUpdates }
    }

    init(driver: UpdaterDriving, startsImmediately: Bool) {
        self.driver = driver
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        automaticallyDownloadsUpdates = driver.automaticallyDownloadsUpdates
        observation = driver.observeCanCheckForUpdates { [weak self] canCheck in
            self?.driverCanCheck = canCheck
        }
        if startsImmediately { startIfNeeded() }
    }

    func checkForUpdates() {
        startIfNeeded()
        driver.checkForUpdates()
    }

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        driver.start()
        driverCanCheck = driver.canCheckForUpdates
    }

    /// Debug builds don't start Sparkle until the first Check for Updates…, so Xcode runs never check on their own.
    static func live() -> AppUpdater {
        #if DEBUG
        AppUpdater(driver: SparkleDriver(), startsImmediately: false)
        #else
        AppUpdater(driver: SparkleDriver(), startsImmediately: true)
        #endif
    }
}

/// Sparkle's standard updater and its windows.
final class SparkleDriver: UpdaterDriving {
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller.updater.automaticallyDownloadsUpdates }
        set { controller.updater.automaticallyDownloadsUpdates = newValue }
    }

    func start() { controller.startUpdater() }

    func checkForUpdates() { controller.checkForUpdates(nil) }

    func observeCanCheckForUpdates(_ change: @escaping (Bool) -> Void) -> AnyObject {
        // Sparkle changes this on the main thread.
        controller.updater.observe(\.canCheckForUpdates, options: [.new]) { updater, _ in
            MainActor.assumeIsolated { change(updater.canCheckForUpdates) }
        }
    }
}

/// BAKE › Check for Updates…, right under About BAKE.
struct CheckForUpdatesCommand: Commands {
    let updater: AppUpdater

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
        }
    }
}
