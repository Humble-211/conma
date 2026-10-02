import XCTest

final class ScreenshotTests: XCTestCase {
    private func launch(locale: String, appearance: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--seed-sample-data", "--locale", locale, "--appearance", appearance]
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
                app.terminate()
            }
        }
    }
}
