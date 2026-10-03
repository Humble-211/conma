import XCTest
import Foundation

final class ProjectsFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", "en"] + extra
        app.launch()
        return app
    }
    private func tapTab(_ app: XCUIApplication, _ label: String) { app.tabBars.buttons[label].tap() }
    private func type(_ el: XCUIElement, _ text: String) { el.tap(); el.typeText(text) }
    private func row(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        return b.waitForExistence(timeout: 2) ? b : app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// (a) minimal project through the 4 required steps, skipping the rest
    func testCreateMinimalProject() {
        let app = launch()
        tapTab(app, "Projects")
        app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_kitchen"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Ann Lee").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "77 Elm Street"); app.buttons["wizard_continue"].tap()
        for _ in 0..<5 { app.buttons["wizard_skip"].tap() }                 // scope, timeline, labour, material, other
        type(app.textFields["wizard_contract_value"], "12000"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap(); app.buttons["wizard_skip"].tap()   // deposit, schedule
        XCTAssertTrue(app.textFields["wizard_review_name"].waitForExistence(timeout: 3))
        app.buttons["wizard_continue"].tap()                                 // Create project
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["77 Elm Street"].exists)
    }

    /// (b) full project with the four-stage template -> 4 rows, total == contract
    func testCreateProjectWithFourStageSchedule() {
        let app = launch()
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_roofing"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Maria Santos").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "9 Pine Road"); app.buttons["wizard_continue"].tap()
        for _ in 0..<5 { app.buttons["wizard_skip"].tap() }
        type(app.textFields["wizard_contract_value"], "20000"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap()                                     // deposit
        app.buttons["wizard_template_fourStage"].tap()
        XCTAssertTrue(app.textFields["wizard_schedule_row_3_amount"].waitForExistence(timeout: 3))
        app.buttons["wizard_continue"].tap()
        app.buttons["wizard_continue"].tap()                                 // Create
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
        let total = app.descendants(matching: .any)["detail_schedule_total"]
        XCTAssertTrue(total.waitForExistence(timeout: 3))
        XCTAssertTrue(total.label.contains("20,000.00"), total.label)
    }

    /// (c) close mid-way, relaunch, banner resumes at the same step
    func testDraftSurvivesRelaunch() {
        let app = launch()
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_bathroom"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "David Nguyen").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "5 Lake Ave"); app.buttons["wizard_continue"].tap()   // now on step 4
        app.buttons["wizard_close"].tap()
        app.buttons["Save draft"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["draft_banner"].waitForExistence(timeout: 3))
        app.terminate()
        let again = XCUIApplication()
        again.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", "en", "--keep-drafts"]
        again.launch()
        again.tabBars.buttons["Projects"].tap()
        XCTAssertTrue(again.descendants(matching: .any)["draft_banner"].waitForExistence(timeout: 5))
        XCTAssertTrue(again.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "4/12")).firstMatch.exists)
        again.buttons["draft_continue"].tap()
        XCTAssertTrue(again.textFields["wizard_scope_description"].waitForExistence(timeout: 3))
    }

    /// (d) edit estimate from detail -> total updates live
    func testEditEstimateFromDetail() {
        let app = launch()
        tapTab(app, "Projects")
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 5))
        app.buttons["detail_edit_estimate_material"].tap()
        XCTAssertTrue(app.buttons["wizard_line_add"].waitForExistence(timeout: 3))
        app.buttons["wizard_line_add"].tap()
        let newIndex = 4   // seed has 4 material lines
        type(app.textFields["wizard_line_label_\(newIndex)"], "Trim")
        type(app.textFields["wizard_line_amount_\(newIndex)"], "500")
        app.buttons["sheet_save"].tap()
        let total = app.descendants(matching: .any)["detail_estimate_total"]
        XCTAssertTrue(total.waitForExistence(timeout: 5))
        XCTAssertTrue(total.label.contains("15,300.00"), total.label)      // 14,800 seed (material 7,900 + labour 6,000 + other 900) + 500
    }

    /// (e) add a customer from More -> visible in wizard step 2
    func testCustomerAddedFromMoreAppearsInWizard() {
        let app = launch()
        tapTab(app, "More"); app.buttons["more_customers"].tap()
        app.buttons["customers_add"].tap()
        type(app.textFields["customer_form_name"], "Zed Young")
        app.buttons["customer_form_save"].tap()
        XCTAssertTrue(app.staticTexts["Zed Young"].waitForExistence(timeout: 5))
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_painting"].tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_customer_search"], "Zed")
        XCTAssertTrue(row(app, "Zed Young").waitForExistence(timeout: 3))
    }

    /// (f) Vietnamese locale: "1.500,50" is stored as 1500.50 and shown back
    func testVietnameseDecimalInput() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", "vi", "-AppleLocale", "vi_VN"]   // device region VN: app copies the device region into its locale
        app.launch()
        app.tabBars.buttons["Dự án"].tap(); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_kitchen"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Ann Lee").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "1 Test"); app.buttons["wizard_continue"].tap()
        for _ in 0..<5 { app.buttons["wizard_skip"].tap() }
        type(app.textFields["wizard_contract_value"], "1500,50"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap(); app.buttons["wizard_skip"].tap()
        app.buttons["wizard_continue"].tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
        let shown = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "1.500,50")).firstMatch
        let dump = app.descendants(matching: .any).allElementsBoundByIndex.map { $0.label }.filter { !$0.isEmpty }.joined(separator: " | ")
        XCTAssertTrue(shown.waitForExistence(timeout: 5), dump)
    }

    /// (g) deleting the last estimate line must not crash and must leave the list usable
    func testDeleteLastEstimateLineDoesNotCrash() {
        let app = launch()
        tapTab(app, "Projects"); app.buttons["projects_add"].tap()
        app.buttons["wizard_jobtype_kitchen"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Ann Lee").tap(); app.buttons["wizard_continue"].tap()
        type(app.textFields["wizard_address_line"], "3 Oak Lane"); app.buttons["wizard_continue"].tap()
        for _ in 0..<3 { app.buttons["wizard_skip"].tap() }                 // scope, timeline, labour -> Material
        app.buttons["wizard_line_add"].tap()
        app.buttons["wizard_line_add"].tap()
        type(app.textFields["wizard_line_label_0"], "Lumber")
        type(app.textFields["wizard_line_label_1"], "Nails")
        app.buttons["wizard_line_delete_1"].tap()
        XCTAssertTrue(app.textFields["wizard_line_label_0"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["wizard_line_label_1"].exists)
        app.buttons["wizard_line_add"].tap()
        XCTAssertTrue(app.textFields["wizard_line_label_1"].waitForExistence(timeout: 3))
    }
}
