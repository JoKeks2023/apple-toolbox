import Testing
import Foundation
import ActivityKit
@testable import AppleToolbox

@MainActor
struct LiveActivityTests {

    @Test func derivesSamplesFromTheRunLength() {
        #expect(LiveActivityRunLength.oneMinute.totalSamples == 4)
        #expect(LiveActivityRunLength.fiveMinutes.totalSamples == 20)
        #expect(LiveActivityRunLength.fifteenMinutes.totalSamples == 60)
        #expect(LiveActivityRunLength.oneMinute.title == "1 minute")
        #expect(LiveActivityRunLength.fifteenMinutes.title == "15 minutes")
        #expect(LiveActivityRunLength.staleAfter > LiveActivityRunLength.sampleInterval)
    }

    @Test func describesReadings() {
        #expect(LiveActivityReading.battery(level: -1, state: "state unknown") == "Battery level unavailable")
        #expect(LiveActivityReading.battery(level: 0.824, state: "charging") == "Battery 82 % · charging")
        #expect(LiveActivityReading.thermal(.nominal) == "Thermal nominal")
        #expect(LiveActivityReading.thermal(.critical) == "Thermal critical")
    }

    @Test func clampsProgressAndStaysUnderTheActivityKitSizeLimit() throws {
        typealias State = ToolboxActivityAttributes.ContentState
        let state = State(phase: .measuring, sample: 3, totalSamples: 4, reading: "Battery 82 % · charging",
                          detail: "Thermal nominal · Low Power off", updatedAt: Date())
        #expect(state.progress == 0.75)
        #expect(State(phase: .finished, sample: 9, totalSamples: 4, reading: "", detail: "", updatedAt: Date()).progress == 1)
        #expect(State(phase: .measuring, sample: 0, totalSamples: 0, reading: "", detail: "", updatedAt: Date()).progress == 0)

        let attributes = ToolboxActivityAttributes(runName: "Device measurement", symbolName: "gauge.with.dots.needle.33percent",
                                                   startedAt: Date(), plannedEnd: Date().addingTimeInterval(900))
        let size = try JSONEncoder().encode(attributes).count + JSONEncoder().encode(state).count
        #expect(size < 4096)
        #expect(try JSONDecoder().decode(State.self, from: JSONEncoder().encode(state)) == state)
    }

    @Test func explainsActivityKitErrorsAndDismissal() {
        #expect(LiveActivityErrors.explain(ActivityAuthorizationError.denied).contains("turned off"))
        #expect(LiveActivityErrors.explain(ActivityAuthorizationError.visibility).contains("foreground"))
        #expect(LiveActivityErrors.explain(ActivityAuthorizationError.unentitled).contains("NSSupportsLiveActivities"))
        #expect(LiveActivityErrors.title(.stale) == "stale")
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        #expect(LiveActivityDismissalChoice.afterOneMinute.policy(endingAt: date) == .after(date.addingTimeInterval(60)))
        #expect(LiveActivityDismissalChoice.immediate.policy(endingAt: date) == .immediate)
    }
}
