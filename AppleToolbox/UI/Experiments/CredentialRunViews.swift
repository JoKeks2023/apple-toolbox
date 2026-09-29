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
            .onAppear {
                provider.checkStoreState()
                provider.listStoredIdentities()
            }
        Section("Identity store") {
            LabeledContent("isEnabled", value: provider.storeState.map { $0.isEnabled ? "true" : "false" } ?? "Not read yet")
            LabeledContent("supportsIncrementalUpdates", value: provider.storeState.map { $0.supportsIncrementalUpdates ? "true" : "false" } ?? "Not read yet")
            Group {
                Button("Check Identity Store State", action: provider.checkStoreState)
                    .buttonStyle(.borderedProminent)
                Button("Ask to Turn On as AutoFill Provider", action: provider.requestTurnOn)
                Button("Open AutoFill Provider Settings", action: provider.openProviderSettings)
            }
            .disabled(provider.isRunning)
            Text("Turn Apple Toolbox on in \(CredentialProviderExperimentService.settingsPath). Until then the store stays disabled and rejects every identity with storeDisabled.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Demo vault · App Group") {
            if provider.vault.passwords.isEmpty && provider.vault.passkeys.isEmpty {
                Text("Empty. Create the demo passwords; passkeys appear once the extension created one for a website.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(provider.vault.passwords) { credential in
                LabeledContent("\(credential.user) @ \(credential.domain)") { Text(credential.password).font(.caption.monospaced()) }
            }
            ForEach(provider.vault.passkeys) { passkey in
                LabeledContent("Passkey \(passkey.userName)", value: "\(passkey.relyingParty) · sign count \(passkey.signCount)")
            }
            Group {
                Button("Create Demo Passwords", action: provider.createDemoPasswords)
                Button("Save Identities to AutoFill", action: provider.saveDemoIdentities)
                    .buttonStyle(.borderedProminent)
                Button("Remove All Saved Identities", role: .destructive, action: provider.removeAllIdentities)
                Button("Reset Demo Data", role: .destructive, action: provider.resetDemoData)
            }
            .disabled(provider.isRunning)
        }
        Section("Identities in the store (\(provider.storedIdentities?.count ?? 0))") {
            if let identities = provider.storedIdentities {
                if identities.isEmpty { Text("None saved for this app's provider.").font(.caption).foregroundStyle(.secondary) }
                ForEach(identities, id: \.self) { Text($0).font(.caption.monospaced()) }
            }
            Button("List Stored Identities", systemImage: "arrow.clockwise", action: provider.listStoredIdentities)
        }
        OutputView(text: provider.output, isError: provider.isError)
        Section("Extension log") {
            if provider.vault.events.isEmpty {
                Text("The extension writes what it filled, signed or created here.").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(provider.vault.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.text).font(.caption)
                    Text(event.date.formatted(date: .abbreviated, time: .standard)).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Button("Re-read Vault", systemImage: "arrow.clockwise", action: provider.reloadVault)
        }
        Text("The provider is an app extension (ASCredentialProviderViewController, extension point \(CredentialProviderExtensionScan.extensionPoint)) with the AutoFill Credential Provider entitlement. With it turned on, a password field on example.com offers the demo accounts in the QuickType bar; on a WebAuthn test site, choose Apple Toolbox when the site offers to save a passkey, then sign in with it. The app never sees other providers' credentials.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
