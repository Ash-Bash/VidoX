import Foundation
import AVFoundation

/// Configures the shared audio session so library playback has sound
/// (including when the hardware silent switch is on).
enum PlaybackAudioSession {
    static func activateForPlayback() {
        #if os(iOS) || os(tvOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            // Playback can still proceed; audio may remain silent if activation fails.
        }
        #endif
    }
}
