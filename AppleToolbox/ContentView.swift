import SwiftUI
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
#if canImport(MapKit) && !os(watchOS) && !os(tvOS)
import MapKit
#endif

struct ContentView: View {
    @State private var selectedCategory: ExperimentCategory?
    @State private var detailPath: [String] = []
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
            NavigationStack(path: $detailPath) {
                Group {
                    if let selectedCategory {
                        CategoryView(category: selectedCategory, experiments: experiments.filter { $0.category == selectedCategory })
                    } else { WelcomeView() }
                }
                .navigationDestination(for: String.self) { experimentID in
                    if let experiment = ExperimentRegistry.descriptor(for: experimentID) {
                        ExperimentDetailView(experiment: experiment)
                    } else {
                        ContentUnavailableView("Experiment unavailable", systemImage: "questionmark.circle")
                    }
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedCategory) { detailPath.removeAll() }
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
                NavigationLink(value: experiment.id) { ExperimentRow(experiment: experiment) }
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
    @State private var securityMessage = "Hello from Joris Apple Toolbox"
    @State private var keychainValue = "A secret I chose to store"
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
    @StateObject private var multipeer = MultipeerConnectivityExperimentService()
    @StateObject private var indoor = IndoorIMDFExperimentService()
    @StateObject private var ar = ARExperimentService()
    @StateObject private var speech = SpeechExperimentService()
    @StateObject private var music = MusicExperimentService()
    @StateObject private var health = HealthAuthorizationExperimentService()
    @StateObject private var notifications = NotificationExperimentService()
    @StateObject private var walletCreator = WalletPassCreatorService()
    @State private var showingIMDFImporter = false

    var body: some View {
        List {
            ExperimentHeroView(experiment: experiment, status: currentStatus)
            if let useCase = ExperimentUseCaseCatalog.forExperimentID(experiment.id) {
                UseCaseSection(useCase: useCase, experiment: experiment)
            }
            Section("Run") {
                if experiment.id == "core-location" {
                    HStack { Label("Authorization", systemImage: "location"); Spacer(); Text(location.authorization).foregroundStyle(.secondary) }
                    Button("Request Location Permission", action: location.requestPermission)
                    Button(location.isUpdating ? "Stop Live Updates" : "Start Live Updates") { location.isUpdating ? location.stop() : location.start() }.buttonStyle(.borderedProminent)
                    LocationReadingView(location: location)
                    OutputView(text: location.output, isError: location.output.localizedCaseInsensitiveContains("error") || location.output.localizedCaseInsensitiveContains("denied"))
                } else if experiment.id == "core-motion" {
                    Button(motion.isRunning ? "Stop Motion Updates" : "Start Motion Updates") { motion.isRunning ? motion.stop() : motion.start() }.buttonStyle(.borderedProminent)
                    MotionReadingView(motion: motion)
                    OutputView(text: motion.output, isError: motion.output.localizedCaseInsensitiveContains("not available") || motion.output.localizedCaseInsensitiveContains("error"))
                } else if experiment.id == "localauthentication" {
                    OutputView(text: AuthenticationService.availability(), isError: false)
                    Button("Authenticate with Face ID / Touch ID", action: run)
                        .buttonStyle(.borderedProminent).disabled(isRunning || currentStatus != .available)
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("error"))
                } else if experiment.id == "cryptokit" {
                    TextField("Message to hash or sign", text: $securityMessage)
                    Button("Hash with SHA-256") { output = CryptoService.hash(message: securityMessage) }
                    Button("Sign and Verify with P-256") { output = CryptoService.signAndVerify(message: securityMessage) }
                        .buttonStyle(.borderedProminent)
                    Button("Run Complete Crypto Experiment") { output = CryptoService.run(message: securityMessage) }
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "keychain" {
                    TextField("Value to store", text: $keychainValue)
                    HStack {
                        Button("Save", action: { output = KeychainService.save(value: keychainValue) })
                        Button("Read", action: { output = KeychainService.read() })
                        Button("Delete", action: { output = KeychainService.delete() })
                    }
                    .buttonStyle(.borderedProminent)
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("failed") || output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "secure-enclave" {
                    TextField("Message to sign", text: $securityMessage)
                    Button("Create key and sign message") {
                        do { output = try SecureEnclaveService.run(message: securityMessage) }
                        catch { output = "Error: \(error.localizedDescription)" }
                    }
                    .buttonStyle(.borderedProminent)
                    OutputView(text: output, isError: output.localizedCaseInsensitiveContains("error") || output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "network-path" {
                    Button(network.isMonitoring ? "Stop Network Monitor" : "Start Network Monitor") { network.isMonitoring ? network.stop() : network.start() }.buttonStyle(.borderedProminent)
                    NetworkInterfacesView(interfaces: network.interfaces)
                    OutputView(text: network.output, isError: network.output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "core-bluetooth" {
                    HStack {
                        Button(bluetooth.isScanning ? "Stop Bluetooth Scan" : "Start Bluetooth Scan") { bluetooth.isScanning ? bluetooth.stop() : bluetooth.start() }.buttonStyle(.borderedProminent)
                        Button("Clear", action: bluetooth.clearResults).buttonStyle(.bordered)
                    }
                    BluetoothResultsView(peripherals: bluetooth.peripherals)
                    OutputView(text: bluetooth.output, isError: bluetooth.output.localizedCaseInsensitiveContains("not available") || bluetooth.output.localizedCaseInsensitiveContains("unauthorized"))
                } else if experiment.id == "core-nfc" {
                    Button(nfc.isScanning ? "Scanning…" : "Scan NFC Tag", action: nfc.start).buttonStyle(.borderedProminent).disabled(nfc.isScanning)
                    NFCRecordsView(records: nfc.records)
                    OutputView(text: nfc.output, isError: nfc.output.localizedCaseInsensitiveContains("not available") || nfc.output.localizedCaseInsensitiveContains("ended"))
                } else if experiment.id == "camera-vision" {
                    Button(media.isRunning ? "Stop Camera & Vision" : "Start Camera & Vision") { media.isRunning ? media.stop() : media.start() }.buttonStyle(.borderedProminent)
                    VisionResultsView(results: media.detectedTexts)
                    OutputView(text: media.output, isError: media.status != .available)
                } else if experiment.id == "audio-input" {
                    Button(audio.isRunning ? "Stop Audio Input" : "Start Audio Input") { audio.isRunning ? audio.stop() : audio.start() }.buttonStyle(.borderedProminent)
                    AudioMeterView(audio: audio)
                    OutputView(text: audio.output, isError: audio.status != .available)
                } else if experiment.id == "mapkit-search" {
                    TextField("Search places", text: $maps.query)
                    Button(maps.isSearching ? "Searching…" : "Search", action: maps.search).buttonStyle(.borderedProminent).disabled(maps.isSearching || maps.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    MapResultsView(results: maps.results)
                    OutputView(text: maps.output, isError: maps.output.localizedCaseInsensitiveContains("error") || maps.output.localizedCaseInsensitiveContains("not available"))
                } else if experiment.id == "homekit-discovery" {
                    Button("Refresh Homes and Accessories", action: home.refresh).buttonStyle(.borderedProminent)
                    HomeResultsView(homes: home.homes)
                    OutputView(text: home.output, isError: home.status == .unavailable)
                } else if experiment.id == "matter-status" {
                    Button("Inspect Matter Availability") { output = MatterExperimentService.statusText() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? MatterExperimentService.statusText() : output, isError: false)
                } else if experiment.id == "continuity" {
                    Button("Activate WatchConnectivity", action: continuity.activate).buttonStyle(.borderedProminent)
                    OutputView(text: continuity.output, isError: continuity.output.localizedCaseInsensitiveContains("error"))
                } else if experiment.id == "app-intents" {
                    Button("Refresh App Intents Report") { output = "App Intent registered: ToolboxStatusIntent\nUse Siri or Shortcuts to discover it." }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Use the button to inspect the registered App Intent." : output, isError: false)
                } else if experiment.id == "natural-language" {
                    TextField("Text to analyze", text: $ai.input, axis: .vertical)
                    Button("Analyze Text", action: ai.analyze).buttonStyle(.borderedProminent).disabled(ai.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    OutputView(text: ai.output, isError: false)
                } else if experiment.id == "foundation-models" {
                    Button("Check Foundation Models Availability") { output = FoundationModelsExperimentService.statusText() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? FoundationModelsExperimentService.statusText() : output, isError: false)
                } else if experiment.id == "healthkit-status" {
                    Button("Request HealthKit Read Authorization", action: health.requestReadAuthorization).buttonStyle(.borderedProminent)
                    OutputView(text: health.output, isError: health.output.localizedCaseInsensitiveContains("error") || health.output.localizedCaseInsensitiveContains("not available") || health.output.localizedCaseInsensitiveContains("denied"))
                } else if experiment.id == "wallet-status" {
                    Button("Inspect Wallet Capability") { output = WalletExperimentService.statusText() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? WalletExperimentService.statusText() : output, isError: false)
                } else if experiment.id == "wallet-creator" {
                    TextField("Pass name", text: $walletCreator.passName)
                    TextField("Organization", text: $walletCreator.organizationName)
                    TextField("Serial number", text: $walletCreator.serialNumber)
                    Button("Create Wallet Pass Draft", action: walletCreator.createDraft).buttonStyle(.borderedProminent)
                    #if !os(tvOS)
                    if let draftURL = walletCreator.draftURL {
                        ShareLink(item: draftURL) { Label("Share pass.json draft", systemImage: "square.and.arrow.up") }
                    }
                    #endif
                    OutputView(text: walletCreator.output, isError: walletCreator.output.localizedCaseInsensitiveContains("could not"))
                } else if experiment.id == "notifications" {
                    HStack {
                        Button("Request Notification Authorization", action: notifications.requestAuthorization).buttonStyle(.borderedProminent)
                        Button("Schedule Test Notification", action: notifications.scheduleTestNotification).buttonStyle(.bordered)
                    }
                    OutputView(text: notifications.output, isError: notifications.output.localizedCaseInsensitiveContains("error") || notifications.output.localizedCaseInsensitiveContains("denied"))
                } else if experiment.id == "app-attest" {
                    Button("Check App Attest Boundary") { output = IdentitySecurityExperimentService.appAttestStatus() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect App Attest support." : output, isError: false)
                } else if experiment.id == "passkeys" {
                    Button("Check Passkey Configuration") { output = IdentitySecurityExperimentService.passkeyStatus() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect the passkey boundary." : output, isError: false)
                } else if experiment.id == "sign-in-with-apple" {
                    Button("Check Sign in with Apple") { output = IdentitySecurityExperimentService.signInWithAppleStatus() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect Sign in with Apple requirements." : output, isError: false)
                } else if experiment.id == "capability-explorer" {
                    Button("Refresh Device and Capability Report", action: { output = CapabilityExplorerService.report() }).buttonStyle(.borderedProminent)
                    OutputView(text: output, isError: false)
                } else if experiment.id == "widgetkit" {
                    Button("Inspect Widget Extension") { output = "WidgetKit extension is included in the iOS app.\nAdd “Apple Toolbox” from the Home Screen widget gallery." }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect the WidgetKit experiment." : output, isError: false)
                } else if experiment.id == "nearby-interaction" {
                    if nearby.isRunning {
                        Button("Stop Nearby Interaction", action: nearby.stop).buttonStyle(.borderedProminent)
                    } else {
                        Button("Inspect Nearby Interaction", action: nearby.start).buttonStyle(.borderedProminent)
                    }
                    OutputView(text: nearby.output, isError: nearby.output.localizedCaseInsensitiveContains("error") || nearby.output.localizedCaseInsensitiveContains("not supported"))
                } else if experiment.id == "multipeer-connectivity" {
                    MultipeerUseCaseView(service: multipeer)
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
                    Button("Check RoomPlan Hardware") { output = RoomPlanExperimentService.statusText() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? RoomPlanExperimentService.statusText() : output, isError: false)
                } else if experiment.id == "speech" {
                    if speech.isRunning { Button("Stop Speech Recognition", action: speech.stop).buttonStyle(.borderedProminent) }
                    else { Button("Start Speech Recognition", action: speech.start).buttonStyle(.borderedProminent) }
                    OutputView(text: speech.output, isError: speech.output.localizedCaseInsensitiveContains("error") || speech.output.localizedCaseInsensitiveContains("denied"))
                } else if experiment.id == "core-ml" {
                    Button("Inspect Core ML Availability") { output = AIAvailabilityExperimentService.coreMLStatus() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect Core ML." : output, isError: false)
                } else if experiment.id == "translation" {
                    Button("Inspect Translation Availability") { output = AIAvailabilityExperimentService.translationStatus() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect Translation." : output, isError: false)
                } else if experiment.id == "sound-analysis" {
                    Button("Inspect Sound Analysis") { output = AIAvailabilityExperimentService.soundAnalysisStatus() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect Sound Analysis." : output, isError: false)
                } else if experiment.id == "musickit" {
                    Button("Request MusicKit Authorization", action: music.requestAuthorization).buttonStyle(.borderedProminent)
                    OutputView(text: music.output, isError: music.output.localizedCaseInsensitiveContains("denied") || music.output.localizedCaseInsensitiveContains("restricted"))
                } else if experiment.id == "shazamkit" {
                    Button("Check ShazamKit Session") { output = ShazamExperimentService.statusText() }.buttonStyle(.borderedProminent)
                    OutputView(text: output == "No run yet." ? "Press the button to inspect ShazamKit." : output, isError: false)
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
        #if canImport(UniformTypeIdentifiers) && !os(tvOS)
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

private struct BluetoothResultsView: View {
    let peripherals: [BluetoothPeripheralResult]

    var body: some View {
        Section("Discovered peripherals (\(peripherals.count))") {
            if peripherals.isEmpty {
                Label("No peripherals discovered yet", systemImage: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.secondary)
                Text("Start a scan and keep this screen open. Results update live as advertisements arrive.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(peripherals) { peripheral in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label(peripheral.name, systemImage: "dot.radiowaves.left.and.right")
                                .font(.headline)
                            Spacer()
                            Text("\(peripheral.rssi) dBm")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(peripheral.rssi >= -60 ? .green : .secondary)
                        }
                        Text(peripheral.id.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(peripheral.advertisedServices.isEmpty ? "No advertised services" : "Services: \(peripheral.advertisedServices.joined(separator: ", "))")
                            Spacer()
                            if peripheral.manufacturerDataBytes > 0 {
                                Text("Manufacturer: \(peripheral.manufacturerDataBytes) B")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct NetworkInterfacesView: View {
    let interfaces: [NetworkInterfaceResult]

    var body: some View {
        Section("Available interfaces") {
            if interfaces.isEmpty {
                Text("Start the monitor to inspect the current network path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(interfaces) { interface in
                    Label {
                        VStack(alignment: .leading) {
                            Text(interface.name)
                            Text(interface.type).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: interface.type.localizedCaseInsensitiveContains("wifi") ? "wifi" : "network")
                    }
                }
            }
        }
    }
}

private struct VisionResultsView: View {
    let results: [VisionTextResult]

    var body: some View {
        Section("Recognized text") {
            if results.isEmpty {
                Text("Start the camera and point it at readable text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { result in
                    HStack {
                        Text(result.text)
                        Spacer()
                        Text("\(Int(result.confidence * 100))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct MapResultsView: View {
    let results: [MapSearchResult]

    var body: some View {
        Section("Map results ((results.count))") {
            if results.isEmpty {
                Text("Search for a place to inspect real MKMapItem results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(result.name, systemImage: "mappin.and.ellipse")
                            .font(.headline)
                        if !result.address.isEmpty { Text(result.address).font(.subheadline) }
                        Text(result.coordinate).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct HomeResultsView: View {
    let homes: [HomeSummary]

    var body: some View {
        Section("HomeKit homes (\(homes.count))") {
            if homes.isEmpty {
                Text("Refresh to inspect homes shared with this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(homes) { home in
                    HStack {
                        Label(home.name, systemImage: "house")
                        Spacer()
                        Text("\(home.rooms) rooms · \(home.accessories) accessories")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

#if canImport(MapKit) && !os(watchOS) && !os(tvOS)
private struct LocationMapView: View {
    let coordinate: LocationCoordinate?
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 51.1657, longitude: 10.4515),
        span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
    )

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: markerItems) { marker in
            MapMarker(coordinate: marker.coordinate, tint: .red)
        }
        .overlay(alignment: .topLeading) {
            Label(coordinate == nil ? "Waiting for location" : "Live position", systemImage: coordinate == nil ? "location.slash" : "location.fill")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.regularMaterial, in: Capsule())
                .padding(10)
        }
        .onChange(of: coordinate) { _, newValue in
            guard let newValue else { return }
            withAnimation(.easeInOut(duration: 0.35)) {
                region = MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: newValue.latitude, longitude: newValue.longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                )
            }
        }
    }

    private var markerItems: [LocationMapMarker] {
        guard let coordinate else { return [] }
        return [LocationMapMarker(coordinate: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude))]
    }
}

private struct LocationMapMarker: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}
#endif

private struct AudioMeterView: View {
    @ObservedObject var audio: AudioExperimentService

    var body: some View {
        Section("Live microphone meter") {
            LabeledContent("Channels", value: audio.channelCount == 0 ? "—" : "\(audio.channelCount)")
            LabeledContent("Sample rate", value: audio.sampleRate == 0 ? "—" : "\(audio.sampleRate) Hz")
            LevelRow(title: "RMS", value: audio.rmsLevel)
            LevelRow(title: "Peak", value: audio.peakLevel)
            AudioLevelChart(levels: audio.levelHistory)
                .frame(height: 110)
            Text("Speak or make a sound near the microphone to see the levels move.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LevelRow: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.formatted(.number.precision(.fractionLength(4))))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(value, 0), 1))
                .tint(value > 0.8 ? .red : .accentColor)
        }
    }
}

private struct AudioLevelChart: View {
    let levels: [Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Peak history")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { proxy in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(level > 0.8 ? Color.red : Color.accentColor)
                            .frame(maxWidth: .infinity, minHeight: 3, maxHeight: max(3, proxy.size.height * min(level, 1)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            .padding(8)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct NFCRecordsView: View {
    let records: [NFCRecordResult]

    var body: some View {
        Section("NDEF records (\(records.count))") {
            if records.isEmpty {
                Text("Scan a physical NFC tag to inspect its records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.type)
                            .font(.headline)
                        Text("Format \(record.format) · Payload \(record.payloadBytes) bytes")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
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

private struct InfoChip: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
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

private struct MultipeerUseCaseView: View {
    @ObservedObject var service: MultipeerConnectivityExperimentService
    @State private var message = "Hello from Apple Toolbox"

    var body: some View {
        if service.isRunning {
            LabeledContent("Connected peers", value: service.connectedPeers.isEmpty ? "None yet" : service.connectedPeers.joined(separator: ", "))
            if !service.discoveredPeers.isEmpty {
                LabeledContent("Discovered peers", value: service.discoveredPeers.joined(separator: ", "))
            }
            TextField("Message to send", text: $message)
            HStack {
                Button("Send to connected peers") { service.send(message: message) }
                    .buttonStyle(.borderedProminent)
                Button("Stop", action: service.stop)
                    .buttonStyle(.bordered)
            }
        } else {
            Button("Discover nearby devices", action: service.start)
                .buttonStyle(.borderedProminent)
        }
        OutputView(text: service.output, isError: service.output.localizedCaseInsensitiveContains("could not") || service.output.localizedCaseInsensitiveContains("not supported") || service.output.localizedCaseInsensitiveContains("no connected"))
    }
}

private struct LocationReadingView: View {
    @ObservedObject var location: LocationExperimentService

    var body: some View {
        Section("Live reading") {
            #if canImport(MapKit) && !os(watchOS) && !os(tvOS)
            LocationMapView(coordinate: location.coordinateValue)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            #endif
            LabeledContent("Coordinate", value: location.coordinate)
            LabeledContent("Accuracy", value: location.accuracy)
            LabeledContent("Altitude", value: location.altitude)
            LabeledContent("Speed", value: location.speed)
            LabeledContent("Course", value: location.course)
            LabeledContent("Heading", value: location.heading)
        }
    }
}

private struct MotionReadingView: View {
    @ObservedObject var motion: MotionExperimentService

    var body: some View {
        Section("Live vectors · x  ·  y  ·  z") {
            VectorRow(title: "User acceleration", symbol: "figure.run", vector: motion.userAcceleration, unit: "g")
            VectorRow(title: "Rotation rate", symbol: "rotate.3d", vector: motion.rotationRate, unit: "rad/s")
            VectorRow(title: "Gravity", symbol: "arrow.down", vector: motion.gravity, unit: "g")
            if let lastUpdated = motion.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Start updates and move the device to see live values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct VectorRow: View {
    let title: String
    let symbol: String
    let vector: MotionVector
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.headline)
            Text("\(vector.formattedValues) \(unit)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
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
    var body: some View {
        #if os(tvOS)
        Text(text).font(.system(.body, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(12).background((isError ? Color.red : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        #else
        Text(text).font(.system(.body, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12).background((isError ? Color.red : Color.secondary).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        #endif
    }
}
private struct StatusBadge: View {
    let status: ExperimentStatus
    var body: some View { Text(status.title).font(.caption.weight(.semibold)).foregroundStyle(status == .available ? .green : .orange).padding(.horizontal, 8).padding(.vertical, 4).background(.quaternary, in: Capsule()) }
}
