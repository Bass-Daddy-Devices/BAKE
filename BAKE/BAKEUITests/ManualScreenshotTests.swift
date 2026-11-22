import XCTest

/// Captures the user manual's screenshots. Not part of the normal test run's assertions about
/// behaviour; run through Tools/manual/capture_screenshots.sh, which exports the attachments.
final class ManualScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        // Only when capture_screenshots.sh asks (TEST_RUNNER_BAKE_MANUAL_SHOTS=1), not in every UI-test run.
        try XCTSkipUnless(ProcessInfo.processInfo.environment["BAKE_MANUAL_SHOTS"] == "1", "manual screenshots not requested")
        continueAfterFailure = false
    }

    @MainActor
    private func launch(scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "-manualScene", scene]
        app.launch()
        if app.dialogs.firstMatch.waitForExistence(timeout: 2) || app.sheets.firstMatch.exists {
            app.typeKey(.escape, modifierFlags: [])
        }
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5))
        sleep(2)  // the scene's .task runs after the window appears; let cards settle
        return app
    }

    private func save(_ screenshot: XCUIScreenshot, as name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testQuickstartPatch() {
        let app = launch(scene: "quickstart")
        XCTAssertTrue(app.descendants(matching: .any)["node.filters"].firstMatch.waitForExistence(timeout: 5))
        save(app.windows.firstMatch.screenshot(), as: "quickstart-patch")
        save(app.descendants(matching: .any)["node.filters"].firstMatch.screenshot(), as: "modulation-lane")
        app.typeKey("=", modifierFlags: .command)
        app.typeKey("=", modifierFlags: .command)
        save(app.windows.firstMatch.screenshot(), as: "pins-and-wire")
    }

    @MainActor func testEmptyDocumentAndSearch() {
        let app = launch(scene: "empty")
        save(app.windows.firstMatch.screenshot(), as: "empty-document")
        app.typeKey("k", modifierFlags: .command)
        app.typeText("fil")
        sleep(1)
        save(app.windows.firstMatch.screenshot(), as: "node-search")
    }

    @MainActor func testCardFrontAndPage2() {
        let app = launch(scene: "card")
        let card = app.descendants(matching: .any)["node.filters"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        save(card.screenshot(), as: "card-front")
        card.descendants(matching: .any)["flip"].firstMatch.click()
        sleep(1)
        save(card.screenshot(), as: "card-page2")
    }

    @MainActor func testClockBatchAndGroup() {
        for (scene, name) in [("clock", "clock-envelope"), ("batch", "batch-patch"), ("group", "group")] {
            let app = launch(scene: scene)
            save(app.windows.firstMatch.screenshot(), as: name)
            app.terminate()
        }
    }

    @MainActor func testSettings() {
        let app = launch(scene: "empty")
        app.typeKey(",", modifierFlags: .command)
        let settings = app.windows.containing(.any, identifier: "settings.outputDevice").firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        save(settings.screenshot(), as: "settings")
    }
}
