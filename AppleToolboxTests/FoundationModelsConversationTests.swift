import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct FoundationModelsConversationTests {

    @Test func contextUsageIsClamped() {
        #expect(FMContextMath.usage(tokens: 1_024, contextSize: 4_096) == 0.25)
        #expect(FMContextMath.usage(tokens: 9_000, contextSize: 4_096) == 1)
        #expect(FMContextMath.usage(tokens: 10, contextSize: 0) == 0)
    }

    @Test func oversizedPromptExceedsTheContextByCharacters() {
        let prompt = FMContextMath.oversizedPrompt(contextSize: 4_096)
        #expect(prompt.count > 4_096 * 6)
        #expect(prompt.hasPrefix("Summarize"))
    }

    @Test func condensingKeepsInstructionsAndTheLastResponse() {
        let entries = ["instructions", "prompt 1", "response 1", "prompt 2", "response 2", "prompt 3"]
        let kept = FMContextMath.condensed(entries, isInstructions: { $0 == "instructions" }, isResponse: { $0.hasPrefix("response") })
        #expect(kept == ["instructions", "response 2"])
        #expect(FMContextMath.condensed(["prompt"], isInstructions: { _ in false }, isResponse: { _ in false }).isEmpty)
    }

    @Test func baseLanguageCodes() {
        #expect(FMContextMath.baseLanguageCode("zh-Hans") == "zh")
        #expect(FMContextMath.baseLanguageCode("de") == "de")
    }

    @Test func everyFailureKindIsExplained() {
        for kind in FMFailureKind.allCases {
            #expect(!kind.title.isEmpty && !kind.explanation.isEmpty, "\(kind)")
        }
        #expect(FMFailureKind.contextWindowExceeded.offersCondensedSession)
        #expect(!FMFailureKind.guardrailViolation.offersCondensedSession)
    }

    @Test func toolsetsSelectTools() {
        #expect(FMToolset.both.includesDeviceCapabilities && FMToolset.both.includesExperimentCatalog)
        #expect(!FMToolset.none.includesDeviceCapabilities && !FMToolset.none.includesExperimentCatalog)
        #expect(FMToolset.experimentCatalog.includesExperimentCatalog && !FMToolset.experimentCatalog.includesDeviceCapabilities)
    }

    @Test func capabilityToolFiltersBySectionAndKeyword() {
        let report = DeviceScanReport(date: .now, platform: "iOS", sections: [
            CapabilitySection(title: "Sensors", symbol: "gyroscope", items: [.available("Barometer", "Relative altitude"), .unavailable("LiDAR", "No LiDAR scanner")]),
            CapabilitySection(title: "Hardware", symbol: "cpu", items: [.available("NFC", "Reader supported")]),
        ])
        let sensors = FMToolFormatting.capabilities(report, section: "Sensors", keyword: "")
        #expect(sensors.contains("- Barometer: Available") && sensors.contains("- LiDAR: Unavailable") && !sensors.contains("NFC"))
        let nfc = FMToolFormatting.capabilities(report, section: "All", keyword: "nfc")
        #expect(nfc.contains("Hardware:") && !nfc.contains("Barometer"))
        #expect(FMToolFormatting.capabilities(report, section: "Display", keyword: "").hasPrefix("No capability"))
    }

    @Test func catalogSearchRanksNameMatchesFirst() {
        let results = ExperimentCatalogSearch.rank("speech", in: ExperimentRegistry.all).map(\.id)
        #expect(results.contains("speech") && results.contains("speech-analyzer"))
        #expect(ExperimentCatalogSearch.rank("  ", in: ExperimentRegistry.all).isEmpty)
        #expect(ExperimentCatalogSearch.answer("zzqxv").hasPrefix("No experiment"))
        #expect(ExperimentCatalogSearch.matches("nfc", in: "Core NFC reader"))
        #expect(!ExperimentCatalogSearch.matches("ar", in: "Hardware card"))
        #expect(ExperimentCatalogSearch.matches("speech", in: "SpeechAnalyzer"))
    }
}
