import XCTest
@testable import StreamKit

final class StreamKitTests: XCTestCase {
    func testPlaybackPhaseInitialization() {
        // Test that all phases can be instantiated
        XCTAssertEqual(PlaybackPhase.idle, PlaybackPhase.idle)
        XCTAssertEqual(PlaybackPhase.loading, PlaybackPhase.loading)
        XCTAssertEqual(PlaybackPhase.ready, PlaybackPhase.ready)
        XCTAssertEqual(PlaybackPhase.playing, PlaybackPhase.playing)
        XCTAssertEqual(PlaybackPhase.paused, PlaybackPhase.paused)
        XCTAssertEqual(PlaybackPhase.waiting, PlaybackPhase.waiting)
        XCTAssertEqual(PlaybackPhase.ended, PlaybackPhase.ended)
        XCTAssertEqual(PlaybackPhase.failed, PlaybackPhase.failed)
        
        // Test that different phases are not equal
        XCTAssertNotEqual(PlaybackPhase.playing, PlaybackPhase.paused)
        XCTAssertNotEqual(PlaybackPhase.ready, PlaybackPhase.waiting)
    }
    
    func testPlaybackIntentInitialization() {
        // Test that both intents can be instantiated
        XCTAssertEqual(PlaybackIntent.play, PlaybackIntent.play)
        XCTAssertEqual(PlaybackIntent.pause, PlaybackIntent.pause)
        
        // Test that intents are not equal to each other
        XCTAssertNotEqual(PlaybackIntent.play, PlaybackIntent.pause)
    }
    
    func testPlaybackPhaseAndIntentAreIndependent() {
        // Verify that phase and intent are separate types that can be used together
        let intent = PlaybackIntent.play
        let phase = PlaybackPhase.ready
        
        // This test just verifies they can coexist in a test - no assertion needed
        // The fact that we can create both instances shows they're independent
        _ = intent
        _ = phase
    }
}
