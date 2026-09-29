import Foundation
import Combine

#if canImport(MusicKit)
import MusicKit
#endif
#if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
import ShazamKit
import AVFoundation
#endif

@MainActor
final class MusicExperimentService: ObservableObject {
    @Published private(set) var output = "MusicKit authorization is ready."

    func requestAuthorization() {
        #if canImport(MusicKit)
        Task {
            let status = await MusicAuthorization.request()
            PermissionCenter.shared.invalidate()
            output = switch status {
            case .authorized: "MusicKit authorized. Catalog and library requests may now be attempted."
            case .denied: "MusicKit authorization denied."
            case .restricted: "MusicKit authorization restricted on this device or account."
            case .notDetermined: "MusicKit authorization remains undetermined."
            @unknown default: "MusicKit returned an unknown authorization state."
            }
        }
        #else
        output = "MusicKit is not supported on this platform."
        #endif
    }
}

struct ShazamMatchedItem: Identifiable {
    let id = UUID()
    let title: String
    let artist: String?
    let subtitle: String?
    let genres: [String]
    let appleMusicURL: URL?
    let webURL: URL?
    let artworkURL: URL?
    let isrc: String?
    let explicitContent: Bool
    let matchOffset: TimeInterval
    let confidence: Float
}

/// Records from the microphone with `SHManagedSession` and matches against the Shazam catalog.
@MainActor
final class ShazamExperimentService: ObservableObject {
    @Published private(set) var output = "ShazamKit is ready. Play music near the microphone, then start listening."
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var isListening = false
    @Published private(set) var matches: [ShazamMatchedItem] = []
    #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private var session: SHManagedSession?
    #endif

    func start() {
        #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isListening else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            status = .permissionRequired
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.start() } else { self?.status = .permissionDenied; self?.output = "Microphone permission was denied. Allow it in Settings so ShazamKit can listen." }
                }
            }
            return
        }
        guard AVCaptureDevice.default(for: .audio) != nil else { status = .hardwareUnsupported; output = "No microphone is available on this device."; return }
        let session = SHManagedSession()
        self.session = session
        matches = []
        isListening = true
        status = .available
        output = "Listening… ShazamKit records from the microphone and matches the signature against the Shazam catalog."
        Task { [weak self] in
            let result = await session.result()
            self?.finish(result, from: session)
        }
        #else
        status = .platformUnsupported
        output = "ShazamKit microphone matching is not available on this platform."
        #endif
    }

    func stop() {
        #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        session?.cancel()
        session = nil
        #endif
        guard isListening else { return }
        isListening = false
        output = "Listening cancelled before ShazamKit returned a result."
    }

    #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func finish(_ result: SHSession.Result, from finished: SHManagedSession) {
        // A cancelled or replaced session may still deliver a result; only the current one counts.
        guard finished === session else { return }
        session = nil
        isListening = false
        switch result {
        case .match(let match):
            matches = match.mediaItems.map(ShazamMatchedItem.init)
            status = .available
            let first = matches.first.map { [$0.title, $0.artist].compactMap { $0 }.joined(separator: " — ") } ?? "Unknown item"
            output = "Match found: \(first)\nMedia items in match: \(matches.count)"
        case .noMatch:
            status = .available
            output = "No match. ShazamKit generated a signature, but the Shazam catalog has no song for it. Play music louder or closer to the microphone and try again."
        case .error(let error, _):
            status = .unavailable
            output = Self.describe(error)
        }
    }

    private static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        var text = "ShazamKit error: \(error.localizedDescription)\nDomain: \(nsError.domain) · Code: \(nsError.code)"
        guard nsError.domain == SHErrorDomain else { return text }
        let hint: String? = switch SHError.Code(rawValue: nsError.code) {
        case .matchAttemptFailed?: "The Shazam catalog could not be queried. Check the network connection and that ShazamKit is enabled for this App ID (Certificates, Identifiers & Profiles › App Services)."
        case .signatureInvalid?: "No usable signature could be generated; the microphone input was probably silent."
        case .signatureDurationInvalid?: "The recording was too short or too long for a catalog match."
        case .internalError?: "ShazamKit reported an internal framework error."
        default: nil
        }
        if let hint { text += "\n\(hint)" }
        return text
    }
    #endif
}

#if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
private extension ShazamMatchedItem {
    init(_ item: SHMatchedMediaItem) {
        self.init(title: item.title ?? "Untitled", artist: item.artist, subtitle: item.subtitle, genres: item.genres,
                  appleMusicURL: item.appleMusicURL, webURL: item.webURL, artworkURL: item.artworkURL, isrc: item.isrc,
                  explicitContent: item.explicitContent, matchOffset: item.matchOffset, confidence: item.confidence)
    }
}
#endif
