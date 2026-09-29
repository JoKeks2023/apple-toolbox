import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct TVPlatformTests {

    @Test func hapticPatternsAreValid() {
        for pattern in ControllerHapticPattern.allCases {
            #expect(!pattern.events.isEmpty, "\(pattern.rawValue)")
            for event in pattern.events {
                #expect((0...1).contains(event.intensity) && (0...1).contains(event.sharpness))
                #expect(event.time >= 0 && (event.duration ?? 0) >= 0)
            }
            #expect(pattern.totalDuration > 0)
        }
        #expect(ControllerHapticPattern.tap.events.first?.duration == nil)
        #expect(ControllerHapticPattern.rumble.totalDuration == 1)
        #expect(ControllerHapticPattern.pulses.events.count == 3)
    }

    @Test func multipeerLinksIPhoneAndAppleTV() {
        let multipeer = ExperimentRegistry.descriptor(for: "multipeer-connectivity")
        #expect(multipeer?.supportedPlatforms.contains(.tvOS) == true)
        #expect(multipeer?.supportedPlatforms.contains(.iOS) == true)
    }
}
