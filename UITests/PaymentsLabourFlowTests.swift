import XCTest

final class PaymentsLabourFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(locale: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--today", "2026-10-03"] + extra
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
    private func waitLabel(_ app: XCUIApplication, _ id: String, lacks text: String, timeout: TimeInterval = 8) {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: timeout), id)
        let done = expectation(for: NSPredicate(format: "NOT (label CONTAINS %@)", text), evaluatedWith: e)
        XCTAssertEqual(XCTWaiter().wait(for: [done], timeout: timeout), .completed, "\(id): '\(e.label)' still has '\(text)'")
    }
    /// A `.contain` container has no label of its own: join its descendants' labels.
    private func text(_ app: XCUIApplication, _ id: String) -> String {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 8), id)
        return ([e.label] + e.descendants(matching: .any).allElementsBoundByIndex.map(\.label)).joined(separator: " ")
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
    private func doneKeyboard(_ app: XCUIApplication, _ id: String) {
        let done = app.buttons[id]
        if done.waitForExistence(timeout: 2) { done.tap() }
    }
    private func tab(_ app: XCUIApplication, _ label: String) {
        let button = app.tabBars.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "tab \(label)")
        button.tap()
    }
    private func scrollTo(_ app: XCUIApplication, _ el: XCUIElement, maxSwipes: Int = 8) {
        var swipes = 0
        while !(el.exists && el.isHittable) && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
        XCTAssertTrue(el.exists, "not found after scrolling\n" + app.debugDescription)
    }
    /// 2b pattern: the list defaults to the In-work filter, so show every project before looking for the card.
    private func openProject(_ app: XCUIApplication, _ address: String, projectsTab: String = "Projects") {
        tab(app, projectsTab)
        let all = app.descendants(matching: .any)["projects_filter"].buttons.element(boundBy: 0)
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        all.tap()
        let card = containing(app, address)
        XCTAssertTrue(card.waitForExistence(timeout: 10), address)
        card.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
    }
    private func savePayment(_ app: XCUIApplication) {
        app.buttons["payment_save"].tap()
        XCTAssertTrue(app.buttons["payment_save"].waitForNonExistence(timeout: 5), "payment form still open\n" + app.debugDescription)
    }
    private func saveLabour(_ app: XCUIApplication) {
        app.buttons["labour_save"].tap()
        XCTAssertTrue(app.buttons["labour_save"].waitForNonExistence(timeout: 5), "labour form still open\n" + app.debugDescription)
    }

    /// (a) Stage 2 (overdue 11,400) from its schedule row: pre-filled, paid, Home moves by exactly 11,400.
    func testRecordPaymentFromScheduleRow() {
        let app = launch()
        openProject(app, "123 Main Street")
        let stage2 = element(app, "detail_schedule_row_1")
        scrollTo(app, stage2)
        XCTAssertTrue(stage2.label.contains("Overdue"), stage2.label)
        stage2.tap()
        waitLabel(app, "payment_chip_remaining", contains: "11,400.00")
        let amount = app.textFields["payment_amount"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        XCTAssertTrue(((amount.value as? String) ?? "").contains("11400"), String(describing: amount.value))
        savePayment(app)
        waitLabel(app, "detail_schedule_row_1", contains: "Paid")
        waitLabel(app, "detail_schedule_row_1", lacks: "Overdue")
        waitLabel(app, "detail_collected", contains: "19,000.00")
        tab(app, "Home")
        waitLabel(app, "home_total_collected", contains: "37,500.00")
        waitLabel(app, "home_total_outstanding", contains: "44,000.00")
        waitLabel(app, "home_total_cash", contains: "26,815.00")
        XCTAssertFalse(text(app, "home_attention").contains("overdue 5 days"))
    }

    /// (b) Home's "Record" next to the overdue row: two taps.
    func testRecordPaymentFromHomeAttention() {
        let app = launch()
        let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "attention_record_")).firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 15), "attention_record_*")
        record.tap()
        waitLabel(app, "payment_project", contains: "Basement Renovation")
        waitLabel(app, "payment_chip_remaining", contains: "11,400.00")
        savePayment(app)
        waitLabel(app, "home_total_collected", contains: "37,500.00")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "attention_record_")).firstMatch.exists)
    }

    /// (c) Kitchen: a payment not linked to any stage counts as collected only.
    func testUnlinkedPayment() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        let add = app.buttons["detail_payments_add"]
        scrollTo(app, add)
        add.tap()
        let none = app.buttons["payment_item_none"]
        XCTAssertTrue(none.waitForExistence(timeout: 5))
        none.tap()
        type(app, "payment_amount", "1000")
        doneKeyboard(app, "payment_keyboard_done")
        savePayment(app)
        let row = waitLabel(app, "detail_payment_row_0", contains: "1,000.00")
        XCTAssertTrue(row.contains("Not linked"), row)
        waitLabel(app, "detail_collected", contains: "1,000.00")
        waitLabel(app, "detail_schedule_row_0", contains: "Upcoming")
        tab(app, "Home")
        waitLabel(app, "home_total_collected", contains: "27,100.00")
        waitLabel(app, "home_total_outstanding", contains: "54,400.00")
    }

    /// (d) Delete Basement's deposit payment: the deposit is overdue again.
    func testDeletePayment() {
        let app = launch()
        openProject(app, "123 Main Street")
        let row = element(app, "detail_payment_row_0")
        scrollTo(app, row)
        XCTAssertTrue(row.label.contains("7,600.00"), row.label)
        row.tap()
        let delete = app.buttons["payment_delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        scrollTo(app, delete)
        delete.tap()
        // The confirmation dialog exposes its action twice (sheet + popover representation); tap the first.
        let confirm = app.buttons.matching(identifier: "payment_delete_confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.buttons["payment_save"].waitForNonExistence(timeout: 5))
        waitLabel(app, "detail_collected", contains: "$0.00")
        waitLabel(app, "detail_schedule_row_0", contains: "Overdue")
        tab(app, "Home")
        waitLabel(app, "home_total_collected", contains: "18,500.00")
        waitLabel(app, "home_total_outstanding", contains: "63,000.00")
        waitLabel(app, "home_total_cash", contains: "7,815.00")
        XCTAssertTrue(text(app, "home_attention").contains("overdue 20 days"))
    }

    /// (e) Add a crew member in More, then log a day for them: their rate fills in.
    func testAddCrewMemberThenLogLabour() {
        let app = launch()
        tab(app, "More")
        app.buttons["more_crew"].tap()
        let add = app.buttons["crew_add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        type(app, "crew_name", "Sam Patel")
        type(app, "crew_trade", "Electrician")
        type(app, "crew_daily_rate", "300")
        app.buttons["crew_save"].tap()
        let sam = button(app, prefix: "crew_row_", containing: "Sam Patel")
        XCTAssertTrue(sam.waitForExistence(timeout: 5), "crew row Sam Patel")
        XCTAssertTrue(sam.label.contains("300.00"), sam.label)
        openProject(app, "123 Main Street")
        let log = app.buttons["detail_labour_add"]
        scrollTo(app, log)
        log.tap()
        let person = button(app, prefix: "labour_person_", containing: "Sam Patel")
        XCTAssertTrue(person.waitForExistence(timeout: 5), "labour_person Sam Patel")
        person.tap()
        waitLabel(app, "labour_total", contains: "300.00")
        saveLabour(app)
        waitLabel(app, "detail_labour_total", contains: "5,900.00")
        tab(app, "Home")
        waitLabel(app, "home_total_spent", contains: "10,985.00")
    }

    /// (f) Mike + John, one day: labour 5,600 → 6,070, over its 6,000 estimate by exactly 70.
    func testLogLabourForTwoPeople() {
        let app = launch()
        openProject(app, "123 Main Street")
        let log = app.buttons["detail_labour_add"]
        scrollTo(app, log)
        log.tap()
        for name in ["Mike", "John"] {
            let person = button(app, prefix: "labour_person_", containing: name)
            XCTAssertTrue(person.waitForExistence(timeout: 5), name)
            person.tap()
        }
        waitLabel(app, "labour_total", contains: "470.00")
        saveLabour(app)
        waitLabel(app, "detail_labour_total", contains: "6,070.00")
        waitLabel(app, "detail_health", contains: "Over budget")
        waitLabel(app, "detail_health_reasons", contains: "70.00")
        tab(app, "Home")
        waitLabel(app, "home_total_spent", contains: "11,155.00")
        waitLabel(app, "home_total_cash", contains: "14,945.00")
    }

    /// (g) Edit David's entry 7 → 8 days.
    func testEditLabourEntry() {
        let app = launch()
        openProject(app, "123 Main Street")
        let david = button(app, prefix: "labour_row_", containing: "David")
        scrollTo(app, david)
        david.tap()
        XCTAssertTrue(app.textFields["labour_days"].waitForExistence(timeout: 5))
        replace(app, "labour_days", with: "8")
        doneKeyboard(app, "labour_keyboard_done")
        waitLabel(app, "labour_total", contains: "1,600.00")
        saveLabour(app)
        waitLabel(app, "detail_labour_total", contains: "5,800.00")
        tab(app, "Home")
        waitLabel(app, "home_total_spent", contains: "10,885.00")
    }

    /// (h) Vietnamese smoke: Payments/Labour cards and the crew list.
    func testVietnameseSmoke() {
        let app = launch(locale: "vi", extra: ["-AppleLocale", "vi_VN"])
        openProject(app, "123 Main Street", projectsTab: "Dự án")
        let payments = element(app, "detail_payments")
        scrollTo(app, payments)
        XCTAssertTrue(text(app, "detail_payments").contains("Thanh toán"))
        let log = app.buttons["detail_labour_add"]
        scrollTo(app, log)
        XCTAssertTrue(log.label.contains("Ghi công"), log.label)
        tab(app, "Thêm")
        waitLabel(app, "more_crew", contains: "Crew")
        app.buttons["more_crew"].tap()
        let mike = button(app, prefix: "crew_row_", containing: "Mike")
        XCTAssertTrue(mike.waitForExistence(timeout: 5), "crew row Mike")
        XCTAssertTrue(mike.label.contains("ngày"), mike.label)
    }
}
