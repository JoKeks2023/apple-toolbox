import Testing
import Foundation
import NaturalLanguage
@testable import AppleToolbox

struct NaturalLanguageTests {

    @Test func tagTonesMatchTheFrameworkTags() {
        #expect(NLTagTone(tag: NLTag.noun.rawValue) == .noun)
        #expect(NLTagTone(tag: NLTag.verb.rawValue) == .verb)
        #expect(NLTagTone(tag: NLTag.adjective.rawValue) == .adjective)
        #expect(NLTagTone(tag: NLTag.determiner.rawValue) == .function)
        #expect(NLTagTone(tag: NLTag.number.rawValue) == .number)
        #expect(NLTagTone(tag: NLTag.personalName.rawValue) == .person)
        #expect(NLTagTone(tag: NLTag.placeName.rawValue) == .place)
        #expect(NLTagTone(tag: NLTag.organizationName.rawValue) == .organization)
        #expect(NLTagTone(tag: NLTag.sentenceTerminator.rawValue) == .punctuation)
        #expect(NLTagTone(tag: NLTag.whitespace.rawValue) == .whitespace)
        #expect(NLTagTone(tag: NLTag.word.rawValue) == .word)
        #expect(NLTagTone(tag: "de") == .other)
    }

    @Test func entityCountsIgnoreOtherTokensAndSortByFrequency() {
        let tokens = [
            NLTaggedToken(id: 0, text: "Tim Cook", tag: NLTag.personalName.rawValue),
            NLTaggedToken(id: 1, text: "presented", tag: NLTag.verb.rawValue),
            NLTaggedToken(id: 2, text: "Cupertino", tag: NLTag.placeName.rawValue),
            NLTaggedToken(id: 3, text: "Berlin", tag: NLTag.placeName.rawValue),
        ]
        let counts = NaturalLanguageFormat.entityCounts(tokens)
        #expect(counts.map(\.tone) == [.place, .person])
        #expect(counts.map(\.count) == [2, 1])
    }

    @Test func sentimentHelpers() {
        #expect(NaturalLanguageFormat.sentimentLabel(for: 0.8) == "Positive")
        #expect(NaturalLanguageFormat.sentimentLabel(for: 0) == "Neutral")
        #expect(NaturalLanguageFormat.sentimentLabel(for: -0.6) == "Negative")
        #expect(NaturalLanguageFormat.sentimentFraction(for: -1) == 0)
        #expect(NaturalLanguageFormat.sentimentFraction(for: 0) == 0.5)
        #expect(NaturalLanguageFormat.sentimentFraction(for: 3) == 1)
    }

    @Test func cosineSimilarityAndOffsets() {
        #expect(NaturalLanguageFormat.cosineSimilarity(fromDistance: 0) == 1)
        #expect(NaturalLanguageFormat.cosineSimilarity(fromDistance: 2) == -1)
        let text = "Grüße aus Köln"
        let range = text.range(of: "Köln")!
        let position = NaturalLanguageFormat.offsets(of: range, in: text)
        #expect(position.offset == 10)
        #expect(position.length == 4)
    }

    @Test func embeddingSupportSummary() {
        #expect(NLEmbeddingSupport(code: "en", name: "English", wordRevisions: [1], sentenceRevisions: [1]).summary == "word + sentence")
        #expect(NLEmbeddingSupport(code: "x", name: "X", wordRevisions: [], sentenceRevisions: []).summary == "none")
    }

    @Test func wordTokenizationUsesTheRealTokenizer() {
        let tokens = NaturalLanguageAnalyzer.tokens("Hello, world! 42", unit: .word)
        #expect(tokens.map(\.text) == ["Hello", "world", "42"])
        #expect(tokens.first?.offset == 0)
        #expect(tokens.last?.attributes.contains("numeric") == true)
    }

    @Test func tagSchemeOptionsMapToDistinctSchemes() {
        let schemes = NLTagSchemeOption.allCases.map { NaturalLanguageAnalyzer.tagScheme($0).rawValue }
        #expect(Set(schemes).count == NLTagSchemeOption.allCases.count)
        #expect(NLTagSchemeOption.nameType.joinsNames && !NLTagSchemeOption.lexicalClass.joinsNames)
    }
}
