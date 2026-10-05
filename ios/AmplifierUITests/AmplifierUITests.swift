import XCTest

final class AmplifierUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
        return app
    }

    func testScopeAndGainControls() {
        let app = launch()
        XCTAssertTrue(app.buttons["importMedia"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["iPhone boost applies inside Amplifier. Audio from YouTube, Chrome, and other apps isn’t changed."].exists)
        XCTAssertEqual(app.staticTexts["gainValue"].label, "+6.0 dB")
        app.sliders["gainSlider"].adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(app.staticTexts["gainValue"].label, "+0.0 dB")
        let toggle = app.switches["boostToggle"]
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testSampleRunsRealGainTapAndCanBeBypassed() {
        let app = launch()
        app.buttons["loadSample"].tap()
        let button = app.buttons["playPause"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: button)
        waitForExpectations(timeout: 10)
        button.tap()
        let processing = NSPredicate(format: "label == %@", "Boosting this file.")
        expectation(for: processing, evaluatedWith: app.staticTexts["boostStatus"])
        waitForExpectations(timeout: 10)
        app.switches["boostToggle"].tap()
        XCTAssertEqual(app.staticTexts["boostStatus"].label, "Boost bypassed for this file.")
        button.tap()
        XCTAssertEqual(button.label, "Play")
        app.buttons["removeMedia"].tap()
        XCTAssertTrue(app.buttons["loadSample"].waitForExistence(timeout: 5))
    }

    func testPlaybackContinuesWhenLeavingTheApp() {
        let app = launch()
        app.buttons["loadSample"].tap()
        let button = app.buttons["playPause"]
        XCTAssertTrue(button.waitForExistence(timeout: 15))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: button)
        waitForExpectations(timeout: 10)
        button.tap()
        expectation(for: NSPredicate(format: "label == %@", "Pause"), evaluatedWith: button)
        waitForExpectations(timeout: 5)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertEqual(button.label, "Pause")
        button.tap()
    }
}
