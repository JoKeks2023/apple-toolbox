import Foundation
#if os(iOS) || os(tvOS)
import AVFAudio
#endif

/// Prepares the shared audio session for audio experiments. Only iOS and tvOS have an app-level
/// AVAudioSession; on macOS the engine records and plays directly.
enum AudioSessionController {
    static func activateForRecording() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Output plus unprocessed microphone input (measurement mode), routed to the speaker instead of the receiver.
    static func activateForPlayAndRecord() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// Non-mixable playback: required to become the Now Playing app and to keep playing with the Ring/Silent switch on silent.
    static func activateForPlayback(video: Bool = false) throws {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: video ? .moviePlayback : .default)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }

    static func deactivate() {
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
