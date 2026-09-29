import SwiftUI
#if canImport(GroupActivities) && (os(iOS) || os(macOS))
import GroupActivities
#endif

/// Continuity (spec §28): Handoff of the open experiment, SharePlay "Explore Together", ShareLink/AirDrop of an
/// experiment summary, and the Universal Links boundary.
struct ContinuityLabRunView: View {
    var body: some View {
        #if os(iOS) || os(macOS)
        HandoffSection()
        SharePlaySection()
        ShareSummarySection()
        UniversalLinksSection()
        #else
        OutputView(text: "Apple Toolbox on \(CurrentPlatform.value.rawValue) takes part in neither Handoff nor its SharePlay activity, and ShareLink is not available here.", isError: true)
        #endif
    }
}

#if os(iOS) || os(macOS)
private struct HandoffSection: View {
    @ObservedObject private var log = ToolboxActivityLog.shared
    @State private var team: String?

    var body: some View {
        Section("Handoff · NSUserActivity") {
            LabeledContent("Activity type") { Text(ExperimentHandoff.activityType).font(.caption.monospaced()).multilineTextAlignment(.trailing) }
            LabeledContent("Declared in NSUserActivityTypes", value: ExperimentHandoff.isDeclared(in: Bundle.main.infoDictionary) ? "Yes" : "No")
            LabeledContent("Signing team", value: team ?? "Unknown (no embedded profile)")
            LabeledContent("Advertised now", value: "Continuity (this screen)")
            let entries = log.entries(in: [.handoff])
            if entries.isEmpty {
                Text("No Handoff received in this session. Open an experiment on another device signed in to the same Apple Account, then pick up Apple Toolbox here from the Dock or the App Switcher.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { ActivityLogRow(entry: $0) }
            }
            Text("Every open experiment advertises this activity with its ID. Handoff needs the same Apple Account on both devices, Bluetooth and Wi-Fi turned on, Handoff enabled in Settings, and both apps signed by the same team. No public API tells an app whether Handoff is enabled or which devices are nearby.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { team = ProvisioningInspector.load().profile?.teamIdentifier }
    }
}

private struct SharePlaySection: View {
    @ObservedObject private var sharePlay = SharePlayCoordinator.shared
    @ObservedObject private var log = ToolboxActivityLog.shared
    @StateObject private var groupState = GroupStateObserver()
    @State private var experimentID = ExperimentRegistry.all.first?.id ?? ""

    var body: some View {
        Section("SharePlay · GroupActivities") {
            LabeledContent("Group Activities entitlement") {
                Text(IdentityEntitlements.summary(of: IdentityEntitlements.state(ofCapability: "group-activities"), key: "com.apple.developer.group-session"))
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("FaceTime call or Messages SharePlay", value: groupState.isEligibleForGroupSession ? "Active" : "None")
            LabeledContent("Session", value: sharePlay.state.title)
            if case .invalidated(let reason) = sharePlay.state {
                Text(reason).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            if sharePlay.state == .joined {
                LabeledContent("Participants", value: "\(sharePlay.participantCount)")
                LabeledContent("Group selection", value: sharePlay.sharedExperimentID.flatMap { ExperimentRegistry.descriptor(for: $0)?.name } ?? "None yet")
            }
            HStack {
                Button(sharePlay.isActivating ? "Starting…" : "Start Explore Together", action: sharePlay.startExploring)
                    .buttonStyle(.borderedProminent)
                    .disabled(sharePlay.isActivating || sharePlay.state == .joined)
                ShareLink(item: ExploreTogetherActivity(), preview: SharePreview("Explore Apple Toolbox together", image: Image(systemName: "shareplay"))) {
                    Label("Share Activity…", systemImage: "shareplay")
                }
                .buttonStyle(.bordered)
            }
            if sharePlay.state == .joined {
                Picker("Experiment", selection: $experimentID) {
                    ForEach(ExperimentRegistry.all) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Button("Send to Group") { sharePlay.send(experimentID) }
                        .buttonStyle(.bordered)
                    Button("Leave", action: sharePlay.leave)
                        .buttonStyle(.bordered)
                    Button("End for Everyone", role: .destructive, action: sharePlay.endForEveryone)
                        .buttonStyle(.bordered)
                }
            }
            OutputView(text: sharePlay.output, isError: sharePlay.isError)
            ForEach(log.entries(in: [.sharePlay])) { ActivityLogRow(entry: $0) }
            Text("While a session is joined, opening any experiment sends its ID with GroupSessionMessenger and every participant's app opens it too; late joiners receive the current one. Without a FaceTime call or Messages conversation, activate() cannot create a session; Share Activity lets the share sheet start one. The session stays active while you browse and ends with Leave or End for Everyone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ShareSummarySection: View {
    @State private var experimentID = "ecosystem-continuity"

    var body: some View {
        Section("Share · ShareLink and AirDrop") {
            Picker("Experiment", selection: $experimentID) {
                ForEach(ExperimentRegistry.all) { Text($0.name).tag($0.id) }
            }
            if let experiment = ExperimentRegistry.descriptor(for: experimentID) {
                let summary = ExperimentShareSummary.text(for: experiment, status: experiment.currentStatus, platform: CurrentPlatform.value)
                Text(summary).font(.caption.monospaced()).textSelection(.enabled)
                ShareLink(item: summary, subject: Text("Apple Toolbox · \(experiment.name)"),
                          preview: SharePreview(experiment.name, image: Image(systemName: experiment.category.symbolName))) {
                    Label("Share Summary…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            Text("ShareLink hands the text to the system share sheet; AirDrop appears there when a nearby device accepts it. Apps cannot start an AirDrop transfer themselves or see who received it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct UniversalLinksSection: View {
    @StateObject private var links = UniversalLinksService()

    var body: some View {
        Section("Universal Links · Associated Domains") {
            LabeledContent("com.apple.developer.associated-domains", value: links.state.title)
            Text(links.entitlementSummary).font(.caption)
            LabeledContent("This app's App ID") { Text(links.appID ?? "Unknown").font(.caption.monospaced()) }
            TextField("Domain, e.g. example.com", text: $links.host)
                .autocorrectionDisabled()
            Picker("Source", selection: $links.source) {
                ForEach(AASASource.allCases) { Text($0.rawValue).tag($0) }
            }
            Button(links.isChecking ? "Fetching…" : "Fetch apple-app-site-association", action: links.check)
                .buttonStyle(.borderedProminent)
                .disabled(links.isChecking || links.host.trimmingCharacters(in: .whitespaces).isEmpty)
            OutputView(text: links.output, isError: links.isError)
            Text("A Universal Link opens Apple Toolbox only when the app's Associated Domains entitlement lists applinks:<domain> and that domain serves an apple-app-site-association file over HTTPS, without redirects, that names the app's App ID. Devices read the file through Apple's CDN when the app is installed; ?mode=developer entries bypass the CDN on development devices. The app would then receive an NSUserActivityTypeBrowsingWeb activity. Apple Toolbox has no domain of its own, so no link can open it today.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear(perform: links.refresh)
    }
}
#endif
