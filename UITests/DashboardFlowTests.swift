import XCTest
import Foundation

final class DashboardFlowTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func launch(locale: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--today", "2026-10-03"] + extra
        app.launch()
        return app
    }

    private func tapTab(_ app: XCUIApplication, _ label: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "tab \(label)")
        tab.tap()
    }

    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any)[id] }

    private func label(_ app: XCUIApplication, _ id: String) -> String {
        let e = element(app, id)
        XCTAssertTrue(e.waitForExistence(timeout: 10), id)
        return e.label
    }

    private func containing(_ app: XCUIApplication, _ text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    private func labels(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty }.joined(separator: " | ")
    }

    /// A wizard/customer row shown either as a button or as plain text.
    private func row(_ app: XCUIApplication, _ label: String) -> XCUIElement {
        let b = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
        return b.waitForExistence(timeout: 3) ? b : app.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    private func scrollTo(_ app: XCUIApplication, _ el: XCUIElement, maxSwipes: Int = 6) {
        var swipes = 0
        while !(el.exists && el.isHittable) && swipes < maxSwipes { app.swipeUp(); swipes += 1 }
    }

    private func openProject(_ app: XCUIApplication, _ address: String, projectsTab: String = "Projects") {
        tapTab(app, projectsTab)
        // The list defaults to the Active filter when an in-work project exists; show every project.
        let all = app.descendants(matching: .any)["projects_filter"].buttons.element(boundBy: 0)
        XCTAssertTrue(all.waitForExistence(timeout: 10))
        all.tap()
        let card = containing(app, address)
        XCTAssertTrue(card.waitForExistence(timeout: 10), address)
        card.tap()
        XCTAssertTrue(app.otherElements["detail_header"].waitForExistence(timeout: 10))
    }

    /// (a) Home answers the dashboard questions with the seed numbers.
    func testHomeShowsAttentionAndTotals() {
        let app = launch()
        let attentionBox = app.otherElements["home_attention"]
        XCTAssertTrue(attentionBox.waitForExistence(timeout: 15))
        let attention = attentionBox.label + " " + attentionBox.descendants(matching: .any).allElementsBoundByIndex.map(\.label).joined(separator: " ")
        XCTAssertTrue(attention.contains("Payment risk"), attention)
        XCTAssertTrue(attention.contains("overdue 5 days"), attention)
        XCTAssertTrue(attention.contains("Starts today"), attention)
        let outstanding = label(app, "home_total_outstanding")
        XCTAssertTrue(outstanding.contains("55,400.00"), outstanding)
        let spent = label(app, "home_total_spent")
        XCTAssertTrue(spent.contains("10,685.00"), spent)
        let cash = label(app, "home_total_cash")
        XCTAssertTrue(cash.contains("15,415.00"), cash)
        let active = label(app, "home_total_active")
        XCTAssertNotNil(active.range(of: #"[^0-9]1$"#, options: .regularExpression), active)   // exactly 1, not 11
    }

    /// (b) Basement detail: cash position, health, timeline.
    func testBasementDetailInsights() {
        let app = launch()
        openProject(app, "123 Main Street")
        let cash = label(app, "detail_cash")
        // Negative sign directly in front of the amount (optionally with the currency symbol between): "-CA$3,085.00" / "−3,085.00".
        XCTAssertNotNil(cash.range(of: #"[-−]\s?(CA\$|\$)?\s?3,085\.00"#, options: .regularExpression), cash)
        let health = label(app, "detail_health")
        XCTAssertTrue(health.contains("Payment risk"), health)
        let timeline = label(app, "detail_timeline")
        XCTAssertTrue(timeline.contains("27 days left"), timeline)
    }

    /// (c) Status change writes activity and bumps Home active jobs.
    func testChangeStatusFromDetail() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        let statusButton = app.buttons["detail_status"]
        XCTAssertTrue(statusButton.waitForExistence(timeout: 10)); statusButton.tap()
        let inProgress = app.buttons["status_inProgress"]
        XCTAssertTrue(inProgress.waitForExistence(timeout: 5))
        inProgress.tap()
        let status = app.buttons["detail_status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let changed = NSPredicate(format: "label CONTAINS %@", "In progress")
        expectation(for: changed, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(containing(app, "Awaiting deposit → In progress").waitForExistence(timeout: 10), labels(app))
        tapTab(app, "Home")
        let active = element(app, "home_total_active")
        XCTAssertTrue(active.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label MATCHES %@", "(?s).*[^0-9]2"), evaluatedWith: active)   // exactly 2, not 12
        waitForExpectations(timeout: 10)
    }

    /// (d) Manual progress via the sheet.
    func testSetProgress() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        let progressButton = element(app, "detail_progress")
        XCTAssertTrue(progressButton.waitForExistence(timeout: 10)); progressButton.tap()
        let slider = app.sliders["progress_slider"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        let value = app.staticTexts["progress_value"]
        XCTAssertEqual(value.label, "0%")                                            // no manual progress yet
        slider.adjust(toNormalizedSliderPosition: 0.6)
        // The slider lands near 60; correct with the stepper (steps of 5) until it reads exactly 60%.
        // Wait for the stepper's buttons (they can appear a beat after the slider settles) and keep them on screen.
        let stepper = app.descendants(matching: .any)["progress_stepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 5), labels(app))
        let increment = stepper.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "Increment", "Increment")).firstMatch
        let decrement = stepper.buttons.matching(NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "Decrement", "Decrement")).firstMatch
        XCTAssertTrue(increment.waitForExistence(timeout: 5), labels(app))
        XCTAssertTrue(decrement.waitForExistence(timeout: 5), labels(app))
        var swipes = 0
        while !(increment.isHittable && decrement.isHittable) && swipes < 3 { value.swipeUp(); swipes += 1 }
        var steps = 0
        while value.label != "60%" && steps < 25 {
            let current = Int(value.label.dropLast()) ?? 0
            let button = current < 60 ? increment : decrement
            XCTAssertTrue(button.waitForExistence(timeout: 5), labels(app))
            button.tap()
            steps += 1
        }
        XCTAssertEqual(value.label, "60%")
        app.buttons["progress_save"].tap()
        expectation(for: NSPredicate(format: "label CONTAINS %@", "60%"), evaluatedWith: element(app, "detail_progress"))
        waitForExpectations(timeout: 10)
        XCTAssertTrue(containing(app, "— → 60%").waitForExistence(timeout: 10), labels(app))
    }

    /// (e) Delete project returns to the list and updates Home collected.
    func testDeleteProject() {
        let app = launch()
        openProject(app, "9 Birch Court")
        app.buttons["detail_menu"].tap()
        XCTAssertTrue(app.buttons["detail_delete"].waitForExistence(timeout: 5)); app.buttons["detail_delete"].tap()
        // The confirmation dialog exposes its action twice (sheet + popover representation); tap the first.
        let confirm = app.buttons.matching(identifier: "detail_delete_confirm").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.buttons["projects_add"].waitForExistence(timeout: 10))
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: containing(app, "Roof Replacement"))
        waitForExpectations(timeout: 10)
        tapTab(app, "Home")
        let collected = element(app, "home_total_collected")
        XCTAssertTrue(collected.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "label CONTAINS %@", "7,600.00"), evaluatedWith: collected)
        waitForExpectations(timeout: 10)
    }

    /// (f) Change customer.
    func testChangeCustomer() {
        let app = launch()
        openProject(app, "45 Oak Avenue")
        let change = app.buttons["detail_change_customer"]
        scrollTo(app, change)
        change.tap()
        let search = app.textFields["customer_picker_search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Maria")
        let pick = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "customer_pick_")).firstMatch
        XCTAssertTrue(pick.waitForExistence(timeout: 5))
        XCTAssertTrue(pick.label.contains("Maria Santos"), pick.label)
        pick.tap()
        XCTAssertTrue(containing(app, "David Nguyen → Maria Santos").waitForExistence(timeout: 10), labels(app))
        XCTAssertTrue(app.otherElements["detail_header"].staticTexts["Maria Santos"].waitForExistence(timeout: 10), labels(app))
    }

    /// (g) Timeline validation blocks Continue (hours per day out of range; the compact DatePicker is not scriptable).
    func testTimelineValidationBlocksContinue() {
        let app = launch()
        tapTab(app, "Projects")
        let add = app.buttons["projects_add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10)); add.tap()
        app.buttons["wizard_jobtype_kitchen"].tap(); app.buttons["wizard_continue"].tap()
        row(app, "Ann Lee").tap(); app.buttons["wizard_continue"].tap()
        let address = app.textFields["wizard_address_line"]
        XCTAssertTrue(address.waitForExistence(timeout: 5)); address.tap(); address.typeText("1 Test"); app.buttons["wizard_continue"].tap()
        app.buttons["wizard_skip"].tap()                                            // scope → timeline
        let hours = app.textFields["wizard_hours_per_day"]
        XCTAssertTrue(hours.waitForExistence(timeout: 5)); hours.tap(); hours.typeText("30")
        XCTAssertTrue(app.staticTexts["timeline_error_hoursPerDayOutOfRange"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["wizard_continue"].isEnabled)
        XCTAssertFalse(app.buttons["wizard_skip"].exists)                           // cannot skip past an invalid timeline either
        let current = (hours.value as? String) ?? ""
        hours.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: max(current.count, 2) + 2) + "8")
        let cleared = NSPredicate(format: "exists == false")
        expectation(for: cleared, evaluatedWith: app.staticTexts["timeline_error_hoursPerDayOutOfRange"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["wizard_continue"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["wizard_continue"].isEnabled)
    }

    /// (h) Vietnamese locale dates and timeline wording.
    func testVietnameseDatesAndTimeline() {
        let app = launch(locale: "vi", extra: ["-AppleLocale", "vi_VN"])
        let date = element(app, "home_date")
        XCTAssertTrue(date.waitForExistence(timeout: 15))
        XCTAssertTrue(date.label.lowercased().contains("3 tháng 10"), date.label)
        openProject(app, "123 Main Street", projectsTab: "Dự án")
        let timeline = label(app, "detail_timeline")
        XCTAssertTrue(timeline.contains("Còn 27 ngày"), timeline)
    }
}
