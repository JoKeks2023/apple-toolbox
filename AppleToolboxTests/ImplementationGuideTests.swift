import Testing
@testable import AppleToolbox

struct ImplementationGuideTests {
    @Test func everyExperimentHasAGuide() {
        let missing = ExperimentRegistry.all.map(\.id).filter { ImplementationGuides.guide(for: $0) == nil }
        #expect(missing.isEmpty, "No implementation guide for: \(missing.joined(separator: ", "))")
    }

    @Test func guidesBelongToRealExperiments() {
        let ids = Set(ExperimentRegistry.all.map(\.id))
        let unknown = ImplementationGuides.all.keys.filter { !ids.contains($0) }
        #expect(unknown.isEmpty, "Guides without an experiment: \(unknown.sorted().joined(separator: ", "))")
    }

    @Test func guidesAreFilledIn() {
        for (id, guide) in ImplementationGuides.all {
            #expect(guide.snippet.contains("import "), "\(id): the snippet should be a self-contained file")
            #expect(guide.infoPlist.allSatisfy { !$0.key.isEmpty && !$0.value.isEmpty }, "\(id): empty Info.plist entry")
        }
    }

    @Test func rendersInfoPlistXML() {
        let guide = ImplementationGuide(snippet: "import Foundation", infoPlist: [
            .init(key: "NSCameraUsageDescription", value: "Scans codes."),
            .init(key: "UIRequiresPersistentWiFi", value: "<true/>"),
        ])
        #expect(guide.infoPlistXML == "<key>NSCameraUsageDescription</key>\n<string>Scans codes.</string>\n<key>UIRequiresPersistentWiFi</key>\n<true/>")
    }
}
