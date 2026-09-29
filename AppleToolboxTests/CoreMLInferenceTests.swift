import Testing
import Foundation
@testable import AppleToolbox

struct CoreMLInferenceTests {

    @Test func statisticsSeparateTheFirstRun() throws {
        let stats = try #require(InferenceTimingStats(milliseconds: [9, 2, 4, 3, 1]))
        #expect(stats.runs == 5)
        #expect(stats.firstMilliseconds == 9)
        #expect(stats.minMilliseconds == 1)
        #expect(stats.maxMilliseconds == 4)
        #expect(stats.medianMilliseconds == 2.5)
        #expect(stats.meanMilliseconds == 2.5)
    }

    @Test func singleAndOddRunStatistics() throws {
        let single = try #require(InferenceTimingStats(milliseconds: [7]))
        #expect(single.medianMilliseconds == 7 && single.meanMilliseconds == 7)
        #expect(single.summary.hasPrefix("1 run: 7") && single.summary.hasSuffix(" ms"))
        let odd = try #require(InferenceTimingStats(milliseconds: [5, 3, 1, 2]))
        #expect(odd.medianMilliseconds == 2)
        #expect(InferenceTimingStats(milliseconds: []) == nil)
    }

    @Test func durationsAndFormatting() {
        #expect(InferenceTimingStats.milliseconds(.milliseconds(12)) == 12)
        #expect(InferenceTimingStats.milliseconds(.microseconds(250)) == 0.25)
        #expect(InferenceTimingStats.format(0.042).hasSuffix("042 ms"))
        #expect(InferenceTimingStats.format(1_240).hasSuffix("24 s"))
    }

    @Test func syntheticInputIsDeterministicAndBounded() {
        let values = SyntheticInput.values(count: 1_000)
        #expect(values == SyntheticInput.values(count: 1_000))
        #expect(values.allSatisfy { (-1...1).contains($0) })
        #expect(Set(values).count > 900)
        #expect(SyntheticInput.values(count: 0).isEmpty)
    }

    @Test func typedInputsAreParsed() {
        #expect(CoreMLInputParser.value(for: .integer, text: " 42 ") == .success(.integer(42)))
        #expect(CoreMLInputParser.value(for: .double, text: "3,5") == .success(.double(3.5)))
        #expect(CoreMLInputParser.value(for: .double, text: "abc") == .failure(.notANumber("abc", "a number")))
        #expect(CoreMLInputParser.value(for: .text, text: " hi ") == .success(.text(" hi ")))
        #expect(CoreMLInputParser.value(for: .multiArray(shape: [1, 15600], dataType: "Float32"), text: "") == .success(.synthetic))
        #expect(CoreMLInputParser.value(for: .image(width: 299, height: 299), text: "") == .failure(.missingImage))
    }

    @Test func outputsAreSummarized() {
        let top = CoreMLOutputFormat.topProbabilities(["question": 0.1, "bug": 0.7, "feature": 0.2], limit: 2)
        #expect(top.hasPrefix("bug 70") && top.contains(" · feature 20") && !top.contains("question"))
        #expect(CoreMLOutputFormat.plannedDevices(["CPU": 3, "Neural Engine": 41, "GPU": 0]) == "Neural Engine 41 · CPU 3")
        #expect(CoreMLOutputFormat.plannedDevices([:]) == nil)
    }
}
