import Foundation
import XCTest

final class SmokeTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func pickerRow(_ app: XCUIApplication, labeled label: String) -> XCUIElement {
        let byButton = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        if byButton.waitForExistence(timeout: 2) { return byButton }
        return app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
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
        XCTAssertTrue(app.staticTexts["No jobs yet"].waitForExistence(timeout: 5))
    }

    func testAllTabsOpenWithSeedData() {
        let app = launch(["--seed-sample-data", "--locale", "en"])
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        for (tab, title) in [("Projects", "Projects"), ("Calendar", "Calendar"), ("Expenses", "Expenses"), ("More", "More")] {
            app.tabBars.buttons[tab].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), "tab \(tab)")
        }
    }

    /// A language row of the Settings picker, addressed by the picker identifier plus its (language-native) label.
    private func languageRow(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let row = app.buttons.matching(identifier: "settings_language_picker").matching(NSPredicate(format: "label == %@", label)).firstMatch
        return row.waitForExistence(timeout: 5) ? row : pickerRow(app, labeled: label)
    }

    private func dump(_ app: XCUIApplication) -> String {
        "nav=\(app.navigationBars.allElementsBoundByIndex.map(\.identifier)) tabs=\(app.tabBars.buttons.allElementsBoundByIndex.map(\.label))"
    }

    func testLanguageSwitchUpdatesOpenScreenAndTabsImmediately() {
        let app = launch(["--seed-sample-data", "--locale", "en"])
        XCTAssertTrue(app.tabBars.buttons["More"].waitForExistence(timeout: 15))
        app.tabBars.buttons["More"].tap()
        XCTAssertTrue(app.buttons["more_settings"].waitForExistence(timeout: 10))
        app.buttons["more_settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), dump(app))
        languageRow(app, "Tiếng Việt").tap()
        // Review Focus #5: the open screen and the tab bar change without leaving the screen.
        XCTAssertTrue(app.navigationBars["Cài đặt"].waitForExistence(timeout: 10), dump(app))
        XCTAssertTrue(app.tabBars.buttons["Trang chủ"].waitForExistence(timeout: 10), dump(app))
        XCTAssertTrue(app.tabBars.buttons["Chi phí"].waitForExistence(timeout: 10), dump(app))
        languageRow(app, "English").tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10), dump(app))
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10), dump(app))
    }
}
