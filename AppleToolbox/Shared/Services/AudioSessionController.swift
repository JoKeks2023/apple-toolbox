import Foundation
#if os(iOS)
import AVFAudio
#endif

/// Prepares the shared audio session for microphone experiments. Only iOS has an app-level
/// AVAudioSession that must allow input; on macOS the engine can record directly.
enum AudioSessionController {
    static func activateForRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    static func deactivate() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
