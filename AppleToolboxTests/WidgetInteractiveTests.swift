import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct WidgetInteractiveTests {
    private let snapshot = ToolboxWidgetSnapshot(experimentID: "cryptokit", experimentName: "CryptoKit", symbolName: "lock.shield", status: "Available",
                                                 isAvailable: true, openedAt: Date(timeIntervalSinceReferenceDate: 0), availableCount: 10, totalCount: 12)

    @Test func pinsAndUnpinsTheLastOpenedExperiment() {
        var state = ToolboxInteractiveState()
        let date = Date(timeIntervalSinceReferenceDate: 100)
        state.setFavorite(true, from: snapshot, at: date)
        #expect(state.favorite == .init(experimentID: "cryptokit", experimentName: "CryptoKit", symbolName: "lock.shield", pinnedAt: date))
        state.setFavorite(false, from: snapshot, at: date)
        #expect(state.favorite == nil)
        state.setFavorite(true, from: nil, at: date)
        #expect(state.favorite == nil)
    }

    @Test func recordsInteractionsNewestFirstWithinTheLimit() {
        var state = ToolboxInteractiveState()
        for index in 0..<(ToolboxInteractiveState.interactionLimit + 3) {
            state.record("Refresh \(index)", bundleIdentifier: "com.example.AppleToolbox.ios.widget", at: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        #expect(state.interactions.count == ToolboxInteractiveState.interactionLimit)
        #expect(state.interactions.first?.intent == "Refresh \(ToolboxInteractiveState.interactionLimit + 2)")
        #expect(state.interactions.first?.process == "widget extension")
    }

    @Test func namesTheProcessThatRanAnIntent() {
        #expect(ToolboxInteractiveState.processName("com.example.AppleToolbox.ios.widget") == "widget extension")
        #expect(ToolboxInteractiveState.processName("com.example.AppleToolbox.ios") == "app")
        #expect(ToolboxInteractiveState.processName(nil) == "unknown process")
        #expect(ToolboxInteractiveState.processName("com.example.other") == "com.example.other")
    }

    @Test func listsEveryKindOnceAndRoundTripsTheState() throws {
        let ids = ToolboxWidgetStore.kinds.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(ToolboxWidgetStore.widgetKind))
        #expect(ids.contains(ToolboxWidgetStore.interactiveWidgetKind))
        #expect(ids.contains(ToolboxWidgetStore.openAppControlKind))
        #expect(ids.contains(ToolboxWidgetStore.favoriteControlKind))

        var state = ToolboxInteractiveState(refreshCount: 3, lastRefresh: Date(timeIntervalSinceReferenceDate: 5))
        state.setFavorite(true, from: snapshot, at: Date(timeIntervalSinceReferenceDate: 6))
        let decoded = try JSONDecoder().decode(ToolboxInteractiveState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
    }
}
