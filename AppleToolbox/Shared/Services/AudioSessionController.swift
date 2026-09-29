import Foundation
#if os(iOS) || os(tvOS)
import AVFAudio
#endif

/// Prepares the shared audio session for audio experiments. Only iOS and tvOS have an app-level
/// AVAudioSession; on macOS the engine records and plays directly.
///
/// `setCategory`/`setActive` and AVAudioEngine `start()`/`stop()` can block for tens to hundreds of
/// milliseconds, so all of it runs on one serial background queue. The single queue keeps the order the
/// main actor asked for: an activation waits for a pending deactivation, and an engine start runs after
/// the activation it depends on.
nonisolated enum AudioSessionController {
    private static let queue = DispatchQueue(label: "AppleToolbox.AudioSessionController", qos: .userInitiated)

    static func activateForRecording() async throws {
        try await perform {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    /// Output plus unprocessed microphone input (measurement mode), routed to the speaker instead of the receiver.
    static func activateForPlayAndRecord() async throws {
        try await perform {
            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    /// Non-mixable playback: required to become the Now Playing app and to keep playing with the Ring/Silent switch on silent.
    static func activateForPlayback(video: Bool = false) async throws {
        try await perform {
            #if os(iOS) || os(tvOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: video ? .moviePlayback : .default)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    /// Enqueued without waiting: later activations and engine work still run after it.
    static func deactivate() {
        enqueue {
            #if os(iOS) || os(tvOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            #endif
        }
    }

    /// Runs blocking audio work (engine start, tap install) on the audio queue and waits for it.
    /// The closure is nonisolated: capture non-Sendable objects through `nonisolated(unsafe)` locals and touch them only here.
    static func perform<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// Fire-and-forget audio work (engine stop, tap removal), ordered before any later `perform`.
    static func enqueue(_ work: @escaping @Sendable () -> Void) {
        queue.async(execute: work)
    }
}
