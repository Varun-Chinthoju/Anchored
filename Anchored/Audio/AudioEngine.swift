import Foundation
import AVFoundation

/// An enumeration of the available sound effects in Anchored.
public enum AnchoredSound: String, CaseIterable {
    case tick
    case pop
    case chime
    
    var fileName: String {
        return self.rawValue
    }
    
    var fileExtension: String {
        return "aiff"
    }
}

/// A class responsible for preloading and playing short focus sound effects.
public final class AudioEngine {
    /// The shared singleton instance of the AudioEngine.
    public static let shared = AudioEngine()
    
    private var players: [AnchoredSound: AVAudioPlayer] = [:]
    private let queue = DispatchQueue(label: "com.varun.Anchored.AudioEngine", qos: .userInteractive)
    
    /// Initializes the AudioEngine and preloads the sound files.
    private init() {
        preloadSounds()
    }
    
    /// Preloads all available sound files into AVAudioPlayer instances.
    private func preloadSounds() {
        // We use Bundle(for: AudioEngine.self) to ensure we can locate the resources
        // whether running in the main application or in a unit test environment.
        let bundle = Bundle(for: AudioEngine.self)
        
        for sound in AnchoredSound.allCases {
            guard let url = bundle.url(forResource: sound.fileName, withExtension: sound.fileExtension) else {
                print("AudioEngine Warning: Could not find resource file for \(sound.fileName).\(sound.fileExtension) in bundle \(bundle.bundlePath)")
                continue
            }
            
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.prepareToPlay()
                players[sound] = player
            } catch {
                print("AudioEngine Error: Failed to initialize AVAudioPlayer for \(sound.fileName).\(sound.fileExtension): \(error.localizedDescription)")
            }
        }
    }
    
    /// Plays the specified sound effect.
    /// Playback is non-blocking (fire-and-forget).
    /// If the sound is already playing, it will be restarted from the beginning.
    ///
    /// - Parameter sound: The AnchoredSound effect to play.
    public func play(_ sound: AnchoredSound) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard let player = self.players[sound] else {
                print("AudioEngine Error: Sound '\(sound.rawValue)' is not preloaded.")
                return
            }
            
            if player.isPlaying {
                player.stop()
                player.currentTime = 0
            }
            player.play()
        }
    }
    
    /// Checks if a specific sound effect is successfully preloaded.
    ///
    /// - Parameter sound: The sound effect to check.
    /// - Returns: True if the sound player is initialized, false otherwise.
    public func isSoundPreloaded(_ sound: AnchoredSound) -> Bool {
        return queue.sync {
            return players[sound] != nil
        }
    }
}
