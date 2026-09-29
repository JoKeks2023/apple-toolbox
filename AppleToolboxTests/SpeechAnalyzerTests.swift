import Testing
import Foundation
@testable import AppleToolbox

struct SpeechAnalyzerTests {

    @Test func timestampsUseMinutesAndTenths() {
        #expect(SpeechAnalyzerFormat.timestamp(0) == "0:00.0")
        #expect(SpeechAnalyzerFormat.timestamp(3.24) == "0:03.2")
        #expect(SpeechAnalyzerFormat.timestamp(75.5) == "1:15.5")
        #expect(SpeechAnalyzerFormat.timestamp(59.96) == "1:00.0")
        #expect(SpeechAnalyzerFormat.timestamp(.nan) == "–:––")
        #expect(SpeechAnalyzerFormat.timestamp(-1) == "–:––")
    }

    @Test func frameCapacityScalesWithTheSampleRate() {
        #expect(SpeechAnalyzerFormat.frameCapacity(inputFrames: 4_800, inputRate: 48_000, outputRate: 16_000) == 1_600)
        #expect(SpeechAnalyzerFormat.frameCapacity(inputFrames: 1_000, inputRate: 44_100, outputRate: 16_000) == 363)
        #expect(SpeechAnalyzerFormat.frameCapacity(inputFrames: 512, inputRate: 16_000, outputRate: 16_000) == 512)
        #expect(SpeechAnalyzerFormat.frameCapacity(inputFrames: 512, inputRate: 0, outputRate: 16_000) == 512)
    }

    @Test func audioFormatDescription() {
        #expect(SpeechAnalyzerFormat.audioFormat(sampleRate: 16_000, channels: 1, sampleFormat: "Int16", interleaved: false) == "16000 Hz · 1 ch · Int16")
        #expect(SpeechAnalyzerFormat.audioFormat(sampleRate: 48_000, channels: 2, sampleFormat: "Float32", interleaved: true) == "48000 Hz · 2 ch · Float32 interleaved")
    }

    @Test func averageConfidence() {
        #expect(SpeechAnalyzerFormat.averageConfidence([]) == nil)
        #expect(SpeechAnalyzerFormat.averageConfidence([0.5, 1]) == 0.75)
    }

    @Test func modesAndAssetStates() {
        #expect(SpeechTranscriberMode.progressive.reportsVolatileResults)
        #expect(!SpeechTranscriberMode.finalOnly.reportsVolatileResults)
        #expect(SpeechAssetState.installed.summary.hasPrefix("Installed"))
        #expect(SpeechAssetState.supported.summary.contains("not downloaded"))
    }
}
