import XCTest
@testable import Anchored

final class AudioEngineTests: XCTestCase {
    
    func testAudioEnginePreloadsSounds() {
        let audioEngine = AudioEngine.shared
        
        // Check that all sounds are preloaded successfully.
        for sound in AnchoredSound.allCases {
            XCTAssertTrue(audioEngine.isSoundPreloaded(sound), "Sound '\(sound.rawValue)' should be preloaded.")
        }
    }
    
    func testAudioEnginePlaySoundDoesNotCrash() {
        let audioEngine = AudioEngine.shared
        
        // Since play is asynchronous and fire-and-forget, we test that invoking play
        // for each sound runs without throwing or crashing.
        for sound in AnchoredSound.allCases {
            audioEngine.play(sound)
        }
        
        // Wait briefly to ensure the play queue finishes processing
        let expectation = XCTestExpectation(description: "Playback operations complete")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 0.5)
    }
}
