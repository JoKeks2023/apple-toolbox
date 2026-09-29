import SwiftUI
import AppIntents

// Compact watch run views for Location, Health, Home, AI, Audio and Developer experiments.

struct WatchLocationView: View {
    @StateObject private var location = LocationExperimentService()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            LabeledContent("Access", value: location.authorization)
            if !location.isAuthorized {
                Button("Request Access", systemImage: "location", action: location.requestPermission)
            }
            Button(location.isUpdating ? "Stop Updates" : "Start Updates", systemImage: location.isUpdating ? "stop.fill" : "location.fill") {
                location.isUpdating ? location.stopUpdates() : location.startUpdates()
            }
            Section("Live") {
                WatchFactRow(title: "Coordinate", text: location.coordinate)
                LabeledContent("Accuracy", value: location.accuracy)
                LabeledContent("Precision", value: location.accuracyAuthorization)
                LabeledContent("Altitude", value: location.altitude)
                LabeledContent("Speed", value: location.speed)
                LabeledContent("Course", value: location.course)
                LabeledContent("Floor", value: location.floorLevel)
            }
            Section {
                LabeledContent("True", value: location.trueHeading)
                LabeledContent("Magnetic", value: location.magneticHeading)
                LabeledContent("Accuracy", value: location.headingAccuracy)
            } header: {
                Text("Heading")
            } footer: {
                Text(location.headingService.detail + ". Region monitoring, visits and significant changes are not available on watchOS.")
            }
            WatchOutput(text: location.output, isError: location.output.localizedCaseInsensitiveContains("denied") || location.output.localizedCaseInsensitiveContains("error"))
        }
        .navigationTitle("Location")
        .onDisappear { location.stop() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { location.stop() }
        }
    }
}

struct WatchHealthReaderView: View {
    @StateObject private var health = HealthKitReaderService(initialOutput: "Pick a data set, request read access, then read what this watch stores.")

    var body: some View {
        List {
            Picker("Data set", selection: $health.preset) {
                ForEach(HealthReaderPreset.allCases) { Text($0.title).tag($0) }
            }
            Button("Request Read Access", systemImage: "heart.text.square", action: health.requestAuthorization)
                .disabled(health.isRequesting)
            Button(health.isReading ? "Reading…" : "Read Recent", systemImage: "arrow.down.doc", action: health.readRecent)
                .disabled(health.isReading)
            WatchFactRow(title: "Request status", text: health.requestStatus)
            ForEach(health.groups) { group in
                Section(group.title) {
                    ForEach(group.rows) { row in
                        VStack(alignment: .leading, spacing: 1) {
                            LabeledContent(row.title, value: row.value)
                            if !row.detail.isEmpty { Text(row.detail).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    if let note = group.note { WatchOutput(text: note) }
                }
            }
            Section {
                WatchOutput(text: health.output, isError: health.isError)
            } footer: {
                Text("Apple Watch keeps a shorter Health history than the paired iPhone, so older samples may only exist there.")
            }
        }
        .navigationTitle("HealthKit")
        .onAppear(perform: health.checkRequestStatus)
    }
}

struct WatchHomeKitView: View {
    @StateObject private var inspector = HomeInspectorService(initialOutput: "Load the homes to list accessories and scenes.")

    var body: some View {
        List {
            Button(inspector.isLoaded ? "Reload Homes" : "Load Homes", systemImage: "house", action: inspector.load)
                .onAppear(perform: inspector.loadIfPreviouslyAuthorized)
            if !inspector.homes.isEmpty {
                Picker("Home", selection: Binding(get: { inspector.selectedHomeID }, set: inspector.selectHome)) {
                    ForEach(inspector.homes) { home in
                        Text(home.name).tag(Optional(home.id))
                    }
                }
            }
            if let home = inspector.home {
                LabeledContent("Hub", value: home.hubState)
                Section("Accessories · \(home.accessories.count)") {
                    ForEach(inspector.filteredAccessories) { accessory in
                        NavigationLink {
                            WatchHomeAccessoryView(inspector: inspector, accessoryID: accessory.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(accessory.name)
                                Text("\(accessory.roomName) · \(accessory.isReachable ? "reachable" : "not reachable")")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !home.scenes.isEmpty {
                    Section("Scenes") {
                        ForEach(home.scenes) { scene in
                            WatchHomeSceneRow(inspector: inspector, scene: scene)
                        }
                    }
                }
            }
            WatchOutput(text: inspector.output, isError: inspector.isError)
        }
        .navigationTitle("Home")
    }
}

private struct WatchHomeSceneRow: View {
    @ObservedObject var inspector: HomeInspectorService
    let scene: HomeSceneInfo
    @State private var confirming = false

    var body: some View {
        Button {
            scene.needsConfirmation ? (confirming = true) : inspector.runScene(scene.id)
        } label: {
            LabeledContent(scene.name, value: inspector.runningScenes.contains(scene.id) ? "Running…" : "\(scene.actions.count) action(s)")
        }
        .disabled(inspector.runningScenes.contains(scene.id))
        .confirmationDialog("Run \(scene.name)? It changes a lock, door or security system.", isPresented: $confirming) {
            Button("Run Scene", role: .destructive) { inspector.runScene(scene.id) }
        }
    }
}

/// One accessory: every characteristic with its live value; switches and other Boolean values can be toggled.
private struct WatchHomeAccessoryView: View {
    @ObservedObject var inspector: HomeInspectorService
    let accessoryID: UUID

    var body: some View {
        List {
            if let accessory = inspector.accessory, accessory.id == accessoryID {
                LabeledContent("Category", value: accessory.category)
                LabeledContent("Reachable", value: accessory.isReachable ? "Yes" : "No")
                if let manufacturer = accessory.manufacturer { LabeledContent("Maker", value: manufacturer) }
                ForEach(accessory.services.filter(\.isUserInteractive)) { service in
                    Section(service.name) {
                        ForEach(service.characteristics) { characteristic in
                            WatchHomeCharacteristicRow(inspector: inspector, characteristic: characteristic)
                        }
                    }
                }
                Button("Read All", systemImage: "arrow.clockwise", action: inspector.readAll)
            } else {
                ProgressView()
            }
            WatchOutput(text: inspector.output, isError: inspector.isError)
        }
        .navigationTitle(inspector.accessory?.name ?? "Accessory")
        .onAppear { inspector.selectAccessory(accessoryID) }
    }
}

private struct WatchHomeCharacteristicRow: View {
    @ObservedObject var inspector: HomeInspectorService
    let characteristic: HomeCharacteristicInfo

    var body: some View {
        let busy = inspector.pending.contains(characteristic.id)
        if characteristic.isWritable, !characteristic.needsConfirmation, case .toggle? = HomeInspectorFormat.control(for: characteristic, allowsSlider: false) {
            Toggle(characteristic.name, isOn: Binding(
                get: { characteristic.value?.boolValue ?? false },
                set: { inspector.write(.bool($0), to: characteristic.id) }))
                .disabled(busy)
        } else {
            LabeledContent(characteristic.name, value: busy ? "…" : characteristic.valueText)
        }
    }
}

struct WatchNaturalLanguageView: View {
    @StateObject private var language = NaturalLanguageExperimentService()

    var body: some View {
        List {
            Picker("Analysis", selection: $language.mode) {
                ForEach(NLAnalysisMode.allCases) { Text($0.rawValue).tag($0) }
            }
            if language.mode == .embeddings {
                TextField("First word", text: $language.firstTerm)
                TextField("Second word", text: $language.secondTerm)
            } else {
                TextField("Text", text: $language.input)
            }
            Button(language.isAnalyzing ? "Analyzing…" : "Analyze", systemImage: "text.magnifyingglass", action: language.analyze)
                .disabled(language.isAnalyzing)
            results
            WatchOutput(text: language.output, isError: language.isError)
        }
        .navigationTitle("Language")
    }

    @ViewBuilder private var results: some View {
        switch language.mode {
        case .language:
            ForEach(language.hypotheses) { guess in
                LabeledContent(guess.name, value: guess.probability.formatted(.percent.precision(.fractionLength(0))))
            }
        case .tokens:
            ForEach(language.tokens.prefix(40)) { token in Text(token.text).font(.caption) }
        case .tags:
            ForEach(language.taggedTokens.prefix(40)) { token in LabeledContent(token.text, value: token.tag) }
        case .sentiment:
            if let overall = language.overallSentiment {
                LabeledContent("Overall", value: NaturalLanguageFormat.sentimentLabel(for: overall))
            }
            ForEach(language.sentiments) { part in
                WatchFactRow(title: part.score.formatted(.number.precision(.fractionLength(2))), text: part.text)
            }
        case .lemmas:
            ForEach(language.lemmas.prefix(40)) { lemma in LabeledContent(lemma.word, value: lemma.lemma ?? "—") }
        case .embeddings:
            if let report = language.embeddingReport {
                ForEach(report.facts) { LabeledContent($0.title, value: $0.value) }
                ForEach(report.neighbors.prefix(5)) { LabeledContent($0.term, value: $0.distance.formatted(.number.precision(.fractionLength(3)))) }
            }
        }
    }
}

struct WatchMusicKitView: View {
    @StateObject private var music = MusicExperimentService()

    var body: some View {
        List {
            Section("Account") {
                LabeledContent("Access", value: music.authorization)
                if !music.isAuthorized {
                    Button("Request Access", systemImage: "music.note", action: music.requestAuthorization)
                }
                LabeledContent("Storefront", value: music.storefront ?? "—")
                LabeledContent("Catalog playback", value: music.canPlayCatalogContent.map { $0 ? "Allowed" : "Not allowed" } ?? "—")
                LabeledContent("Cloud library", value: music.hasCloudLibraryEnabled.map { $0 ? "On" : "Off" } ?? "—")
            }
            Picker("Source", selection: $music.source) {
                ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Type", selection: $music.kind) {
                ForEach(MusicItemKind.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField(music.source == .catalog ? "Search term" : "Filter (optional)", text: $music.term)
            Button(music.isLoading ? "Loading…" : "Load", systemImage: "magnifyingglass", action: music.load)
                .disabled(music.isLoading || !music.isAuthorized)
            ForEach(music.results) { row in
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).lineLimit(2)
                    Text(row.subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Section {
                WatchOutput(text: music.output, isError: music.isError)
            } footer: {
                Text("watchOS offers MusicKit's catalog and library requests, but no ApplicationMusicPlayer, so this app cannot play music on the watch.")
            }
        }
        .navigationTitle("MusicKit")
    }
}

struct WatchCapabilityExplorerView: View {
    @State private var report: DeviceScanReport?
    @State private var isScanning = false

    var body: some View {
        List {
            Button(isScanning ? "Scanning…" : "Rescan", systemImage: "arrow.clockwise") { Task { await scan() } }
                .disabled(isScanning)
            if let report {
                Text("\(report.count(.available)) available · \(report.count(.unavailable)) unavailable · \(report.count(.unknown)) unknown")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(report.sections) { section in
                    Section(section.title) {
                        ForEach(section.items) { item in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.state.marker) \(item.name)").font(.caption)
                                    .foregroundStyle(item.state == .available ? .green : item.state == .unavailable ? .red : .orange)
                                Text(item.detail).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Capabilities")
        .task { if report == nil { await scan() } }
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        report = await DeviceScanner.scan()
        isScanning = false
    }
}

/// Runs the App Intents the watch app registers by calling `perform()` in-process, as Siri or Shortcuts would.
struct WatchAppIntentsView: View {
    private enum WatchIntent: String, CaseIterable, Identifiable {
        case status = "Show Status", hash = "Hash Text", capabilities = "Device Capabilities"
        var id: String { rawValue }
    }

    @State private var text = "Apple Toolbox"
    @State private var output = "Run an intent to see the value its perform() returns."
    @State private var isError = false
    @State private var running: WatchIntent?

    var body: some View {
        List {
            LabeledContent("App Shortcuts", value: "\(ToolboxShortcuts.appShortcuts.count) registered")
            TextField("Text to hash", text: $text)
            ForEach(WatchIntent.allCases) { intent in
                Button(running == intent ? "Running…" : intent.rawValue, systemImage: "bolt.fill") { run(intent) }
                    .disabled(running != nil)
            }
            Section {
                WatchOutput(text: output, isError: isError)
            } footer: {
                Text("The watch app registers the status, hash and capability intents; opening a category or experiment is iPhone, iPad, Mac and Apple TV only.")
            }
        }
        .navigationTitle("App Intents")
    }

    private func run(_ intent: WatchIntent) {
        running = intent
        Task {
            do {
                let value: String = switch intent {
                case .status: try await ToolboxStatusIntent().perform().value ?? ""
                case .hash: try await HashTextIntent(text: text).perform().value ?? ""
                case .capabilities: try await CapabilitySummaryIntent().perform().value ?? ""
                }
                output = "\(intent.rawValue)\n\(value.isEmpty ? "perform() returned no value." : value)"
                isError = false
            } catch {
                output = "\(intent.rawValue) failed: \(error.localizedDescription)"
                isError = true
            }
            running = nil
        }
    }
}

struct WatchNotificationsView: View {
    @StateObject private var notifications = NotificationExperimentService()
    @ObservedObject private var log = NotificationEventLog.shared

    var body: some View {
        List {
            Picker("Authorization", selection: $notifications.authorizationChoice) {
                ForEach(NotificationAuthorizationChoice.allCases) { Text($0.title).tag($0) }
            }
            Button("Request Authorization", systemImage: "bell.badge", action: notifications.requestAuthorization)
            Picker("Category", selection: $notifications.category) {
                // The custom-UI category is drawn by the iOS notification content extension only.
                ForEach(ToolboxNotificationCategory.allCases.filter { $0 != .report }) { Text($0.title).tag($0) }
            }
            Picker("Level", selection: $notifications.interruption) {
                ForEach(NotificationInterruptionChoice.allCases) { Text($0.title).tag($0) }
            }
            Picker("Delay", selection: $notifications.delay) {
                ForEach(NotificationDelayChoice.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Image attachment", isOn: $notifications.includeAttachment)
            Button("Schedule", systemImage: "clock.badge", action: notifications.schedule)
            WatchOutput(text: notifications.output, isError: notifications.isError)
            Section("Settings") {
                ForEach(notifications.settings.rows) { LabeledContent($0.title, value: $0.value) }
                LabeledContent("Pending", value: "\(notifications.pending.count)")
                LabeledContent("Delivered", value: "\(notifications.delivered.count)")
            }
            Section {
                ForEach(log.events.prefix(8)) { event in
                    WatchFactRow(title: event.date.formatted(date: .omitted, time: .standard), text: event.title + "\n" + event.detail)
                }
            } header: {
                Text("Delegate log")
            } footer: {
                Text("Lower your wrist after scheduling to get the notification on the watch face; while the app is open, willPresent shows it as a banner.")
            }
        }
        .navigationTitle("Notifications")
        .onAppear {
            notifications.refresh()
            log.reload()
        }
    }
}
