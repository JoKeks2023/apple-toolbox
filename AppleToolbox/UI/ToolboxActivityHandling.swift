import SwiftUI
#if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
import CoreSpotlight
#endif

extension View {
    /// App-wide system entry points: keeps the Spotlight index current and opens tapped Spotlight results
    /// through `ToolboxNavigator`.
    func toolboxActivityHandling() -> some View {
        modifier(ToolboxActivityHandling())
    }

    /// Per-experiment system integration: donates the Open Experiment intent when the experiment opens.
    func experimentActivity(_ experiment: ExperimentDescriptor) -> some View {
        modifier(ExperimentActivity(experiment: experiment))
    }
}

private struct ToolboxActivityHandling: ViewModifier {
    func body(content: Content) -> some View {
        content
        #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
            .task { await ExperimentSpotlightIndex.synchronizeOnLaunch() }
            .onContinueUserActivity(CSSearchableItemActionType, perform: ExperimentSpotlightIndex.continueFromSpotlight)
        #endif
    }
}

private struct ExperimentActivity: ViewModifier {
    let experiment: ExperimentDescriptor

    func body(content: Content) -> some View {
        content
            .task(id: experiment.id) { await IntentDonationLog.shared.donateOpen(experiment) }
    }
}
