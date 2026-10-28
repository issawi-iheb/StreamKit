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

        tapMenuEntry("demo.bearer-authenticated-hls", in: app)

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

        tapMenuEntry("demo.axinom-fairplay", in: app)

        XCTAssertTrue(app.textFields["Protected HLS manifest URL"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["FairPlay certificate URL"].exists)
        XCTAssertTrue(app.textFields["FairPlay license URL"].exists)
        XCTAssertTrue(app.secureTextFields["Axinom license token"].exists)
        XCTAssertTrue(app.buttons["fairPlayLoadProtectedStream"].exists)
    }

    @MainActor
    func testPresentationExampleShowsAVKitAndPictureInPictureOptions() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["demo.presentation-avkit-pip"].tap()

        XCTAssertTrue(app.staticTexts["StreamKit Player and Picture in Picture"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "presentation-renderer-picker")
                .firstMatch.exists
        )
        XCTAssertTrue(app.switches["presentation-automatic-pip"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "presentation-playback-phase")
                .firstMatch.exists
        )
    }

    @MainActor
    func testPresentationRouteCanBeRemovedAndRestored() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["demo.presentation-avkit-pip"].tap()
        let playerInterface = app.staticTexts["presentation-player-interface-ready"]
        XCTAssertTrue(playerInterface.waitForExistence(timeout: 5))

        app.navigationBars.buttons["StreamKit"].tap()
        let presentationEntry = app.buttons["demo.presentation-avkit-pip"]
        XCTAssertTrue(presentationEntry.waitForExistence(timeout: 5))

        presentationEntry.tap()
        XCTAssertTrue(playerInterface.waitForExistence(timeout: 5))
    }

    @MainActor
    func testCustomPiPContinuesAfterPlayerRouteIsRemoved() throws {
        let app = XCUIApplication()
        app.launch()

        app.buttons["demo.presentation-avkit-pip"].tap()
        XCTAssertTrue(
            app.staticTexts["presentation-player-interface-ready"]
                .waitForExistence(timeout: 5)
        )

        let rendererPicker = app.segmentedControls["presentation-renderer-picker"]
        rendererPicker.buttons["Custom"].tap()

        if app.staticTexts["presentation-pip-unsupported"].waitForExistence(timeout: 2) {
            throw XCTSkip("Custom PiP is not supported on this device.")
        }

        let startPiP = app.buttons["presentation-start-pip"]
        let startPredicate = NSPredicate(format: "isEnabled == true")
        expectation(for: startPredicate, evaluatedWith: startPiP)
        waitForExpectations(timeout: 20)
        startPiP.tap()

        let pipStatus = app.descendants(matching: .any)
            .matching(identifier: "presentation-pip-state")
            .firstMatch
        let activePredicate = NSPredicate(format: "label CONTAINS %@", "Yes")
        expectation(for: activePredicate, evaluatedWith: pipStatus)
        waitForExpectations(timeout: 10)

        app.navigationBars.buttons["StreamKit"].tap()
        XCTAssertTrue(app.buttons["demo.presentation-avkit-pip"].waitForExistence(timeout: 5))

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Custom PiP after player route removal"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let stopPiP = app.buttons["demo.stop-active-pip"]
        XCTAssertTrue(stopPiP.waitForExistence(timeout: 5))
        stopPiP.tap()
        XCTAssertFalse(stopPiP.waitForExistence(timeout: 10))
    }

    @MainActor
    func testStandalonePlayerCanEnterAndExitFullscreen() throws {
        let app = XCUIApplication()
        app.launch()

        tapMenuEntry("demo.standalone-player", in: app)

        let enterFullscreen = app.buttons["player.enter-fullscreen"]
        XCTAssertTrue(enterFullscreen.waitForExistence(timeout: 5))
        enterFullscreen.tap()

        let exitFullscreen = app.buttons["player.exit-fullscreen"]
        XCTAssertTrue(exitFullscreen.waitForExistence(timeout: 5))
        exitFullscreen.tap()

        XCTAssertTrue(app.navigationBars["Custom player"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testManagedPlayerCanEnterAndExitFullscreen() throws {
        let app = XCUIApplication()
        app.launch()

        tapMenuEntry("demo.managed-player", in: app)
        XCTAssertTrue(app.navigationBars["Managed Player"].waitForExistence(timeout: 5))

        let playerSurface = app.otherElements["Video"]
        XCTAssertTrue(playerSurface.waitForExistence(timeout: 5), app.debugDescription)
        playerSurface.tap()

        let enterFullscreenButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[cd] 'full' OR label CONTAINS[cd] 'screen'")
        ).firstMatch
        XCTAssertTrue(enterFullscreenButton.waitForExistence(timeout: 10), app.debugDescription)
        enterFullscreenButton.tap()

        let fullscreenSurface = app.otherElements["Video"]
        XCTAssertTrue(fullscreenSurface.waitForExistence(timeout: 10), app.debugDescription)
        fullscreenSurface.tap()
        let transportButton = app.buttons["Play/Pause"]
        XCTAssertTrue(transportButton.waitForExistence(timeout: 10), app.debugDescription)
        if transportButton.label == "Play" {
            transportButton.tap()
        }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20), app.debugDescription)

        let fullscreenScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        fullscreenScreenshot.name = "Managed AVKit fullscreen during playback"
        fullscreenScreenshot.lifetime = .keepAlways
        add(fullscreenScreenshot)

        fullscreenSurface.tap()
        let exitFullscreenButton = app.buttons["Close"]
        XCTAssertTrue(exitFullscreenButton.waitForExistence(timeout: 10), app.debugDescription)

        exitFullscreenButton.tap()

        XCTAssertTrue(app.navigationBars["Managed Player"].waitForExistence(timeout: 10))

        app.buttons["managed.back-to-menu"].tap()
        XCTAssertTrue(app.buttons["demo.managed-player"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testManagedPlayerCanBeReopenedAfterLeavingItsRoute() throws {
        let app = XCUIApplication()
        app.launch()

        let managedPlayerEntry = app.buttons["demo.managed-player"]
        XCTAssertTrue(managedPlayerEntry.waitForExistence(timeout: 5))
        managedPlayerEntry.tap()

        XCTAssertTrue(app.navigationBars["Managed Player"].waitForExistence(timeout: 5))
        let playerSurface = app.otherElements["Video"]
        XCTAssertTrue(playerSurface.waitForExistence(timeout: 10), app.debugDescription)
        playerSurface.tap()
        let transportButton = app.buttons["Play/Pause"]
        XCTAssertTrue(transportButton.waitForExistence(timeout: 10), app.debugDescription)
        if transportButton.label == "Play" {
            transportButton.tap()
        }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20), app.debugDescription)

        app.buttons["managed.back-to-menu"].tap()
        XCTAssertTrue(managedPlayerEntry.waitForExistence(timeout: 10))

        let readyToReopen = NSPredicate(format: "isEnabled == true")
        expectation(for: readyToReopen, evaluatedWith: managedPlayerEntry)
        waitForExpectations(timeout: 10)
        managedPlayerEntry.tap()

        XCTAssertTrue(app.navigationBars["Managed Player"].waitForExistence(timeout: 10))
        let reopenedPlayerSurface = app.otherElements["Video"]
        XCTAssertTrue(reopenedPlayerSurface.waitForExistence(timeout: 10), app.debugDescription)
        reopenedPlayerSurface.tap()
        let reopenedTransportButton = app.buttons["Play/Pause"]
        XCTAssertTrue(reopenedTransportButton.waitForExistence(timeout: 10), app.debugDescription)
        if reopenedTransportButton.label == "Play" {
            reopenedTransportButton.tap()
        }
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 20), app.debugDescription)

        app.buttons["managed.back-to-menu"].tap()
        XCTAssertTrue(managedPlayerEntry.waitForExistence(timeout: 10))
    }

    @MainActor
    func testLiveDVRDemoStartsWithPublicLiveSample() throws {
        let app = XCUIApplication()
        app.launch()

        tapMenuEntry("demo.live-dvr", in: app)

        let liveURLField = app.textFields["Live HLS manifest URL"]
        XCTAssertTrue(liveURLField.waitForExistence(timeout: 5))
        XCTAssertEqual(
            liveURLField.value as? String,
            "https://rt-fra.rttv.com/live/rtfrance/playlist.m3u8"
        )
        XCTAssertTrue(app.buttons["liveDVRLoadStream"].isEnabled)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }

    @MainActor
    private func tapMenuEntry(_ identifier: String, in app: XCUIApplication) {
        let entry = app.buttons[identifier]
        for _ in 0..<5 {
            if entry.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(entry.isHittable, "Expected menu entry \(identifier) to be visible after scrolling")
        entry.tap()
    }
}
