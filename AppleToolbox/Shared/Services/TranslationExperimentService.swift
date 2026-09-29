import Foundation
import Combine
#if canImport(Translation) && (os(iOS) || os(macOS))
@preconcurrency import Translation
#endif

struct TranslationLanguage: Identifiable, Hashable {
    let id: String
    let name: String
    let language: Locale.Language
}

@MainActor
final class TranslationExperimentService: ObservableObject {
    /// Picker tag for "detect the source language from the text".
    static let detectSourceID = ""

    @Published private(set) var languages: [TranslationLanguage] = []
    @Published var sourceID = TranslationExperimentService.detectSourceID
    @Published var targetID = ""
    @Published var input = "Every experiment in this app calls a real Apple API on this device."
    @Published private(set) var pairStatus = "—"
    @Published private(set) var translation = ""
    @Published private(set) var output = "Loading the languages this system can translate…"
    @Published private(set) var isError = false
    @Published private(set) var isTranslating = false
    #if canImport(Translation) && (os(iOS) || os(macOS))
    /// Drives SwiftUI's `.translationTask`; a new value or `invalidate()` runs the task again.
    @Published private(set) var configuration: TranslationSession.Configuration?
    #endif

    var isSupported: Bool {
        #if canImport(Translation) && (os(iOS) || os(macOS))
        true
        #else
        false
        #endif
    }

    #if canImport(Translation) && (os(iOS) || os(macOS))
    /// LanguageAvailability is not Sendable, so it is created and queried outside the main actor.
    @concurrent nonisolated private static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
    }
    #endif

    func loadLanguages() async {
        #if canImport(Translation) && (os(iOS) || os(macOS))
        guard languages.isEmpty else { return }
        let supported = await Self.supportedLanguages()
        languages = supported.map { language in
            TranslationLanguage(id: language.maximalIdentifier, name: Self.displayName(for: language), language: language)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !languages.isEmpty else { setOutput("The system reports no supported translation languages.", error: true); return }
        let preferred = Locale.current.language.languageCode?.identifier == "en" ? "de" : "en"
        targetID = (languages.first { $0.language.languageCode?.identifier == preferred } ?? languages[0]).id
        setOutput("\(languages.count) languages are supported. Choose a pair and translate.", error: false)
        #else
        setOutput("The Translation framework is only available on iOS, iPadOS and macOS.", error: true)
        #endif
    }

    func refreshStatus() async {
        #if canImport(Translation) && (os(iOS) || os(macOS))
        guard let target = language(for: targetID) else { pairStatus = "Choose a target language."; return }
        let availability = LanguageAvailability()
        let status: LanguageAvailability.Status
        if let source = language(for: sourceID) {
            status = await availability.status(from: source, to: target)
        } else {
            do { status = try await availability.status(for: input, to: target) }
            catch { pairStatus = "Source language not identified: \(error.localizedDescription)"; return }
        }
        pairStatus = switch status {
        case .installed: "Installed · translates on device without a download"
        case .supported: "Supported · language assets are not downloaded yet; the system offers the download when you translate"
        case .unsupported: "Unsupported · this language pair cannot be translated"
        @unknown default: "\(status)"
        }
        #endif
    }

    /// Asks `.translationTask` for a session; resetting an unchanged configuration re-runs it.
    func requestTranslation() {
        #if canImport(Translation) && (os(iOS) || os(macOS))
        guard !isTranslating, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let source = language(for: sourceID)
        let target = language(for: targetID)
        if configuration != nil, configuration?.source == source, configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: source, target: target)
        }
        #endif
    }

    #if canImport(Translation) && (os(iOS) || os(macOS))
    struct Outcome: Sendable {
        let text: String
        let source: Locale.Language
        let target: Locale.Language
    }

    /// TranslationSession is not Sendable, so it never leaves the translationTask closure; only the result
    /// is handed to the main actor.
    nonisolated static func translate(_ text: String, in session: TranslationSession) async throws -> Outcome {
        let response = try await session.translate(text)
        return Outcome(text: response.targetText, source: response.sourceLanguage, target: response.targetLanguage)
    }

    private var translationStarted = ContinuousClock.now

    /// Returns the text to translate, or nil when there is nothing to do.
    func beginTranslation() -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        isTranslating = true
        translation = ""
        setOutput("Translating…", error: false)
        translationStarted = .now
        return text
    }

    func finishTranslation(_ result: Result<Outcome, Error>) async {
        switch result {
        case .success(let outcome):
            translation = outcome.text
            let elapsed = (ContinuousClock.now - translationStarted).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
            setOutput("Translated \(Self.displayName(for: outcome.source)) → \(Self.displayName(for: outcome.target)) in \(elapsed) with a TranslationSession.", error: false)
        case .failure(let error):
            let localized = error as? LocalizedError
            let lines = ["Translation failed: \(localized?.errorDescription ?? error.localizedDescription)", localized?.failureReason]
            setOutput(lines.compactMap { $0 }.joined(separator: "\n"), error: true)
        }
        isTranslating = false
        await refreshStatus()
    }
    #endif

    private func language(for id: String) -> Locale.Language? {
        languages.first { $0.id == id }?.language
    }

    private func setOutput(_ message: String, error: Bool) {
        output = message
        isError = error
    }

    private static func displayName(for language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier) ?? language.minimalIdentifier
    }
}
