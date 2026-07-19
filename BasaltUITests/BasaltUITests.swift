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
        XCTAssertTrue(app.otherElements["chat-view"].waitForExistence(timeout: 8))
        attachScreenshot(named: "01-chat")

        let models = app.buttons["models-navigation"].firstMatch
        if models.waitForExistence(timeout: 3) {
            models.tap()
        } else {
            app.navigationBars.buttons.firstMatch.tap()
            app.buttons["models-navigation"].firstMatch.tap()
        }
        XCTAssertTrue(app.otherElements["model-library"].waitForExistence(timeout: 5))
        attachScreenshot(named: "02-model-library")

        app.buttons["library-add-model"].tap()
        XCTAssertTrue(app.buttons["choose-gguf-file"].waitForExistence(timeout: 5))
        attachScreenshot(named: "03-import-model")
        app.buttons["Close"].tap()

        let settings = app.buttons["settings-navigation"].firstMatch
        if settings.waitForExistence(timeout: 2) {
            settings.tap()
            XCTAssertTrue(app.otherElements["settings-view"].waitForExistence(timeout: 5))
            attachScreenshot(named: "04-settings")
        }
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
