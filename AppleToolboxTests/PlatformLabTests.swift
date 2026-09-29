import Testing
import Foundation
import AppIntents
@testable import AppleToolbox

struct MetalComputeCheckTests {

    @Test func detectsExactDoubling() {
        let input = MetalComputeCheck.input(count: 8)
        #expect(MetalComputeCheck.mismatches(input: input, output: input.map { $0 * 2 }).isEmpty)
        var wrong = input.map { $0 * 2 }
        wrong[3] += 0.5
        #expect(MetalComputeCheck.mismatches(input: input, output: wrong) == [3])
        #expect(MetalComputeCheck.mismatches(input: input, output: Array(wrong.prefix(4))).count == 8)
    }

    @Test func inputIsNotTrivial() {
        let input = MetalComputeCheck.input(count: 4096)
        #expect(input.count == 4096)
        #expect(input.contains { $0 < 0 } && input.contains { $0 > 0 } && input.contains { $0 != $0.rounded() })
    }

    @Test func coversEveryElementWithThreadgroups() {
        #expect(MetalComputeCheck.threadgroups(count: 4096, width: 1024) == 4)
        #expect(MetalComputeCheck.threadgroups(count: 4097, width: 1024) == 5)
        #expect(MetalComputeCheck.threadgroups(count: 10, width: 32) == 1)
        #expect(MetalComputeCheck.threadgroups(count: 0, width: 32) == 0)
    }

    @Test func kernelDeclaresTheFunctionItCalls() {
        #expect(MetalComputeCheck.kernelSource.contains("kernel void \(MetalComputeCheck.functionName)("))
    }
}

struct MacHardwareFormattingTests {
    private let posix = Locale(identifier: "en_US_POSIX")

    @Test func rendersFourCharacterCodes() {
        #expect(MacHardwareFormatting.fourCC(0x7573_6220) == "usb ")
        #expect(MacHardwareFormatting.fourCC(0) == "0")
    }

    @Test func namesTransports() {
        #expect(MacHardwareFormatting.transportName(0x626C_746E) == "Built-in")
        #expect(MacHardwareFormatting.transportName(0x7573_6220) == "USB")
        #expect(MacHardwareFormatting.transportName(0x626C_7565) == "Bluetooth")
        #expect(MacHardwareFormatting.transportName(0x6363_776C) == "Continuity (wireless)")
        #expect(MacHardwareFormatting.transportName(0x7A7A_7A7A) == "Other ('zzzz')")
    }

    @Test func formatsSampleRates() {
        #expect(MacHardwareFormatting.sampleRates([44100...44100, 48000...48000], locale: posix) == "44.1, 48 kHz")
        #expect(MacHardwareFormatting.sampleRates([8000...192_000], locale: posix) == "8–192 kHz")
        #expect(MacHardwareFormatting.sampleRates([], locale: posix) == "None reported")
    }

    @Test func describesRefreshRates() {
        #expect(MacHardwareFormatting.refreshRate(minimumInterval: 1.0 / 120, maximumInterval: 1.0 / 24, maximumFPS: 120) == "24–120 Hz (adaptive)")
        #expect(MacHardwareFormatting.refreshRate(minimumInterval: 1.0 / 60, maximumInterval: 1.0 / 60, maximumFPS: 60) == "60 Hz (fixed)")
        #expect(MacHardwareFormatting.refreshRate(minimumInterval: 0, maximumInterval: 0, maximumFPS: 60) == "60 Hz")
    }
}

@MainActor
struct PlatformCategoryTests {

    @Test func platformCategoryListsTheLabs() {
        let ids = ExperimentRegistry.experiments(in: .platform).map(\.id)
        #expect(ids.contains("metal") && ids.contains("mac-hardware"))
        #expect(ExperimentRegistry.descriptor(for: "mac-hardware")?.supportedPlatforms == [.macOS])
    }

    @Test func everyCategoryHasAnAppIntentsRepresentation() {
        for category in ExperimentCategory.allCases {
            #expect(ExperimentCategory.caseDisplayRepresentations[category] != nil, "\(category.rawValue)")
        }
    }
}
