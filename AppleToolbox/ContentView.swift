import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

struct ContentView: View {
    @State private var selectedCategory: ExperimentCategory?
    private let experiments = ExperimentRegistry.all

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedCategory) {
                Section("Explore") {
                    ForEach(ExperimentCategory.allCases) { category in
                        let count = experiments.filter { $0.category == category }.count
                        NavigationLink(value: category) {
                            Label {
                                HStack { Text(category.rawValue); Spacer(); if count > 0 { Text("\(count)").foregroundStyle(.secondary) } }
                            } icon: { Image(systemName: category.symbolName).foregroundStyle(.tint) }
                        }
                    }
                }
            }
            .navigationTitle("Apple Toolbox")
        } detail: {
            if let selectedCategory {
                CategoryView(category: selectedCategory, experiments: experiments.filter { $0.category == selectedCategory })
            } else { WelcomeView() }
        }
        .navigationSplitViewStyle(.balanced)
    }
}

private struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Joris Apple Toolbox", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("A native laboratory for discovering what your Apple devices can actually do.")
        }
    }
}

private struct CategoryView: View {
    let category: ExperimentCategory
    let experiments: [ExperimentDescriptor]
    var body: some View {
        List {
            Section { Text("Foundation experiments for \(category.rawValue.lowercased()).").foregroundStyle(.secondary) }
            ForEach(experiments) { experiment in
                NavigationLink { ExperimentDetailView(experiment: experiment) } label: { ExperimentRow(experiment: experiment) }
            }
        }.navigationTitle(category.rawValue)
    }
}

private struct ExperimentRow: View {
    let experiment: ExperimentDescriptor
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: experiment.category.symbolName).font(.title3).frame(width: 34, height: 34)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(experiment.name).font(.headline)
                Text(experiment.frameworks.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); StatusBadge(status: experiment.currentStatus)
        }.padding(.vertical, 4)
    }
}

struct ExperimentDetailView: View {
    let experiment: ExperimentDescriptor
    @State private var output = "No run yet."
    @State private var isRunning = false
    @StateObject private var location = LocationExperimentService()
    @StateObject private var motion = MotionExperimentService()
    @StateObject private var network = NetworkExperimentService()
    @StateObject private var bluetooth = BluetoothExperimentService()
    @StateObject private var nfc = NFCExperimentService()
    @StateObject private var media = CameraVisionExperimentService()
    @StateObject private var audio = AudioExperimentService()
    @StateObject private var maps = MapExperimentService()
    @StateObject private var home = HomeExperimentService()
    @StateObject private var continuity = ContinuityExperimentService()
    @StateObject private var ai = AIExperimentService()
    @StateObject private var nearby = NearbyExperimentService()
    @StateObject private var indoor = IndoorIMDFExperimentService()
    @StateObject private var ar = ARExperimentService()
    @StateObject private var speech = SpeechExperimentService()
    @State private var showingIMDFImporter = false

    var body: some View {
        List {
            Section {
                Text(experiment.description)
                HStack { Text("Status"); Spacer(); StatusBadge(status: currentStatus) }
            }
            Section("Run") {
                if experiment.id == "core-location" {
                    HStack { Label("Authorization", systemImage: "location"); Spacer(); Text(location.authorization).foregroundStyle(.secondary) }
                    Button("Request Location Permission", action: location.requestPermission)
                    Button(location.isUpdating ? "Stop Live Updates" : "Start Live Updates") { location.isUpdating ? location.stop() : location.start() }.buttonStyle(.borderedProminent)
                    OutputView(text: location.output, isError: location.output.localizedCaseInsensitiveContains("error") || location.output.localizedCaseInsensitiveContains("denied"))
                } else if experiment.id == "core-motion" {
                    Button(motion.isRunning ? "Stop Motion Updates" : "Start Motion Updates") { motion.isRunning ? motion.stop() : motion.start() }.buttonStyle(.borderedProminent)
                    OutputView(text: motion.output, isError: motion.output.localizedCaseInsensitiveContains("not available") || motion.output.localizedCaseInsensitiveContains("error"))
                } else if experiment.id == "localauthentication" {
                    OutputView(text: AuthenticationService.availability(), isError: false)
                    Button("Authenticate with Face ID / Touch ID", action: run)
                        .buttonStyle(.borderedProminent).disabled(isRunning || currentStatus != .available)
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("error"))
                } else if experiment.id == "cryptokit" {
                    Button("Hash with SHA-256") { output = CryptoService.hash() }
                    Button("Sign and Verify with P-256") { output = CryptoService.signAndVerify() }
                        .buttonStyle(.borderedProminent)
                    Button("Run Complete Crypto Experiment") { output = CryptoService.run() }
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "keychain" {
                    HStack {
                        Button("Save", action: { output = KeychainService.save() })
                        Button("Read", action: { output = KeychainService.read() })
                        Button("Delete", action: { output = KeychainService.delete() })
                    }
                    .buttonStyle(.borderedProminent)
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("failed") || output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "network-path" {
                    Button(network.isMonitoring ? "Stop Network Monitor" : "Start Network Monitor") { network.isMonitoring ? network.stop() : network.start() }.buttonStyle(.borderedProminent)
                    OutputView(text: network.output, isError: network.output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "core-bluetooth" {
                    Button(bluetooth.isScanning ? "Stop Bluetooth Scan" : "Start Bluetooth Scan") { bluetooth.isScanning ? bluetooth.stop() : bluetooth.start() }.buttonStyle(.borderedProminent)
                    OutputView(text: bluetooth.output, isError: bluetooth.output.localizedCaseInsensitiveContains("not available") || bluetooth.output.localizedCaseInsensitiveContains("unauthorized"))
                } else if experiment.id == "core-nfc" {
                    Button(nfc.isScanning ? "Scanning…" : "Scan NFC Tag", action: nfc.start).buttonStyle(.borderedProminent).disabled(nfc.isScanning)
                    OutputView(text: nfc.output, isError: nfc.output.localizedCaseInsensitiveContains("not available") || nfc.output.localizedCaseInsensitiveContains("ended"))
                } else if experiment.id == "camera-vision" {
                    Button(media.isRunning ? "Stop Camera & Vision" : "Start Camera & Vision") { media.isRunning ? media.stop() : media.start() }.buttonStyle(.borderedProminent)
                    OutputView(text: media.output, isError: media.status != .available)
                } else if experiment.id == "audio-input" {
                    Button(audio.isRunning ? "Stop Audio Input" : "Start Audio Input") { audio.isRunning ? audio.stop() : audio.start() }.buttonStyle(.borderedProminent)
                    OutputView(text: audio.output, isError: audio.status != .available)
                } else if experiment.id == "mapkit-search" {
                    Button(maps.isSearching ? "Searching…" : "Search Apple Store Locations", action: maps.search).buttonStyle(.borderedProminent).disabled(maps.isSearching)
                    OutputView(text: maps.output, isError: maps.output.localizedCaseInsensitiveContains("error") || maps.output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "homekit-discovery" {
                    Button("Refresh Homes and Accessories", action: home.refresh).buttonStyle(.borderedProminent)
                    OutputView(text: home.output, isError: home.status == .unavailable)
                } else if experiment.id == "matter-status" {
                    OutputView(text: MatterExperimentService.statusText(), isError: false)
                } else if experiment.id == "continuity" {
                    Button("Activate WatchConnectivity", action: continuity.activate).buttonStyle(.borderedProminent)
                    OutputView(text: continuity.output, isError: continuity.output.localizedCaseInsensitiveContains("error"))
                } else if experiment.id == "app-intents" {
                    OutputView(text: "App Intent registered: ToolboxStatusIntent\nUse Siri or Shortcuts to discover it.", isError: false)
                } else if experiment.id == "natural-language" {
                    Button("Analyze Sample Text", action: ai.analyze).buttonStyle(.borderedProminent)
                    OutputView(text: ai.output, isError: false)
                } else if experiment.id == "foundation-models" {
                    OutputView(text: FoundationModelsExperimentService.statusText(), isError: false)
                } else if experiment.id == "healthkit-status" {
                    OutputView(text: HealthExperimentService.statusText(), isError: false)
                } else if experiment.id == "wallet-status" {
                    OutputView(text: WalletExperimentService.statusText(), isError: false)
                } else if experiment.id == "widgetkit" {
                    OutputView(text: "WidgetKit extension is included in the iOS app.\nAdd “Apple Toolbox” from the Home Screen widget gallery.", isError: false)
                } else if experiment.id == "nearby-interaction" {
                    if nearby.isRunning {
                        Button("Stop Nearby Interaction", action: nearby.stop).buttonStyle(.borderedProminent)
                    } else {
                        Button("Inspect Nearby Interaction", action: nearby.start).buttonStyle(.borderedProminent)
                    }
                    OutputView(text: nearby.output, isError: nearby.output.localizedCaseInsensitiveContains("error") || nearby.output.localizedCaseInsensitiveContains("not supported"))
                } else if experiment.id == "indoor-imdf" {
                    Button("Import IMDF JSON", action: { showingIMDFImporter = true }).buttonStyle(.borderedProminent)
                    OutputView(text: indoor.output, isError: indoor.status == .unavailable)
                } else if experiment.id == "arkit" {
                    if ar.isRunning {
                        Button("Stop ARKit", action: ar.stop).buttonStyle(.borderedProminent)
                    } else {
                        Button("Start ARKit", action: ar.start).buttonStyle(.borderedProminent)
                    }
                    OutputView(text: ar.output, isError: ar.output.localizedCaseInsensitiveContains("error") || ar.output.localizedCaseInsensitiveContains("not supported"))
                } else if experiment.id == "roomplan" {
                    OutputView(text: RoomPlanExperimentService.statusText(), isError: false)
                } else if experiment.id == "speech" {
                    if speech.isRunning { Button("Stop Speech Recognition", action: speech.stop).buttonStyle(.borderedProminent) }
                    else { Button("Start Speech Recognition", action: speech.start).buttonStyle(.borderedProminent) }
                    OutputView(text: speech.output, isError: speech.output.localizedCaseInsensitiveContains("error") || speech.output.localizedCaseInsensitiveContains("denied"))
                } else if experiment.id == "core-ml" {
                    OutputView(text: AIAvailabilityExperimentService.coreMLStatus(), isError: false)
                } else if experiment.id == "translation" {
                    OutputView(text: AIAvailabilityExperimentService.translationStatus(), isError: false)
                } else if experiment.id == "sound-analysis" {
                    OutputView(text: AIAvailabilityExperimentService.soundAnalysisStatus(), isError: false)
                } else {
                    Button(isRunning ? "Running…" : "Run Experiment", action: run).buttonStyle(.borderedProminent).disabled(isRunning || currentStatus != .available)
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("failed") || output.localizedCaseInsensitiveContains("not available") || output.localizedCaseInsensitiveContains("unsupported"))
                }
            }
            RequirementsView(experiment: experiment)
            Section("Documentation") { Link(destination: experiment.documentationURL) { Label("Open Apple Developer Documentation", systemImage: "book.closed") } }
        }
        .navigationTitle(experiment.name)
        .task { output = initialStatusMessage }
        #if canImport(UniformTypeIdentifiers)
        .fileImporter(isPresented: $showingIMDFImporter, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first { indoor.load(url: url) }
            if case .failure(let error) = result { output = "File import error: \(error.localizedDescription)" }
        }
        #endif
    }

    private var currentStatus: ExperimentStatus {
        if experiment.id == "core-location" { return location.status }
        if experiment.id == "core-motion" { return motion.status }
        return experiment.currentStatus
    }
    private var initialStatusMessage: String {
        switch currentStatus {
        case .hardwareUnsupported: "Why this doesn't work: required hardware is not available on this device or simulator."
        case .platformUnsupported: "Why this doesn't work: this experiment is not supported on the current platform."
        case .permissionRequired: "Permission has not been evaluated yet. Use the permission action above."
        default: "Ready. Results from the real system API will appear here."
        }
    }
    private func run() {
        isRunning = true
        Task {
            do {
                switch experiment.id {
                case "localauthentication": output = try await AuthenticationService.authenticate()
                case "cryptokit": output = CryptoService.run()
                case "keychain": output = KeychainService.run()
                case "secure-enclave": output = try SecureEnclaveService.run()
                default: output = "No run action is registered for this experiment."
                }
            } catch { output = "Error: \(error.localizedDescription)" }
            isRunning = false
        }
    }
}

private struct RequirementsView: View {
    let experiment: ExperimentDescriptor
    var body: some View {
        Section("Requirements") {
            RequirementLine(title: "Frameworks", value: experiment.frameworks.joined(separator: ", "))
            RequirementLine(title: "Platforms", value: experiment.supportedPlatforms.map(\.rawValue).joined(separator: " · "))
            RequirementLine(title: "Hardware", value: experiment.hardwareRequirements.isEmpty ? "None listed" : experiment.hardwareRequirements.joined(separator: ", "))
            RequirementLine(title: "OS", value: experiment.osRequirements.joined(separator: ", "))
            RequirementLine(title: "Permissions", value: experiment.permissions.isEmpty ? "None" : experiment.permissions.joined(separator: ", "))
            RequirementLine(title: "Capabilities", value: experiment.capabilities.isEmpty ? "None" : experiment.capabilities.joined(separator: ", "))
            RequirementLine(title: "Entitlements", value: experiment.entitlements.isEmpty ? "None" : experiment.entitlements.joined(separator: ", "))
        }
    }
}
private struct RequirementLine: View { let title: String; let value: String; var body: some View { LabeledContent(title, value: value) } }
private struct OutputView: View {
    let text: String; let isError: Bool
    var body: some View { Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).background((isError ? Color.red : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 10)) }
}
private struct StatusBadge: View {
    let status: ExperimentStatus
    var body: some View { Text(status.title).font(.caption.weight(.semibold)).foregroundStyle(status == .available ? .green : .orange).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule()) }
}
