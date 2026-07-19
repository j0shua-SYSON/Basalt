import XCTest

final class BasaltUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testVisualWalkthrough() throws {
        XCTAssertTrue(app.buttons["model-selector"].waitForExistence(timeout: 10))
        attachScreenshot(named: "01-chat")

        tapSidebarItem("models-navigation")
        XCTAssertTrue(app.navigationBars["Models"].waitForExistence(timeout: 5))
        attachScreenshot(named: "02-model-library")

        app.buttons["library-add-model"].tap()
        XCTAssertTrue(app.buttons["choose-gguf-file"].waitForExistence(timeout: 5))
        attachScreenshot(named: "03-import-model")
        app.buttons["Close"].tap()

        tapSidebarItem("settings-navigation")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        attachScreenshot(named: "04-settings")
    }

    private func tapSidebarItem(_ identifier: String) {
        let item = app.buttons[identifier].firstMatch
        if !item.waitForExistence(timeout: 2) {
            let sidebar = app.buttons["Show Sidebar"].firstMatch
            XCTAssertTrue(sidebar.waitForExistence(timeout: 3))
            sidebar.tap()
        }
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
