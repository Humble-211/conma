import XCTest

final class ExpensesFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(locale: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--today", "2026-10-03", "--fake-scanner"] + extra
        app.launch()
        return app
    }
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }
    private func containing(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }
    private func button(_ app: XCUIApplication, prefix: String, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", prefix, text)).firstMatch
    }
    @discardableResult
    private func waitLabel(_ app: XCUIApplication, _ id: String, contains text: String, timeout: TimeInterval = 8) -> String {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), id)
        let done = expectation(for: NSPredicate(format: "label CONTAINS %@", text), evaluatedWith: e)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed, "\(id): '\(e.label)' lacks '\(text)'")
        return e.label
    }
    private func type(_ app: XCUIApplication, _ id: String, _ text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        field.tap()
        field.typeText(text)
    }
    private func replace(_ app: XCUIApplication, _ id: String, with text: String) {
        let field = app.textFields[id]
        XCTAssertTrue(field.waitForExistence(timeout: 5), id)
        let current = (field.value as? String) ?? ""
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()        // caret at the end (trailing-aligned text)
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }
    private func doneKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["expense_keyboard_done"]
        if done.waitForExistence(timeout: 2) { done.tap() }
    }
    private func skipScanner(_ app: XCUIApplication) {
        let cancel = app.buttons["scanner_cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5), "scanner_cancel\n" + app.debugDescription)
        cancel.tap()
    }
    private func save(_ app: XCUIApplication) {
        app.buttons["expense_save"].tap()
        XCTAssertTrue(app.buttons["expense_save"].waitForNonExistence(timeout: 5), "form still open\n" + app.debugDescription)
    }
    private func tab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "tab \(label)")
        button.tap()
    }
    private func scrollTo(_ app: XCUIApplication, _ el: XCUIElement, maxSwipes: Int = 5) {
        var swipes = 0
        while !(el.exists && el.isHittable) && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
    }
    /// 2b pattern: the list defaults to the In-work filter, so show every project before looking for the card.
    private func openProject(_ app: XCUIApplication, _ address: String) {
        tab(app, "Projects")
        let all = app.descendants(matching: .any)["projects_filter"].buttons.element(boundBy: 0)
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        all.tap()
        let card = containing(app, address)
        XCTAssertTrue(card.waitForExistence(timeout: 10), address)
        card.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
    }
    private func openExpenseRow(_ app: XCUIApplication, _ vendor: String) {
        let row = button(app, prefix: "expense_row_", containing: vendor)
        XCTAssertTrue(row.waitForExistence(timeout: 5), vendor)
        row.tap()
        XCTAssertTrue(app.textFields["expense_amount"].waitForExistence(timeout: 5))
    }

    /// (a) Quick add from Home: Basement is the default project; Fuel 250 pushes "other" over its 900 estimate.
    func testAddExpenseFromHomeUpdatesDashboard() {
        let app = launch()
        let add = app.buttons["home_add_expense"]
        XCTAssertTrue(add.waitForExistence(timeout: 10), "home_add_expense")
        add.tap()
        skipScanner(app)
        waitLabel(app, "expense_project", contains: "Basement Renovation")
        type(app, "expense_amount", "250")
        doneKeyboard(app)
        app.buttons["expense_category_fuel"].tap()
        save(app)
        waitLabel(app, "home_total_spent", contains: "10,935.00")
        waitLabel(app, "home_total_cash", contains: "15,165.00")
        XCTAssertTrue(containing(app, "Over budget").waitForExistence(timeout: 5), "Over budget on Home")
        openProject(app, "123 Main Street")
        waitLabel(app, "detail_health", contains: "Over budget")
        let cash = waitLabel(app, "detail_cash", contains: "3,335.00")
        XCTAssertTrue(cash.contains("-") || cash.contains("−"), cash)
        waitLabel(app, "detail_health_reasons", contains: "28.00")
        tab(app, "Expenses")
        waitLabel(app, "expenses_total_this_month", contains: "1,945.00")
    }

    /// (b) Scanner page + tax by percent from the Expenses tab.
    func testTaxPercentAndReceiptFromTab() {
        let app = launch()
        tab(app, "Expenses")
        XCTAssertTrue(app.buttons["expenses_add"].waitForExistence(timeout: 5), "expenses_add")
        app.buttons["expenses_add"].tap()
        let capture = app.buttons["scanner_capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5), "scanner_capture\n" + app.debugDescription)
        capture.tap()
        waitLabel(app, "expense_receipt_count", contains: "1/10")
        XCTAssertTrue(element(app, "expense_receipt_thumb_0").exists)
        type(app, "expense_amount", "100")
        doneKeyboard(app)
        app.buttons["expense_tax_percent_toggle"].tap()
        type(app, "expense_tax_percent", "13")
        doneKeyboard(app)
        waitLabel(app, "expense_tax_amount", contains: "13.00")
        waitLabel(app, "expense_total", contains: "113.00")
        app.buttons["expense_category_materials"].tap()
        save(app)
        waitLabel(app, "expenses_total_this_month", contains: "1,808.00")
        let row = button(app, prefix: "expense_row_", containing: "113.00")
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("1-page receipt"), row.label)
    }

    /// (c) Edit Drywall 1,500 → 1,600, then delete it.
    func testEditThenDeleteExpense() {
        let app = launch()
        tab(app, "Expenses")
        waitLabel(app, "expenses_total_this_month", contains: "1,695.00")
        openExpenseRow(app, "Drywall")
        replace(app, "expense_amount", with: "1600")
        doneKeyboard(app)
        save(app)
        waitLabel(app, "expenses_total_this_month", contains: "1,795.00")
        openExpenseRow(app, "Drywall")
        app.swipeUp()
        app.buttons["expense_delete"].tap()
        // The confirmation dialog exposes its action twice (sheet + popover representation); tap the first.
        let confirm = app.buttons.matching(identifier: "expense_delete_confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        waitLabel(app, "expenses_total_this_month", contains: "$0.00")
        XCTAssertFalse(button(app, prefix: "expense_row_", containing: "Drywall").exists)
        openProject(app, "123 Main Street")
        waitLabel(app, "detail_spent", contains: "8,990.00")
    }

    /// (d) Lumber's two receipt pages in the viewer.
    func testReceiptViewerPagesAndShare() {
        let app = launch()
        tab(app, "Expenses")
        openExpenseRow(app, "Lumber")
        let thumb = element(app, "expense_receipt_thumb_0")
        XCTAssertTrue(thumb.waitForExistence(timeout: 5))
        thumb.tap()
        XCTAssertTrue(element(app, "receipt_viewer").waitForExistence(timeout: 5))
        waitLabel(app, "receipt_page_label", contains: "Page 1 of 2")
        app.swipeLeft()
        waitLabel(app, "receipt_page_label", contains: "Page 2 of 2")
        XCTAssertTrue(element(app, "receipt_share").exists)
        app.buttons["receipt_close"].tap()
        XCTAssertTrue(app.textFields["expense_amount"].waitForExistence(timeout: 5))
        app.buttons["expense_cancel"].tap()
    }

    /// (e) Custom categories: create, change an unused group, then the group locks once used.
    func testCustomCategoriesAndGroupLock() {
        let app = launch()
        tab(app, "More")
        app.buttons["more_categories"].tap()
        XCTAssertTrue(app.buttons["categories_add"].waitForExistence(timeout: 5))
        app.buttons["categories_add"].tap()
        type(app, "category_name", "Dump runs")
        app.buttons["category_save"].tap()
        let dumpRow = button(app, prefix: "category_row_", containing: "Dump runs")
        XCTAssertTrue(dumpRow.waitForExistence(timeout: 5))
        XCTAssertTrue(dumpRow.label.contains("Other"), dumpRow.label)
        button(app, prefix: "category_row_", containing: "Scaffolding").tap()
        XCTAssertTrue(app.buttons["category_group_material"].waitForExistence(timeout: 5))
        app.buttons["category_group_material"].tap()
        app.buttons["category_save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@ AND label CONTAINS %@", "category_row_", "Scaffolding", "Materials"))
                        .firstMatch.waitForExistence(timeout: 5))
        tab(app, "Expenses")
        XCTAssertTrue(app.buttons["expenses_add"].waitForExistence(timeout: 5), "expenses_add")
        app.buttons["expenses_add"].tap()
        skipScanner(app)
        type(app, "expense_amount", "40")
        doneKeyboard(app)
        app.buttons["expense_category_more"].tap()
        // The picker lists the 13 built-ins first; the lazy list creates the custom rows only once scrolled near.
        let pick = button(app, prefix: "category_pick_custom_", containing: "Dump runs")
        XCTAssertTrue(element(app, "category_picker").waitForExistence(timeout: 5))
        var swipes = 0
        while !(pick.exists && pick.isHittable) && swipes < 6 { element(app, "category_picker").swipeUp(); swipes += 1 }
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        pick.tap()
        save(app)
        tab(app, "More")                                                     // categories screen is still pushed
        XCTAssertTrue(dumpRow.waitForExistence(timeout: 5))
        dumpRow.tap()
        XCTAssertTrue(element(app, "category_group_locked").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["category_group_material"].isEnabled)
    }

    /// (f) Project section: preset project from Kitchen's detail; Basement "See all" is filtered.
    func testProjectExpensesSection() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        let empty = element(app, "detail_expenses_empty")
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        let add = app.buttons["detail_expenses_add"]
        scrollTo(app, add)
        add.tap()
        skipScanner(app)
        waitLabel(app, "expense_project", contains: "Kitchen Renovation")
        type(app, "expense_amount", "75")
        doneKeyboard(app)
        app.buttons["expense_category_fuel"].tap()
        save(app)
        waitLabel(app, "detail_expense_row_0", contains: "75.00")
        waitLabel(app, "detail_spent", contains: "75.00")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openProject(app, "123 Main Street")
        let all = app.buttons["detail_expenses_all"]
        scrollTo(app, all, maxSwipes: 6)
        all.tap()
        waitLabel(app, "expenses_filter_project", contains: "Basement Renovation")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "expense_row_")).count, 3)
    }

    /// (g) Default tax % pre-fills new expenses.
    func testDefaultTaxPrefill() {
        let app = launch()
        tab(app, "More")
        app.buttons["more_settings"].tap()
        type(app, "settings_default_tax", "13")
        // The decimal keyboard covers the tab bar: pop Settings first (also dismisses the keyboard).
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["more_settings"].waitForExistence(timeout: 5))
        tab(app, "Expenses")
        XCTAssertTrue(app.buttons["expenses_add"].waitForExistence(timeout: 5), "expenses_add")
        app.buttons["expenses_add"].tap()
        skipScanner(app)
        type(app, "expense_amount", "200")
        doneKeyboard(app)
        waitLabel(app, "expense_tax_amount", contains: "26.00")
        waitLabel(app, "expense_total", contains: "226.00")
    }

    /// (g2) An out-of-range default tax is not saved, and its prefix ("100" on the way to "1000") is not saved either.
    func testInvalidDefaultTaxIsNotSaved() {
        let app = launch()
        tab(app, "More")
        app.buttons["more_settings"].tap()
        type(app, "settings_default_tax", "1000")
        waitLabel(app, "settings_default_tax_kept", contains: "No default tax")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["more_settings"].waitForExistence(timeout: 5))
        tab(app, "Expenses")
        XCTAssertTrue(app.buttons["expenses_add"].waitForExistence(timeout: 5), "expenses_add")
        app.buttons["expenses_add"].tap()
        skipScanner(app)
        type(app, "expense_amount", "200")
        doneKeyboard(app)
        waitLabel(app, "expense_total", contains: "200.00")
        XCTAssertFalse(element(app, "expense_tax_amount").exists, "no % tax pre-filled")
    }

    /// (h) Vietnamese headers and folded search.
    func testVietnameseHeadersAndSearch() {
        let app = launch(locale: "vi", extra: ["-AppleLocale", "vi_VN"])
        XCTAssertTrue(app.tabBars.buttons["Chi phí"].waitForExistence(timeout: 10))
        tab(app, "Chi phí")
        waitLabel(app, "expenses_total_this_month", contains: "Tháng này")
        waitLabel(app, "expenses_total_last_month", contains: "Tháng trước")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("dumpster")
        XCTAssertTrue(button(app, prefix: "expense_row_", containing: "Dumpster rental").waitForExistence(timeout: 5))
        XCTAssertFalse(button(app, prefix: "expense_row_", containing: "Drywall").exists)
    }
}
