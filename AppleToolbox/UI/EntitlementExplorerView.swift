import SwiftUI

/// Capability and entitlement state of the running app (spec §36). Reference data comes from
/// `CapabilityRegistry`, the current state only from the app's own embedded profile and Info.plist.
struct EntitlementExplorerView: View {
    @State private var lookup: ProvisioningLookup?
    @State private var searchText = ""

    var body: some View {
        List {
            ProfileSummarySection(lookup: lookup)
            if let lookup {
                ForEach(CapabilityKind.allCases) { kind in
                    let capabilities = matches(of: kind)
                    if !capabilities.isEmpty {
                        Section {
                            ForEach(capabilities) { capability in
                                NavigationLink(value: CapabilityRoute(id: capability.id)) {
                                    CapabilityRow(capability: capability, state: ProvisioningInspector.state(of: capability, in: lookup))
                                }
                            }
                        } header: {
                            Label(kind.rawValue, systemImage: kind.symbolName)
                        } footer: {
                            Text(kind.summary)
                        }
                    }
                }
                if !searchText.isEmpty, CapabilityKind.allCases.allSatisfy({ matches(of: $0).isEmpty }) {
                    ContentUnavailableView.search(text: searchText)
                }
                if let profile = lookup.profile { OtherEntitlementsSection(profile: profile) }
            }
        }
        .navigationTitle("Entitlements")
        .searchable(text: $searchText, prompt: "Capability, key or framework")
        .navigationDestination(for: CapabilityRoute.self) { route in
            if let capability = CapabilityRegistry.descriptor(for: route.id), let lookup {
                CapabilityDetailView(capability: capability, state: ProvisioningInspector.state(of: capability, in: lookup))
            } else {
                ContentUnavailableView("Capability unavailable", systemImage: "questionmark.circle")
            }
        }
        .task { if lookup == nil { lookup = ProvisioningInspector.load() } }
    }

    private func matches(of kind: CapabilityKind) -> [CapabilityDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        return CapabilityRegistry.capabilities(of: kind)
            .filter { query.isEmpty || ([$0.name, $0.framework] + $0.keys).contains { $0.localizedCaseInsensitiveContains(query) } }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct CapabilityRoute: Hashable {
    let id: String
}

private struct ProfileSummarySection: View {
    let lookup: ProvisioningLookup?

    var body: some View {
        Section {
            switch lookup {
            case nil:
                ProgressView("Reading embedded profile…")
            case .found(let profile)?:
                Label("Embedded provisioning profile", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                LabeledContent("Name", value: profile.name)
                LabeledContent("Team", value: [profile.teamName, profile.teamIdentifier.map { "(\($0))" }].compactMap { $0 }.joined(separator: " "))
                if let appIDName = profile.appIDName { LabeledContent("App ID", value: appIDName) }
                if !profile.platforms.isEmpty { LabeledContent("Platforms", value: profile.platforms.joined(separator: ", ")) }
                if let expirationDate = profile.expirationDate {
                    LabeledContent(profile.isExpired ? "Expired" : "Expires") {
                        Text(expirationDate, format: .dateTime.day().month().year()).foregroundStyle(profile.isExpired ? .red : .secondary)
                    }
                }
                LabeledContent("Devices", value: profile.provisionsAllDevices ? "All devices" : profile.provisionedDeviceCount.map { "\($0) registered" } ?? "Not limited to registered devices")
                LabeledContent("Entitlements", value: "\(profile.entitlements.count)")
            case .missing(let reason)?, .unreadable(let reason)?:
                Label("No readable provisioning profile", systemImage: "questionmark.diamond").foregroundStyle(.orange)
                Text(reason).foregroundStyle(.secondary)
                Text("Entitlement-based capabilities are shown as Unknown. Info.plist-based capabilities are still read from the bundle.").font(.footnote).foregroundStyle(.secondary)
            }
        } header: {
            Text("This app")
        } footer: {
            Text("Provisioned means the profile authorizes the key. The signed app may use only a subset, and permissions, hardware and region still decide whether an API works. Nothing here is requested, granted or simulated.")
        }
    }
}

private struct OtherEntitlementsSection: View {
    let profile: ProvisioningProfile

    var body: some View {
        let known = Set(CapabilityRegistry.all.flatMap(\.keys))
        let others = profile.entitlements.keys.filter { !known.contains($0) }.sorted()
        if !others.isEmpty {
            Section("Other keys in the profile") {
                ForEach(others, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(key).font(.caption.monospaced())
                        Text(profile.entitlements[key] ?? "").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct CapabilityRow: View {
    let capability: CapabilityDescriptor
    let state: ProvisioningState

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capability.name).font(.headline)
                Text(capability.keys.first ?? "No entitlement key").font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                if !capability.isSupportedOnCurrentPlatform {
                    Text("Not available on \(CurrentPlatform.value.rawValue)").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            ProvisioningStateBadge(state: state)
        }
        .padding(.vertical, 2)
    }
}

private struct ProvisioningStateBadge: View {
    let state: ProvisioningState

    var body: some View {
        Text(state.title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: Capsule())
    }

    private var color: Color {
        switch state {
        case .provisioned, .declared: .green
        case .notProvisioned, .notDeclared: .orange
        case .unknown: .secondary
        }
    }
}

private struct CapabilityKindBadge: View {
    let kind: CapabilityKind

    var body: some View {
        Label(kind.rawValue, systemImage: kind.symbolName)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.14), in: Capsule())
    }

    private var color: Color {
        switch kind {
        case .developerCapability: .blue
        case .managedCapability: .purple
        case .specialEntitlement: .yellow
        case .appleProgram: .pink
        case .hardwareDependent: .teal
        }
    }
}

private struct CapabilityDetailView: View {
    let capability: CapabilityDescriptor
    let state: ProvisioningState

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top) {
                        Text(capability.name).font(.title3.weight(.semibold))
                        Spacer(minLength: 8)
                        ProvisioningStateBadge(state: state)
                    }
                    CapabilityKindBadge(kind: capability.kind)
                    Text(capability.kind.summary).foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section("Requirements") {
                LabeledContent("Platform", value: capability.platforms.map(\.rawValue).joined(separator: ", "))
                LabeledContent("Region", value: capability.region ?? "No regional restriction listed")
                LabeledContent("Requires", value: capability.access.title)
                LabeledContent("Developer Program", value: capability.personalTeam ? "Not required (Personal Team works)" : "Required")
                if let hardware = capability.hardware { LabeledContent("Hardware", value: hardware) }
                LabeledContent("Framework", value: capability.framework)
            }
            Section("Current status") {
                LabeledContent("Status") { ProvisioningStateBadge(state: state) }
                if let value = presentValue {
                    Text(value).font(.system(.callout, design: .monospaced))
                }
                if !capability.isSupportedOnCurrentPlatform {
                    Text("Why this doesn't work here: \(capability.name) is not available on \(CurrentPlatform.value.rawValue).").foregroundStyle(.orange)
                }
                if case .unknown(let reason) = state { Text(reason).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next step").font(.subheadline.weight(.semibold))
                    Text(nextStep)
                }
            }
            Section("Key") {
                if capability.keys.isEmpty {
                    Text("No entitlement key").foregroundStyle(.secondary)
                } else {
                    ForEach(capability.keys, id: \.self) { Text($0).font(.system(.callout, design: .monospaced)) }
                }
                Text(sourceDescription).font(.footnote).foregroundStyle(.secondary)
            }
            if let experiment = capability.relatedExperiment {
                Section("Related experiment") {
                    NavigationLink(value: experiment.id) {
                        Label(experiment.name, systemImage: experiment.category.symbolName)
                    }
                }
            }
            Section("Documentation") {
                Link(destination: capability.documentationURL) { Label("Open Apple Developer Documentation", systemImage: "book.closed") }
            }
        }
        .navigationTitle(capability.name)
    }

    private var presentValue: String? {
        switch state {
        case .provisioned(let value), .declared(let value): value
        default: nil
        }
    }

    private var nextStep: String {
        switch state {
        case .provisioned: "Nothing to request. Keep the key in the app's entitlements file; runtime permissions and hardware checks still apply."
        case .declared: "Nothing to request. The bundle declares it; runtime checks still apply."
        default: capability.requirement
        }
    }

    private var sourceDescription: String {
        switch capability.keySource {
        case .provisioningProfile: "Entitlement. Listed in the provisioning profile once the capability is enabled on the App ID."
        case .codeSignature: "Entitlement that only the code signature carries; provisioning profiles do not list it."
        case .infoPlist: "Info.plist key, read from the app bundle."
        case .appIDOnly: "App ID setting without an entitlement key."
        }
    }
}
