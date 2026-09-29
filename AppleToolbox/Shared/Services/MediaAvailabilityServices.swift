import Foundation
import Combine

#if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
import ShazamKit
import AVFoundation
import os
#endif

/// How long the microphone is captured for a custom-catalog reference or query signature.
enum ShazamCaptureLength: Int, CaseIterable, Identifiable {
    case five = 5, ten = 10, fifteen = 15, thirty = 30
    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String { "\(rawValue) s" }

    /// Query signatures must lie within the catalog's allowed range; reference signatures may be any length.
    static func queryDuration(requested: TimeInterval, minimum: TimeInterval, maximum: TimeInterval) -> TimeInterval {
        guard maximum >= minimum, minimum > 0 else { return requested }
        return min(max(requested, minimum), maximum)
    }
}

enum ShazamCaptureMode: Equatable {
    case reference, query
}

/// One reference signature added to the in-app `SHCustomCatalog`.
struct ShazamCatalogEntry: Identifiable {
    let id = UUID()
    let title: String
    let artist: String?
    let duration: TimeInterval
    let added: Date
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
    // Custom catalog (SHSignatureGenerator → SHCustomCatalog → SHSession(catalog:))
    @Published var referenceTitle = ""
    @Published var referenceArtist = ""
    @Published var captureLength = ShazamCaptureLength.ten
    @Published private(set) var captureMode: ShazamCaptureMode?
    @Published private(set) var captureProgress = 0.0
    @Published private(set) var catalogEntries: [ShazamCatalogEntry] = []
    @Published private(set) var catalogFileURL: URL?
    @Published private(set) var catalogOutput = "Record a reference signature from the microphone to build a custom catalog, then record a query and match it against the catalog. Nothing is sent to the Shazam service."
    @Published private(set) var catalogIsError = false
    @Published private(set) var catalogMatches: [ShazamMatchedItem] = []
    #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private var session: SHManagedSession?
    private let customCatalog = SHCustomCatalog()
    private var captureEngine: AVAudioEngine?
    private var generator: SHSignatureGenerator?
    private var appendFailure: OSAllocatedUnfairLock<String?>?
    private var captureTask: Task<Void, Never>?
    #endif

    var isCapturing: Bool { captureMode != nil }

    func start() {
        #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard !isListening, captureMode == nil else { return }
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
        cancelCapture()
        guard isListening else { return }
        isListening = false
        output = "Listening cancelled before ShazamKit returned a result."
    }


    // MARK: Custom catalog

    func recordReference() { beginCapture(.reference) }
    func recordQuery() { beginCapture(.query) }

    func cancelCapture() {
        #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard captureMode != nil else { return }
        captureTask?.cancel()
        captureTask = nil
        tearDownCapture()
        catalogOutput = "Signature capture cancelled."
        catalogIsError = false
        #endif
    }

    private func beginCapture(_ mode: ShazamCaptureMode) {
        #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
        guard captureMode == nil, !isListening else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            AVCaptureDevice.requestAccess(for: .audio) { @Sendable [weak self] granted in
                Task { @MainActor in
                    PermissionCenter.shared.invalidate()
                    if granted { self?.beginCapture(mode) } else { self?.catalogFailed("Microphone permission was denied. Allow it in Settings so SHSignatureGenerator can hear the audio.") }
                }
            }
            return
        }
        if mode == .query, catalogEntries.isEmpty {
            catalogFailed("The custom catalog is empty. Record a reference signature first; SHSession(catalog:) can only match what the catalog contains.")
            return
        }
        let duration = mode == .reference ? captureLength.seconds
            : ShazamCaptureLength.queryDuration(requested: captureLength.seconds, minimum: customCatalog.minimumQuerySignatureDuration, maximum: customCatalog.maximumQuerySignatureDuration)
        do {
            try AudioSessionController.activateForRecording()
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                AudioSessionController.deactivate()
                catalogFailed("The microphone input reports no usable format (sample rate \(format.sampleRate) Hz, \(format.channelCount) channels). No microphone is available.")
                return
            }
            let generator = SHSignatureGenerator()
            let failure = OSAllocatedUnfairLock<String?>(initialState: nil)
            // SHSignatureGenerator is not Sendable; only this tap appends to it until the engine stops, then the main actor reads it.
            nonisolated(unsafe) let tapGenerator = generator
            input.installTap(onBus: 0, bufferSize: 4_096, format: format) { @Sendable buffer, time in
                do { try tapGenerator.append(buffer, at: time) } catch {
                    let message = error.localizedDescription
                    failure.withLock { if $0 == nil { $0 = message } }
                }
            }
            engine.prepare()
            try engine.start()
            captureEngine = engine
            self.generator = generator
            appendFailure = failure
            captureMode = mode
            captureProgress = 0
            catalogMatches = []
            catalogIsError = false
            catalogOutput = mode == .reference
                ? "Recording a \(Int(duration)) s reference signature at \(Int(format.sampleRate)) Hz · \(format.channelCount) ch…"
                : "Recording a \(duration.formatted(.number.precision(.fractionLength(0...1)))) s query signature (catalog allows \(customCatalog.minimumQuerySignatureDuration.formatted(.number.precision(.fractionLength(0...1))))–\(customCatalog.maximumQuerySignatureDuration.formatted(.number.precision(.fractionLength(0...1)))) s)…"
            captureTask = Task { [weak self] in
                let start = Date.now
                while !Task.isCancelled {
                    let elapsed = Date.now.timeIntervalSince(start)
                    self?.captureProgress = min(elapsed / duration, 1)
                    if elapsed >= duration { break }
                    try? await Task.sleep(for: .milliseconds(200))
                }
                guard !Task.isCancelled else { return }
                await self?.finishCapture(mode)
            }
        } catch {
            tearDownCapture()
            catalogFailed("The microphone could not start: \(error.localizedDescription)")
        }
        #else
        catalogFailed("SHSignatureGenerator from the microphone is only available on iPhone, iPad and Mac.")
        #endif
    }

    private func catalogFailed(_ message: String) {
        catalogOutput = message
        catalogIsError = true
    }

    #if canImport(ShazamKit) && canImport(AVFoundation) && (os(iOS) || os(macOS))
    private func tearDownCapture() {
        captureEngine?.inputNode.removeTap(onBus: 0)
        captureEngine?.stop()
        captureEngine = nil
        generator = nil
        appendFailure = nil
        captureMode = nil
        captureProgress = 0
        AudioSessionController.deactivate()
    }

    private func finishCapture(_ mode: ShazamCaptureMode) async {
        captureTask = nil
        captureEngine?.inputNode.removeTap(onBus: 0)
        captureEngine?.stop()
        let failure = appendFailure?.withLock { $0 }
        guard let generator else { tearDownCapture(); return }
        let signature = generator.signature()
        tearDownCapture()
        if let failure {
            catalogFailed("SHSignatureGenerator rejected the microphone audio: \(failure)\nShazamKit accepts PCM at 16, 32, 44.1 or 48 kHz.")
            return
        }
        switch mode {
        case .reference: addReference(signature)
        case .query: await match(signature)
        }
    }

    private func addReference(_ signature: SHSignature) {
        let title = referenceTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = referenceArtist.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "Reference \(catalogEntries.count + 1)" : title
        var properties: [SHMediaItemProperty: Any] = [.title: resolvedTitle, .subtitle: "Custom catalog · Apple Toolbox"]
        if !artist.isEmpty { properties[.artist] = artist }
        let item = SHMediaItem(properties: properties)
        do {
            try customCatalog.addReferenceSignature(signature, representing: [item])
            catalogEntries.append(ShazamCatalogEntry(title: resolvedTitle, artist: artist.isEmpty ? nil : artist, duration: signature.duration, added: .now))
            catalogIsError = false
            catalogOutput = "Added \"\(resolvedTitle)\" (\(signature.duration.formatted(.number.precision(.fractionLength(1)))) s, \(signature.dataRepresentation.count.formatted()) bytes) to the custom catalog. Entries: \(catalogEntries.count)."
            writeCatalogFile()
        } catch {
            catalogFailed(Self.describe(error))
        }
    }

    private func writeCatalogFile() {
        let url = URL.temporaryDirectory.appending(path: "AppleToolbox.shazamcatalog")
        do {
            try? FileManager.default.removeItem(at: url)
            try customCatalog.dataRepresentation.write(to: url, options: .atomic)
            catalogFileURL = url
        } catch {
            catalogFileURL = nil
            catalogOutput += "\nThe catalog could not be written to a file: \(error.localizedDescription)"
        }
    }

    private func match(_ signature: SHSignature) async {
        // SHSession is not Sendable, but this session is used only for this one awaited match and never touched again here.
        nonisolated(unsafe) let session = SHSession(catalog: customCatalog)
        catalogOutput = "Matching a \(signature.duration.formatted(.number.precision(.fractionLength(1)))) s query signature against \(catalogEntries.count) reference signature(s)…"
        let result = await session.result(from: signature)
        switch result {
        case .match(let match):
            catalogMatches = match.mediaItems.map(ShazamMatchedItem.init)
            catalogIsError = false
            catalogOutput = "Custom catalog match: \(catalogMatches.first?.title ?? "Unknown item")\nMedia items in match: \(catalogMatches.count)"
        case .noMatch:
            catalogIsError = false
            catalogOutput = "No match in the custom catalog. The query signature did not correspond to any reference signature. Play the same audio as the reference, closer to the microphone."
        case .error(let error, _):
            catalogFailed(Self.describe(error))
        }
    }
    #endif

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
