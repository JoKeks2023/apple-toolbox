import Foundation
import Combine
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

// MARK: - Choices

nonisolated enum NLAnalysisMode: String, CaseIterable, Identifiable, Sendable {
    case language = "Language identification"
    case tokens = "Tokenization"
    case tags = "Lexical classes & entities"
    case sentiment = "Sentiment"
    case lemmas = "Lemmas"
    case embeddings = "Embeddings"
    var id: String { rawValue }
}

nonisolated enum NLTokenUnitOption: String, CaseIterable, Identifiable, Sendable {
    case word = "Word", sentence = "Sentence", paragraph = "Paragraph", document = "Document"
    var id: String { rawValue }
}

/// NLTagger scores sentiment per sentence or paragraph.
nonisolated enum NLSentimentUnitOption: String, CaseIterable, Identifiable, Sendable {
    case sentence = "Sentence", paragraph = "Paragraph"
    var id: String { rawValue }
    var tokenUnit: NLTokenUnitOption { self == .sentence ? .sentence : .paragraph }
}

nonisolated enum NLTagSchemeOption: String, CaseIterable, Identifiable, Sendable {
    case lexicalClass = "Lexical class"
    case nameType = "Named entities"
    case nameTypeOrLexicalClass = "Entities + lexical class"
    case tokenType = "Token type"
    case language = "Language per word"
    case script = "Script per word"
    var id: String { rawValue }
    /// Named-entity schemes join multi-word names ("Tim Cook") into one token.
    var joinsNames: Bool { self == .nameType || self == .nameTypeOrLexicalClass }
}

nonisolated enum NLEmbeddingKind: String, CaseIterable, Identifiable, Sendable {
    case word = "Word embedding", sentence = "Sentence embedding"
    var id: String { rawValue }
}

// MARK: - Results

nonisolated struct NLLanguageGuess: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let probability: Double
    var id: String { code }
}

nonisolated struct NLTokenInfo: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    /// Character offset and length in the analyzed string.
    let offset: Int
    let length: Int
    let attributes: [String]
}

nonisolated struct NLTaggedToken: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let tag: String
    var tone: NLTagTone { NLTagTone(tag: tag) }
}

nonisolated struct NLSentimentScore: Identifiable, Equatable, Sendable {
    let id: Int
    let text: String
    let score: Double
}

nonisolated struct NLLemma: Identifiable, Equatable, Sendable {
    let id: Int
    let word: String
    let lemma: String?
}

nonisolated struct NLEmbeddingSupport: Identifiable, Equatable, Sendable {
    let code: String
    let name: String
    let wordRevisions: [Int]
    let sentenceRevisions: [Int]
    var id: String { code }

    var summary: String {
        switch (wordRevisions.isEmpty, sentenceRevisions.isEmpty) {
        case (false, false): "word + sentence"
        case (false, true): "word only"
        case (true, false): "sentence only"
        case (true, true): "none"
        }
    }
}

nonisolated struct NLNeighbor: Identifiable, Equatable, Sendable {
    let term: String
    let distance: Double
    var id: String { term }
}

nonisolated struct NLFact: Identifiable, Equatable, Sendable {
    let title: String
    let value: String
    var id: String { title }
}

nonisolated struct NLEmbeddingReport: Equatable, Sendable {
    let facts: [NLFact]
    let neighbors: [NLNeighbor]
    let distance: Double?
    let vectorPreview: [Double]
    let notes: [String]
}

// MARK: - Pure helpers

/// Groups NLTagger tags into a handful of tones for the colored token list.
nonisolated enum NLTagTone: String, CaseIterable, Sendable {
    case noun, verb, adjective, adverb, pronoun, function, number, person, place, organization, punctuation, whitespace, word, other

    /// `tag` is an NLTag raw value, e.g. "Noun" or "PersonalName".
    init(tag: String) {
        switch tag {
        case "Noun": self = .noun
        case "Verb": self = .verb
        case "Adjective": self = .adjective
        case "Adverb": self = .adverb
        case "Pronoun": self = .pronoun
        case "Determiner", "Particle", "Preposition", "Conjunction", "Interjection", "Classifier", "Idiom": self = .function
        case "Number": self = .number
        case "PersonalName": self = .person
        case "PlaceName": self = .place
        case "OrganizationName": self = .organization
        case "Punctuation", "SentenceTerminator", "OpenQuote", "CloseQuote", "OpenParenthesis", "CloseParenthesis", "WordJoiner", "Dash", "OtherPunctuation": self = .punctuation
        case "Whitespace", "ParagraphBreak", "OtherWhitespace": self = .whitespace
        case "Word": self = .word
        default: self = .other
        }
    }

    var isEntity: Bool { self == .person || self == .place || self == .organization }

    var title: String {
        switch self {
        case .function: "Function word"
        case .person: "Person"
        case .place: "Place"
        case .organization: "Organization"
        default: rawValue.capitalized
        }
    }
}

nonisolated enum NaturalLanguageFormat {
    /// NLTagger's sentimentScore lies in −1…1; small magnitudes read as neutral.
    static func sentimentLabel(for score: Double) -> String {
        if score >= 0.2 { return "Positive" }
        if score <= -0.2 { return "Negative" }
        return "Neutral"
    }

    /// Maps −1…1 onto 0…1 for a progress bar.
    static func sentimentFraction(for score: Double) -> Double {
        min(max((score + 1) / 2, 0), 1)
    }

    /// Cosine distance (0 = identical, 2 = opposite) as cosine similarity.
    static func cosineSimilarity(fromDistance distance: Double) -> Double {
        1 - distance
    }

    /// How many named entities of each kind a tagged token list contains, most frequent first.
    static func entityCounts(_ tokens: [NLTaggedToken]) -> [(tone: NLTagTone, count: Int)] {
        let counts = Dictionary(grouping: tokens.map(\.tone).filter(\.isEntity), by: { $0 }).mapValues(\.count)
        return counts.map { (tone: $0.key, count: $0.value) }.sorted { $0.count != $1.count ? $0.count > $1.count : $0.tone.rawValue < $1.tone.rawValue }
    }

    /// Character offset and length of `range` inside `text`.
    static func offsets(of range: Range<String.Index>, in text: String) -> (offset: Int, length: Int) {
        (text.distance(from: text.startIndex, to: range.lowerBound), text.distance(from: range.lowerBound, to: range.upperBound))
    }

    static func languageName(_ code: String) -> String {
        guard code != "und" else { return "Undetermined" }
        return Locale.current.localizedString(forIdentifier: code) ?? code
    }
}

// MARK: - Analysis (off the main actor)

#if canImport(NaturalLanguage)
/// Thin wrappers around NLLanguageRecognizer, NLTokenizer, NLTagger and NLEmbedding. They run on a
/// background task; each call creates its own framework objects, so nothing is shared between threads.
nonisolated enum NaturalLanguageAnalyzer {
    /// Languages checked for bundled embeddings; the framework offers no list of its own.
    static let embeddingCandidates: [NLLanguage] = [
        .english, .german, .french, .spanish, .italian, .portuguese, .dutch, .swedish, .danish, .norwegian, .finnish,
        .polish, .czech, .slovak, .hungarian, .romanian, .croatian, .bulgarian, .ukrainian, .russian, .greek, .turkish,
        .catalan, .arabic, .hebrew, .hindi, .thai, .vietnamese, .indonesian, .malay, .japanese, .korean,
        .simplifiedChinese, .traditionalChinese,
    ]

    static func identify(_ text: String, maximum: Int = 5) -> (dominant: NLLanguageGuess?, hypotheses: [NLLanguageGuess]) {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: maximum)
            .map { NLLanguageGuess(code: $0.key.rawValue, name: NaturalLanguageFormat.languageName($0.key.rawValue), probability: $0.value) }
            .sorted { $0.probability > $1.probability }
        let dominant = recognizer.dominantLanguage.map { language in
            hypotheses.first { $0.code == language.rawValue } ?? NLLanguageGuess(code: language.rawValue, name: NaturalLanguageFormat.languageName(language.rawValue), probability: 1)
        }
        return (dominant, hypotheses)
    }

    static func tokens(_ text: String, unit: NLTokenUnitOption) -> [NLTokenInfo] {
        let tokenizer = NLTokenizer(unit: tokenUnit(unit))
        tokenizer.string = text
        var tokens: [NLTokenInfo] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, attributes in
            let position = NaturalLanguageFormat.offsets(of: range, in: text)
            var flags: [String] = []
            if attributes.contains(.numeric) { flags.append("numeric") }
            if attributes.contains(.symbolic) { flags.append("symbolic") }
            if attributes.contains(.emoji) { flags.append("emoji") }
            tokens.append(NLTokenInfo(id: tokens.count, text: String(text[range]), offset: position.offset, length: position.length, attributes: flags))
            return true
        }
        return tokens
    }

    static func tags(_ text: String, scheme option: NLTagSchemeOption, omitPunctuation: Bool) -> [NLTaggedToken] {
        let scheme = tagScheme(option)
        let tagger = NLTagger(tagSchemes: [scheme])
        tagger.string = text
        var options: NLTagger.Options = [.omitWhitespace, .omitOther]
        if omitPunctuation { options.insert(.omitPunctuation) }
        if option.joinsNames { options.insert(.joinNames) }
        var tokens: [NLTaggedToken] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: scheme, options: options) { tag, range in
            tokens.append(NLTaggedToken(id: tokens.count, text: String(text[range]), tag: tag?.rawValue ?? "—"))
            return true
        }
        return tokens
    }

    /// Tag schemes the tagger supports for words in `code` on this device.
    static func availableSchemes(forLanguage code: String) -> [String] {
        NLTagger.availableTagSchemes(for: .word, language: NLLanguage(rawValue: code)).map(\.rawValue).sorted()
    }

    static func sentiment(_ text: String, unit: NLSentimentUnitOption) -> (overall: Double?, parts: [NLSentimentScore]) {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        var parts: [NLSentimentScore] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: tokenUnit(unit.tokenUnit), scheme: .sentimentScore, options: [.omitWhitespace]) { tag, range in
            let segment = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty, let score = tag.flatMap({ Double($0.rawValue) }) {
                parts.append(NLSentimentScore(id: parts.count, text: segment, score: score))
            }
            return true
        }
        let overall = tagger.tag(at: text.startIndex, unit: .paragraph, scheme: .sentimentScore).0.flatMap { Double($0.rawValue) }
        return (parts.count > 1 ? overall : parts.first?.score ?? overall, parts)
    }

    static func lemmas(_ text: String) -> [NLLemma] {
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        var lemmas: [NLLemma] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lemma, options: [.omitWhitespace, .omitPunctuation, .omitOther]) { tag, range in
            lemmas.append(NLLemma(id: lemmas.count, word: String(text[range]), lemma: tag?.rawValue))
            return true
        }
        return lemmas
    }

    static func embeddingSupport() -> [NLEmbeddingSupport] {
        embeddingCandidates.map { language in
            NLEmbeddingSupport(code: language.rawValue, name: NaturalLanguageFormat.languageName(language.rawValue),
                               wordRevisions: Array(NLEmbedding.supportedRevisions(for: language)),
                               sentenceRevisions: Array(NLEmbedding.supportedSentenceEmbeddingRevisions(for: language)))
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func embeddingReport(kind: NLEmbeddingKind, languageCode: String, first: String, second: String, neighborCount: Int) -> NLEmbeddingReport? {
        let language = NLLanguage(rawValue: languageCode)
        let loaded = switch kind {
        case .word: NLEmbedding.wordEmbedding(for: language)
        case .sentence: NLEmbedding.sentenceEmbedding(for: language)
        }
        guard let embedding = loaded else { return nil }
        var facts = [
            NLFact(title: "Language", value: NaturalLanguageFormat.languageName(embedding.language?.rawValue ?? languageCode)),
            NLFact(title: "Revision", value: "\(embedding.revision)"),
            NLFact(title: "Dimension", value: "\(embedding.dimension)"),
            NLFact(title: "Vocabulary size", value: embedding.vocabularySize.formatted()),
        ]
        var notes: [String] = []
        let a = kind == .word ? first.lowercased() : first
        let b = kind == .word ? second.lowercased() : second
        if kind == .word {
            facts.append(NLFact(title: "“\(a)” in vocabulary", value: embedding.contains(a) ? "yes" : "no"))
            if !b.isEmpty { facts.append(NLFact(title: "“\(b)” in vocabulary", value: embedding.contains(b) ? "yes" : "no")) }
        }
        let vector = a.isEmpty ? nil : embedding.vector(for: a)
        if !a.isEmpty, vector == nil { notes.append("NLEmbedding returned no vector for “\(a)”.") }
        var neighbors: [NLNeighbor] = []
        if kind == .word, !a.isEmpty {
            neighbors = embedding.neighbors(for: a, maximumCount: neighborCount, distanceType: .cosine).map { NLNeighbor(term: $0.0, distance: $0.1) }
            if neighbors.isEmpty { notes.append("No neighbours: “\(a)” is not in the embedding's vocabulary.") }
        } else if kind == .sentence {
            notes.append("Sentence embeddings have no vocabulary, so nearest neighbours only exist for word embeddings. Compare two sentences with the distance instead.")
        }
        var distance: Double?
        if !a.isEmpty, !b.isEmpty {
            // For word embeddings a term outside the vocabulary yields the maximum distance of 2, which would be misleading.
            if kind == .sentence || (embedding.contains(a) && embedding.contains(b)) {
                distance = embedding.distance(between: a, and: b, distanceType: .cosine)
            } else {
                notes.append("Distance skipped: both terms must be in the vocabulary.")
            }
        }
        return NLEmbeddingReport(facts: facts, neighbors: neighbors, distance: distance, vectorPreview: Array((vector ?? []).prefix(8)), notes: notes)
    }

    static func tokenUnit(_ option: NLTokenUnitOption) -> NLTokenUnit {
        switch option {
        case .word: .word
        case .sentence: .sentence
        case .paragraph: .paragraph
        case .document: .document
        }
    }

    static func tagScheme(_ option: NLTagSchemeOption) -> NLTagScheme {
        switch option {
        case .lexicalClass: .lexicalClass
        case .nameType: .nameType
        case .nameTypeOrLexicalClass: .nameTypeOrLexicalClass
        case .tokenType: .tokenType
        case .language: .language
        case .script: .script
        }
    }
}
#endif

// MARK: - Service

@MainActor
final class NaturalLanguageExperimentService: ObservableObject {
    static let neighborCounts = [5, 10, 20]

    @Published var input = "Tim Cook presented the new iPhone at Apple Park in Cupertino. The keynote was fantastic, although the demo crashed twice."
    @Published var mode = NLAnalysisMode.tags
    @Published var tokenUnit = NLTokenUnitOption.word
    @Published var tagScheme = NLTagSchemeOption.nameTypeOrLexicalClass
    @Published var omitPunctuation = true
    @Published var sentimentUnit = NLSentimentUnitOption.sentence
    @Published var embeddingKind = NLEmbeddingKind.word
    @Published var embeddingLanguage = "en"
    @Published var firstTerm = "coffee"
    @Published var secondTerm = "tea"
    @Published var neighborCount = 10

    @Published private(set) var dominantLanguage: NLLanguageGuess?
    @Published private(set) var hypotheses: [NLLanguageGuess] = []
    @Published private(set) var tokens: [NLTokenInfo] = []
    @Published private(set) var taggedTokens: [NLTaggedToken] = []
    @Published private(set) var availableSchemes: [String] = []
    @Published private(set) var overallSentiment: Double?
    @Published private(set) var sentiments: [NLSentimentScore] = []
    @Published private(set) var lemmas: [NLLemma] = []
    @Published private(set) var embeddingSupport: [NLEmbeddingSupport] = []
    @Published private(set) var embeddingReport: NLEmbeddingReport?
    @Published private(set) var output = "On-device language analysis is ready. Choose an analysis and run it."
    @Published private(set) var isError = false
    @Published private(set) var isAnalyzing = false
    private var work: Task<Void, Never>?

    var isSupported: Bool {
        #if canImport(NaturalLanguage)
        true
        #else
        false
        #endif
    }

    /// Whether the selected tag scheme is missing for the detected language, so assets could be requested.
    var selectedSchemeMissing: Bool {
        guard mode == .tags, dominantLanguage != nil, !availableSchemes.isEmpty else { return false }
        #if canImport(NaturalLanguage)
        return !availableSchemes.contains(NaturalLanguageAnalyzer.tagScheme(tagScheme).rawValue)
        #else
        return false
        #endif
    }

    func loadEmbeddingSupport() async {
        #if canImport(NaturalLanguage)
        guard embeddingSupport.isEmpty else { return }
        embeddingSupport = await Self.runDetached { NaturalLanguageAnalyzer.embeddingSupport() }
        #endif
    }

    func analyze() {
        #if canImport(NaturalLanguage)
        work?.cancel()
        let text = input
        let mode = self.mode
        guard mode == .embeddings || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isAnalyzing = true
        let started = ContinuousClock.now
        let unit = tokenUnit, scheme = tagScheme, omit = omitPunctuation, sentimentUnit = self.sentimentUnit
        let kind = embeddingKind, languageCode = embeddingLanguage, neighbors = neighborCount
        let first = firstTerm.trimmingCharacters(in: .whitespacesAndNewlines), second = secondTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        work = Task { [weak self] in
            let language = await Self.runDetached { NaturalLanguageAnalyzer.identify(text) }
            guard !Task.isCancelled, let self else { return }
            self.dominantLanguage = language.dominant
            self.hypotheses = language.hypotheses
            let languageName = language.dominant?.name ?? "undetermined"
            var message: String
            switch mode {
            case .language:
                message = language.dominant.map { "NLLanguageRecognizer: dominant language \($0.name) (\($0.code)), \(language.hypotheses.count) hypotheses." }
                    ?? "NLLanguageRecognizer could not determine a language for this text."
            case .tokens:
                let tokens = await Self.runDetached { NaturalLanguageAnalyzer.tokens(text, unit: unit) }
                self.tokens = tokens
                message = "NLTokenizer (.\(unit.rawValue.lowercased())) found \(tokens.count) token(s) in \(languageName) text."
            case .tags:
                let code = language.dominant?.code
                let result = await Self.runDetached {
                    (NaturalLanguageAnalyzer.tags(text, scheme: scheme, omitPunctuation: omit), code.map(NaturalLanguageAnalyzer.availableSchemes(forLanguage:)) ?? [])
                }
                self.taggedTokens = result.0
                self.availableSchemes = result.1
                let entities = NaturalLanguageFormat.entityCounts(result.0).map { "\($0.tone.title) ×\($0.count)" }.joined(separator: ", ")
                message = "NLTagger (\(scheme.rawValue)) tagged \(result.0.count) token(s)." + (entities.isEmpty ? "" : "\nNamed entities: \(entities).")
                if self.selectedSchemeMissing { message += "\nThis scheme is not available for \(languageName) on this device; request its assets below." }
            case .sentiment:
                let result = await Self.runDetached { NaturalLanguageAnalyzer.sentiment(text, unit: sentimentUnit) }
                self.overallSentiment = result.overall
                self.sentiments = result.parts
                message = result.parts.isEmpty
                    ? "NLTagger returned no sentiment score for \(languageName) text; the sentiment model may not support this language."
                    : "NLTagger sentimentScore rated \(result.parts.count) \(sentimentUnit.rawValue.lowercased())(s) from −1 (negative) to 1 (positive)."
            case .lemmas:
                let lemmas = await Self.runDetached { NaturalLanguageAnalyzer.lemmas(text) }
                self.lemmas = lemmas
                let known = lemmas.filter { $0.lemma != nil }.count
                message = "NLTagger (.lemma) found a lemma for \(known) of \(lemmas.count) word(s)." + (known == 0 && !lemmas.isEmpty ? " Lemmatization may not be supported for \(languageName)." : "")
            case .embeddings:
                let report = await Self.runDetached {
                    NaturalLanguageAnalyzer.embeddingReport(kind: kind, languageCode: languageCode, first: first, second: second, neighborCount: neighbors)
                }
                self.embeddingReport = report
                let name = NaturalLanguageFormat.languageName(languageCode)
                message = report == nil
                    ? "NLEmbedding.\(kind == .word ? "wordEmbedding" : "sentenceEmbedding")(for: .\(languageCode)) returned nil: no \(kind.rawValue.lowercased()) for \(name) is available on this device."
                    : "Loaded the \(name) \(kind.rawValue.lowercased())." + (report?.distance.map { "\nCosine distance: \($0.formatted(.number.precision(.fractionLength(3))))" } ?? "")
            }
            guard !Task.isCancelled else { return }
            let elapsed = (ContinuousClock.now - started).formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated))
            self.output = message + "\nFinished in \(elapsed) on device."
            self.isError = false
            self.isAnalyzing = false
        }
        #else
        output = "The NaturalLanguage framework is not available on this platform."
        isError = true
        #endif
    }

    /// Asks the system to download the tagger model for the detected language and selected scheme.
    func requestTaggerAssets() {
        #if canImport(NaturalLanguage)
        guard let code = dominantLanguage?.code else { return }
        let scheme = NaturalLanguageAnalyzer.tagScheme(tagScheme)
        output = "Requesting NLTagger assets for \(NaturalLanguageFormat.languageName(code)) · \(scheme.rawValue)…"
        isError = false
        Task { [weak self] in
            do {
                let result = try await NLTagger.requestAssets(for: NLLanguage(rawValue: code), tagScheme: scheme)
                let text = switch result {
                case .available: "Assets are available. Run the analysis again."
                case .notAvailable: "The system reports no assets for this language and scheme."
                case .error: "The asset request ended with an error result."
                @unknown default: "Asset request result: \(result.rawValue)"
                }
                self?.output = "NLTagger.requestAssets: \(text)"
                self?.isError = result != .available
                self?.availableSchemes = NaturalLanguageAnalyzer.availableSchemes(forLanguage: code)
            } catch {
                self?.output = "NLTagger.requestAssets failed: \(error.localizedDescription)"
                self?.isError = true
            }
        }
        #endif
    }

    /// Runs framework work on a background thread and returns only Sendable values.
    @concurrent nonisolated private static func runDetached<T: Sendable>(_ body: @Sendable () -> T) async -> T {
        body()
    }
}
