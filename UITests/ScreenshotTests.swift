import XCTest

final class ScreenshotTests: XCTestCase {
    private func launch(locale: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--appearance", appearance, "--today", "2026-10-03"]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureAllScreens() {
        let tabs = ["home", "projects", "calendar", "expenses", "more"]
        for locale in ["en", "vi"] {
            for appearance in ["light", "dark"] {
                let app = launch(locale: locale, appearance: appearance)
                XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
                let tabButtons = app.tabBars.buttons
                for (index, tab) in tabs.enumerated() {
                    tabButtons.element(boundBy: index).tap()
                    _ = app.navigationBars.firstMatch.waitForExistence(timeout: 5)
                    snap(app, "\(tab)_\(locale)_\(appearance)")
                }
                app.buttons["more_gallery"].tap()
                XCTAssertTrue(app.scrollViews["component_gallery"].waitForExistence(timeout: 5))
                snap(app, "gallery_\(locale)_\(appearance)")
                // Leave the gallery right away: its looping loading indicator keeps the app from going idle,
                // which slows later queries on the More tab.
                app.navigationBars.buttons.element(boundBy: 0).tap()
                _ = app.buttons["more_customers"].waitForExistence(timeout: 5)
                if appearance == "light" {
                    app.tabBars.buttons.element(boundBy: 1).tap()
                    app.buttons["projects_add"].tap()
                    let steps = ["jobType", "customer", "location", "scope", "timeline", "labour", "material", "other", "price", "deposit", "schedule", "review"]
                    app.buttons["wizard_jobtype_basementRenovation"].tap(); snap(app, "wizard_1_\(steps[0])_\(locale)")
                    app.buttons["wizard_continue"].tap(); snap(app, "wizard_2_\(steps[1])_\(locale)")
                    let ann = app.buttons.matching(NSPredicate(format: "label == %@", "Ann Lee")).firstMatch
                    if ann.waitForExistence(timeout: 2) { ann.tap() } else { app.staticTexts.matching(NSPredicate(format: "label == %@", "Ann Lee")).firstMatch.tap() }
                    app.buttons["wizard_continue"].tap()
                    app.textFields["wizard_address_line"].tap(); app.textFields["wizard_address_line"].typeText("88 Screenshot Lane")
                    snap(app, "wizard_3_\(steps[2])_\(locale)")
                    for i in 3..<12 {
                        let next = app.buttons["wizard_continue"]
                        if next.exists && next.isEnabled { next.tap() } else { app.buttons["wizard_skip"].tap() }
                        if i == 8 { app.textFields["wizard_contract_value"].tap(); app.textFields["wizard_contract_value"].typeText("38000") }
                        if i == 10 { app.buttons["wizard_template_fourStage"].tap() }
                        snap(app, "wizard_\(i + 1)_\(steps[i])_\(locale)")
                    }
                    app.buttons["wizard_close"].tap()
                    app.buttons[locale == "vi" ? "Bỏ nháp" : "Discard draft"].tap()
                    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
                    _ = app.otherElements["detail_header"].waitForExistence(timeout: 5)
                    snap(app, "detail_\(locale)_light")
                    app.buttons["detail_status"].tap()
                    _ = app.buttons["status_inProgress"].waitForExistence(timeout: 5)
                    snap(app, "status_picker_\(locale)")
                    app.buttons["sheet_cancel"].tap()
                    _ = app.otherElements["detail_header"].waitForExistence(timeout: 5)
                    app.swipeUp(); app.swipeUp()
                    snap(app, "detail_full_\(locale)")
                    let allActivity = app.buttons["detail_activity_all"]
                    var swipes = 0
                    while !(allActivity.exists && allActivity.isHittable) && swipes < 4 { app.swipeUp(); swipes += 1 }
                    allActivity.tap()
                    _ = app.descendants(matching: .any)["activity_list"].waitForExistence(timeout: 5)
                    snap(app, "activity_\(locale)")
                    app.navigationBars.buttons.element(boundBy: 0).tap()                       // activity → detail
                    _ = app.otherElements["detail_header"].waitForExistence(timeout: 5)
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                    app.tabBars.buttons.element(boundBy: 4).tap()
                    var attempts = 0
                    while !app.buttons["more_customers"].waitForExistence(timeout: 3) && attempts < 3 {   // something is still pushed: pop to root
                        let back = app.navigationBars.buttons["BackButton"]
                        if back.exists { back.tap() } else { app.tabBars.buttons.element(boundBy: 4).tap() }
                        attempts += 1
                    }
                    app.buttons["more_customers"].tap()
                    snap(app, "customers_\(locale)")
                    app.cells.firstMatch.tap(); snap(app, "customer_profile_\(locale)")
                } else {
                    app.tabBars.buttons.element(boundBy: 1).tap()
                    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "123 Main Street")).firstMatch.tap()
                    _ = app.otherElements["detail_header"].waitForExistence(timeout: 5)
                    snap(app, "detail_\(locale)_dark")
                }
                app.terminate()
            }
        }
    }
}
