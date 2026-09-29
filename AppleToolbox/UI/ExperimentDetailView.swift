import SwiftUI

struct ExperimentDetailView: View {
    let experiment: ExperimentDescriptor
    /// Re-evaluates the status whenever a permission changes.
    @ObservedObject private var permissions = PermissionCenter.shared
    @StateObject private var lifecycle = ExperimentLifecycle()
    /// Changing the identity recreates the run view with fresh services and state.
    @State private var runID = UUID()

    var body: some View {
        List {
            let status = experiment.currentStatus
            ExperimentHeroView(experiment: experiment, status: status)
            if let explanation = experiment.explanation(for: status) {
                WhyNotSection(explanation: explanation, status: status)
            }
            ExperimentChecksSection(checks: experiment.checks(for: status))
            UseCaseSection(useCase: experiment.useCase ?? .generic(for: experiment.id), experiment: experiment)
            Section("Run") {
                ExperimentRunView(experiment: experiment).id(runID)
                Button("Reset Experiment", systemImage: "arrow.counterclockwise") {
                    lifecycle.reset()
                    runID = UUID()
                }
            }
            RequirementsView(experiment: experiment)
            Section("Documentation") { Link(destination: experiment.documentationURL) { Label("Open Apple Developer Documentation", systemImage: "book.closed") } }
        }
        .navigationTitle(experiment.name)
        .environmentObject(lifecycle)
        .onAppear { WidgetKitExperimentService.recordOpened(experiment) }
        .onDisappear { lifecycle.stopAll() }
    }
}

/// Routes an experiment to its run view. Each run view owns only the service it needs,
/// so opening one experiment never starts another experiment's framework.
struct ExperimentRunView: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.category {
        case .security: SecurityRunRoutes(experiment: experiment)
        case .location: LocationRunRoutes(experiment: experiment)
        case .sensors: SensorsRunRoutes(experiment: experiment)
        case .input: InputRunRoutes(experiment: experiment)
        case .connectivity: ConnectivityRunRoutes(experiment: experiment)
        case .networking: NetworkingRunRoutes(experiment: experiment)
        case .nfc: NFCRunRoutes(experiment: experiment)
        case .home: HomeRunRoutes(experiment: experiment)
        case .camera: CameraRunRoutes(experiment: experiment)
        case .spatial: SpatialRunRoutes(experiment: experiment)
        case .audio: AudioRunRoutes(experiment: experiment)
        case .ai: AIRunRoutes(experiment: experiment)
        case .maps: MapsRunRoutes(experiment: experiment)
        case .wallet: WalletRunRoutes(experiment: experiment)
        case .health: HealthRunRoutes(experiment: experiment)
        case .system: SystemRunRoutes(experiment: experiment)
        case .developer: DeveloperRunRoutes(experiment: experiment)
        }
    }
}

struct UnroutedExperimentView: View {
    var body: some View { OutputView(text: "No run view is registered for this experiment.", isError: true) }
}

private struct ExperimentHeroView: View {
    let experiment: ExperimentDescriptor
    let status: ExperimentStatus

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    Image(systemName: experiment.category.symbolName)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(width: 48, height: 48)
                        .background(.tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(experiment.name)
                            .font(.title3.weight(.semibold))
                        Text(experiment.category.rawValue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    StatusBadge(status: status)
                }
                Text(experiment.description)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    InfoChip(title: CurrentPlatform.value.rawValue, symbol: "display.2")
                    InfoChip(title: experiment.frameworks.first ?? "Apple API", symbol: "shippingbox")
                    if !experiment.hardwareRequirements.isEmpty {
                        InfoChip(title: "Hardware", symbol: "cpu")
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }
}

private struct WhyNotSection: View {
    let explanation: ExperimentExplanation
    let status: ExperimentStatus
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section("Why doesn't this work?") {
            LabeledContent("Reason") { Text(explanation.reason).multilineTextAlignment(.trailing) }
            LabeledContent("Required") { Text(explanation.required).multilineTextAlignment(.trailing) }
            LabeledContent("Next step") { Text(explanation.nextStep).multilineTextAlignment(.trailing) }
            if status == .permissionDenied, let settingsURL {
                Button("Open Settings", systemImage: "gear") { openURL(settingsURL) }
            }
        }
    }

    private var settingsURL: URL? {
        #if os(iOS) || os(tvOS)
        URL(string: UIApplication.openSettingsURLString)
        #elseif os(macOS)
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy")
        #else
        nil
        #endif
    }
}

private struct ExperimentChecksSection: View {
    let checks: [ExperimentCheck]

    var body: some View {
        Section("Checks") {
            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: symbol(for: check.outcome))
                        .foregroundStyle(color(for: check.outcome))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(check.title).font(.subheadline.weight(.semibold))
                        Text(check.detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func symbol(for outcome: ExperimentCheck.Outcome) -> String {
        switch outcome {
        case .passed: "checkmark.circle.fill"
        case .pending: "clock.fill"
        case .failed: "xmark.octagon.fill"
        case .notApplicable: "minus.circle"
        }
    }

    private func color(for outcome: ExperimentCheck.Outcome) -> Color {
        switch outcome {
        case .passed: .green
        case .pending: .orange
        case .failed: .red
        case .notApplicable: .secondary
        }
    }
}

private struct UseCaseSection: View {
    let useCase: ExperimentUseCase
    let experiment: ExperimentDescriptor

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Try it", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Text("LIVE PLAYGROUND")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                Label(useCase.title, systemImage: "play.circle.fill")
                    .font(.headline)
                Text(useCase.summary)
                HStack(alignment: .top, spacing: 10) {
                    Text("1")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(.tint, in: Circle())
                    Text(useCase.interaction)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !experiment.permissions.isEmpty || !experiment.hardwareRequirements.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(experiment.permissions, id: \.self) { InfoChip(title: $0, symbol: "lock.open") }
                            ForEach(experiment.hardwareRequirements, id: \.self) { InfoChip(title: $0, symbol: "cpu") }
                        }
                    }
                }
            }
            .padding(14)
            .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

private struct RequirementsView: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        Section("Requirements") {
            LabeledContent("Frameworks", value: experiment.frameworks.joined(separator: ", "))
            LabeledContent("Platforms", value: experiment.supportedPlatforms.map(\.rawValue).joined(separator: " · "))
            LabeledContent("Hardware", value: experiment.hardwareRequirements.isEmpty ? "None listed" : experiment.hardwareRequirements.joined(separator: ", "))
            LabeledContent("OS", value: experiment.osRequirements.joined(separator: ", "))
            LabeledContent("Permissions", value: experiment.permissions.isEmpty ? "None" : experiment.permissions.joined(separator: ", "))
            LabeledContent("Capabilities", value: experiment.capabilities.isEmpty ? "None" : experiment.capabilities.joined(separator: ", "))
            LabeledContent("Entitlements", value: experiment.entitlements.isEmpty ? "None" : experiment.entitlements.joined(separator: ", "))
        }
    }
}
