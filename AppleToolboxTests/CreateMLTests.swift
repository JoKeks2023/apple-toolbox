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

    @Test func labelsAreNormalizedAndUniqueIgnoringCase() throws {
        var set = CreateMLSampleSet()
        #expect(try set.addLabel("  red   apple ") == "red apple")
        #expect(throws: CreateMLLabelError.duplicate("red apple")) { try set.addLabel("Red Apple") }
        #expect(throws: CreateMLLabelError.empty) { try set.addLabel("   ") }
        #expect(set.labels == ["red apple"])
    }

    @Test func samplesAreGroupedByLabel() throws {
        var set = CreateMLSampleSet()
        try set.addLabel("cat")
        try set.addLabel("dog")
        try set.addLabel("empty")
        let cat = [sample("a.jpg"), sample("b.jpg")]
        set.add(cat, to: "cat")
        set.add([sample("c.jpg")], to: "dog")
        set.add([sample("ignored.jpg")], to: "unknown")
        #expect(set.sampleCount == 3)
        #expect(set.filesByLabel.keys.sorted() == ["cat", "dog"])
        #expect(set.filesByLabel["cat"] == cat.map(\.url))
        #expect(set.removeSample(id: cat[0].id)?.name == "a.jpg")
        #expect(set.removeLabel("dog").map(\.name) == ["c.jpg"])
        #expect(set.labels == ["cat", "empty"])
    }

    @Test func readinessNeedsTwoFilledLabelsWithTwoSamplesEach() throws {
        var set = CreateMLSampleSet()
        try set.addLabel("clap")
        set.add([sample("1.wav"), sample("2.wav")], to: "clap")
        #expect(set.readiness(noun: "sound")?.contains("at least 2 labels") == true)
        try set.addLabel("snap")
        set.add([sample("3.wav")], to: "snap")
        #expect(set.readiness(noun: "sound")?.contains("snap") == true)
        set.add([sample("4.wav")], to: "snap")
        #expect(set.readiness(noun: "sound") == nil)
    }

    @Test func trainedModelFileNamesSortByTime() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        #expect(CreateMLModelStore.fileName(for: .imageClassifier, date: date) == "ImageClassifier-20260921-141320.mlmodel")
        #expect(CreateMLModelStore.fileName(for: .tabularRegressor, date: date).hasPrefix("TabularRegressor-"))
        #expect(CreateMLTask.soundClassifier.usesLabeledFiles && !CreateMLTask.textClassifier.usesLabeledFiles)
    }

    private func sample(_ name: String) -> CreateMLSample {
        CreateMLSample(id: UUID(), url: URL(fileURLWithPath: "/tmp/\(name)"), name: name)
    }
}
