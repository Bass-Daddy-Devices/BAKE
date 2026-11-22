//
//  BAKEUITests.swift
//  BAKEUITests
//
//  Created by Chris Connelly on 2026-10-09.
//

import XCTest

final class BAKEUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testSettingsHaveUpdateSwitchesAndTheMenuHasCheckForUpdates() throws {
        let app = XCUIApplication()
        app.launch()

        let appMenu = app.menuBars.menuBarItems["BAKE"]
        appMenu.click()
        XCTAssertTrue(app.menuItems["Check for Updates…"].exists)
        app.typeKey(.escape, modifierFlags: [])

        app.typeKey(",", modifierFlags: .command)
        // A grouped Form can draw a Toggle as a checkbox or a switch, so match by identifier only.
        let controls = app.descendants(matching: .any)
        XCTAssertTrue(controls["settings.checkAutomatically"].waitForExistence(timeout: 5))
        XCTAssertTrue(controls["settings.downloadAutomatically"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
