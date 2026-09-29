import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct DeveloperToolsCatalogTests {

    @Test func coversTheSpecTools() {
        let names = Set(DeveloperToolsCatalog.all.map(\.name))
        for name in ["Xcode", "Simulator", "Instruments", "Accessibility Inspector", "Create ML", "Reality Composer Pro",
                     "HomeKit Accessory Simulator", "PacketLogger", "FileMerge", "Console", "Xcode Cloud", "Indoor Survey",
                     "AirPort Utility", "Field Test Mode", "Apple Configurator", "Apple Business Manager",
                     "Apple Business Register", "Apple Business Connect"] {
            #expect(names.contains(name), "\(name)")
        }
    }

    @Test func identifiersAreUniqueAndLinksResolve() {
        let ids = DeveloperToolsCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        for tool in DeveloperToolsCatalog.all {
            #expect(!tool.summary.isEmpty && !tool.inToolbox.isEmpty, "\(tool.id)")
            for experiment in tool.relatedExperiments {
                #expect(ExperimentRegistry.descriptor(for: experiment) != nil, "\(tool.id) → \(experiment)")
            }
        }
    }
}
