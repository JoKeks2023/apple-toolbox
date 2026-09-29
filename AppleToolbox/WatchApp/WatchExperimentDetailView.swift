import SwiftUI

/// Watch detail (spec §37/§38): live status, "Why doesn't this work?", the pre-run checks and the watch run view.
/// Uses the same `checks(for:)` and `explanation(for:)` models as the iPhone detail view.
struct WatchExperimentDetailView: View {
    let experiment: ExperimentDescriptor
    /// Re-evaluates the status whenever a permission changes.
    @ObservedObject private var permissions = PermissionCenter.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let status = experiment.currentStatus
        List {
            Section {
                Text(experiment.description).font(.caption2)
                LabeledContent("Status") { WatchStatusText(status: status) }
                LabeledContent("Frameworks", value: experiment.frameworks.joined(separator: ", "))
            }
            if WatchRunCatalog.hasWatchRun(experiment.id) {
                Section {
                    NavigationLink { WatchRunRoutes(experiment: experiment) } label: {
                        Label("Run on Watch", systemImage: "play.circle.fill")
                    }
                } footer: {
                    Text("Calls the real API on this Apple Watch.")
                }
            }
            if let explanation = experiment.explanation(for: status) {
                Section("Why doesn't this work?") {
                    WatchFactRow(title: "Reason", text: explanation.reason)
                    WatchFactRow(title: "Required", text: explanation.required)
                    WatchFactRow(title: "Next step", text: explanation.nextStep)
                }
            }
            Section("Checks") {
                ForEach(experiment.checks(for: status)) { WatchCheckRow(check: $0) }
            }
        }
        .navigationTitle(experiment.name)
        .onChange(of: scenePhase) { _, phase in
            // Permissions can change in Settings while the app is in the background.
            if phase == .active { Task { await permissions.refresh() } }
        }
    }
}

/// Routes an experiment to its compact watch run view. Each view owns only its own service.
struct WatchRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "core-motion": WatchMotionView()
        case "continuity": WatchLinkView()
        case "core-location": WatchLocationView()
        case "core-bluetooth": WatchBluetoothView()
        case "nearby-interaction": WatchNearbyView()
        case "healthkit-status": WatchHealthReaderView()
        case "homekit-discovery": WatchHomeKitView()
        case "natural-language": WatchNaturalLanguageView()
        case "musickit": WatchMusicKitView()
        case "capability-explorer": WatchCapabilityExplorerView()
        case "app-intents": WatchAppIntentsView()
        case "notifications": WatchNotificationsView()
        case "cryptokit": WatchCryptoKitView()
        case "keychain": WatchKeychainView()
        case "secure-enclave": WatchSecureEnclaveView()
        case "app-attest": WatchAppAttestView(experiment: experiment)
        case "sign-in-with-apple": WatchSignInWithAppleView(experiment: experiment)
        default: List { WatchOutput(text: "No watch run view is registered for this experiment.", isError: true) }
        }
    }
}

// MARK: Shared watch rows

struct WatchStatusText: View {
    let status: ExperimentStatus

    var body: some View {
        Text(status.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(status == .available ? .green : .orange)
    }
}

/// A title with a wrapping value below it, for text too long for a trailing label on a watch screen.
struct WatchFactRow: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.caption)
        }
    }
}

struct WatchCheckRow: View {
    let check: ExperimentCheck

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(check.title).font(.caption.weight(.semibold))
                Text(check.detail).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var symbol: String {
        switch check.outcome {
        case .passed: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .failed: "xmark.octagon.fill"
        case .notApplicable: "minus.circle"
        }
    }

    private var color: Color {
        switch check.outcome {
        case .passed: .green
        case .pending: .orange
        case .failed: .red
        case .notApplicable: .secondary
        }
    }
}

/// The live output of a watch run view: what the real API returned, or its real error.
struct WatchOutput: View {
    let text: String
    var isError = false

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(isError ? .red : .secondary)
    }
}
