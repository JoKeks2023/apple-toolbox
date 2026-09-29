import SwiftUI

struct KeychainSharingRunView: View {
    @StateObject private var sharing: KeychainSharingExperimentService

    init(experiment: ExperimentDescriptor) {
        _sharing = StateObject(wrappedValue: KeychainSharingExperimentService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        OutputView(text: sharing.groupSummary, isError: false)
            .onAppear(perform: sharing.inspect)
        Button("Check Access Groups", action: sharing.inspect)
        Picker("Access group", selection: $sharing.group) {
            ForEach(KeychainAccessGroupOption.allCases) { Text($0.title).tag($0) }
        }
        TextField("Value to store", text: $sharing.value)
        Toggle("Synchronize with iCloud Keychain", isOn: $sharing.synchronizable)
        HStack {
            Button("Save", action: sharing.save)
            Button("Read", action: sharing.read)
            Button("Delete", action: sharing.delete)
        }
        .buttonStyle(.borderedProminent)
        .disabled(sharing.isRunning)
        Button("List Items per Access Group", action: sharing.listItems)
            .disabled(sharing.isRunning)
        OutputView(text: sharing.output, isError: sharing.isError)
        Text("“Default group” saves without kSecAttrAccessGroup, so the result shows where the system puts such items. Only apps of the same team that list a group in their entitlements can share it.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct CredentialProviderRunView: View {
    @StateObject private var provider: CredentialProviderExperimentService

    init(experiment: ExperimentDescriptor) {
        _provider = StateObject(wrappedValue: CredentialProviderExperimentService(initialOutput: ExperimentOutput.initialMessage(for: experiment.currentStatus)))
    }

    var body: some View {
        OutputView(text: CredentialProviderExperimentService.boundarySummary, isError: false)
        Group {
            Button("Check Identity Store State", action: provider.checkStoreState)
                .buttonStyle(.borderedProminent)
            Button("Save a Demo Password Identity", action: provider.saveDemoIdentity)
            Button("Remove All Saved Identities", role: .destructive, action: provider.removeAllIdentities)
            Button("Ask to Turn On as AutoFill Provider", action: provider.requestTurnOn)
            Button("Open AutoFill Provider Settings", action: provider.openProviderSettings)
        }
        .disabled(provider.isRunning)
        OutputView(text: provider.output, isError: provider.isError)
        Text("A credential provider is an app extension (ASCredentialProviderViewController, extension point \(CredentialProviderExtensionScan.extensionPoint)) with the AutoFill Credential Provider entitlement. The person turns it on in Settings › General › AutoFill & Passwords; only then does the identity store accept this app's identities, and the system shows them in the QuickType bar. The app never sees other providers' credentials.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
