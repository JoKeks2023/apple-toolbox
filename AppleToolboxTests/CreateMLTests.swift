import Testing
import Foundation
@testable import AppleToolbox

struct CreateMLTests {

    @Test func textSampleHasTextAndLabelColumnsWithBalancedLabels() throws {
        let info = try CreateMLDataset.inspect(CreateMLDataset.textSample)
        #expect(info.columns.map(\.name) == ["text", "label"])
        #expect(info.textColumns.count == 2)
        #expect(info.rowCount == 24)
        let counts = try CreateMLDataset.labelCounts(CreateMLDataset.textSample, column: "label")
        #expect(counts.map(\.label) == ["bug", "feature", "question"])
        #expect(counts.allSatisfy { $0.count == 8 })
    }

    @Test func tabularSampleIsNumeric() throws {
        let info = try CreateMLDataset.inspect(CreateMLDataset.tabularSample)
        #expect(info.rowCount == 20)
        #expect(info.numericColumns.map(\.name) == ["size_m2", "rooms", "distance_km", "rent_eur"])
        #expect(info.columns.first { $0.name == "distance_km" }?.kind == .decimal)
        #expect(info.columns.first { $0.name == "rooms" }?.kind == .integer)
        #expect(info.columns.first?.example == "32")
    }

    @Test func labelCountsOfAMissingColumnAreEmpty() throws {
        #expect(try CreateMLDataset.labelCounts("a,b\n1,2\n", column: "label").isEmpty)
    }

    @Test func accuracyAndRanking() {
        #expect(CreateMLFormat.accuracy(fromClassificationError: 0.25) == 0.75)
        #expect(CreateMLFormat.accuracy(fromClassificationError: 1.5) == 0)
        let ranked = CreateMLFormat.ranked(["question": 0.1, "bug": 0.7, "feature": 0.2])
        #expect(ranked.map(\.label) == ["bug", "feature", "question"])
    }

    @Test func metricColumnsAreFoundByKeyword() {
        let names = ["True Label", "Predicted", "Count"]
        #expect(CreateMLFormat.column(in: names, matching: ["true", "actual"]) == "True Label")
        #expect(CreateMLFormat.column(in: names, matching: ["predict"]) == "Predicted")
        #expect(CreateMLFormat.column(in: ["Class", "Precision", "Recall"], matching: ["recall"]) == "Recall")
        #expect(CreateMLFormat.column(in: names, matching: ["precision"]) == nil)
    }

    @Test func samplesFollowTheTask() {
        #expect(CreateMLDataset.sample(for: .textClassifier).hasPrefix("text,label"))
        #expect(CreateMLDataset.sample(for: .tabularRegressor).hasPrefix("size_m2"))
    }
}
