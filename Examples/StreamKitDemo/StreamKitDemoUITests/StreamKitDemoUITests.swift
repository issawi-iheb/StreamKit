//
//  StreamKitDemoUITests.swift
//  StreamKitDemoUITests
//
//  Created by Iheb on 13/10/2026.
//

import XCTest

final class StreamKitDemoUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testBearerAuthenticationExampleShowsCredentialInputs() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["demo.bearer-authenticated-hls"].tap()

        XCTAssertTrue(app.textFields["HTTPS media URL"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["Trusted media hosts"].exists)
        XCTAssertTrue(app.secureTextFields["Bearer token"].exists)
        XCTAssertTrue(app.buttons["Load HLS stream"].exists)
    }

    @MainActor
    func testAudioSessionExampleExplainsInterruptionAndBackgroundPlayback() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["demo.audio-session"].tap()

        XCTAssertTrue(app.staticTexts["Audio session and interruption handling"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "audio-session-playback-phase")
                .firstMatch.exists
        )
    }

    @MainActor
    func testAxinomFairPlayExampleShowsLiveTestInputs() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["demo.axinom-fairplay"].tap()

        XCTAssertTrue(app.textFields["Protected HLS manifest URL"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["FairPlay certificate URL"].exists)
        XCTAssertTrue(app.textFields["FairPlay license URL"].exists)
        XCTAssertTrue(app.secureTextFields["Axinom license token"].exists)
        XCTAssertTrue(app.buttons["fairPlayLoadProtectedStream"].exists)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
