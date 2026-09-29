import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct ToolboxToolsTests {

    @Test func everyToolOpensAnExperiment() {
        for tool in ToolboxTools.all {
            #expect(tool.experiment != nil, "\(tool.id)")
            #expect(!tool.promotedFrom.isEmpty && !tool.summary.isEmpty, "\(tool.id)")
        }
    }

    @Test func coversTheSpecUtilities() {
        let titles = Set(ToolboxTools.all.map(\.title))
        for title in ["NFC Inspector", "Network Inspector", "Location Dashboard", "Audio Analyzer", "Home Inspector", "Indoor Survey", "Crypto Lab"] {
            #expect(titles.contains(title), "\(title)")
        }
        #expect(Set(ToolboxTools.all.map(\.id)).count == ToolboxTools.all.count)
    }
}
