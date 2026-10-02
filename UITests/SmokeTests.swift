import XCTest

final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing"] + extra
        app.launch()
        return app
    }

    func testSetupFlowCreatesCompanyAndShowsTabs() {
        let app = launch(["--locale", "en"])
        let company = app.textFields["setup_company_name"]
        XCTAssertTrue(company.waitForExistence(timeout: 10))
        company.tap(); company.typeText("Northwind Contracting")
        let owner = app.textFields["setup_owner_name"]
        owner.tap(); owner.typeText("Duc")
        app.buttons["setup_start"].tap()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["No jobs yet"].exists)
    }

    func testAllTabsOpenWithSeedData() {
        let app = launch(["--seed-sample-data", "--locale", "en"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["123 Main Street"].waitForExistence(timeout: 5))
        for (tab, title) in [("Projects", "Projects"), ("Calendar", "Calendar"), ("Expenses", "Expenses"), ("More", "More")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "tab \(tab)")
        }
    }

    func testLanguageSwitchUpdatesOpenScreenAndTabsImmediately() {
        let app = launch(["--seed-sample-data", "--locale", "en"])
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 10))
        app.tabBars.buttons["More"].tap()
        app.buttons["more_settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Tiếng Việt"].tap()
        // Review Focus #5: the open screen and the tab bar change without leaving the screen.
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Trang chủ"].exists)
        XCTAssertTrue(app.tabBars.buttons["Chi phí"].exists)
        app.buttons["English"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }
}
