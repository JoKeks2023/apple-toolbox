import SwiftUI

struct MapKitSearchRunView: View {
    @StateObject private var maps = MapExperimentService()

    var body: some View {
        TextField("Search places", text: $maps.query)
        Button(maps.isSearching ? "Searching…" : "Search", action: maps.search).buttonStyle(.borderedProminent).disabled(maps.isSearching || maps.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        MapResultsView(results: maps.results)
        OutputView(text: maps.output, isError: maps.output.localizedCaseInsensitiveContains("error") || maps.output.localizedCaseInsensitiveContains("not available"))
    }
}

struct WalletPassCreatorRunView: View {
    @StateObject private var walletCreator = WalletPassCreatorService()

    var body: some View {
        Picker("Pass style", selection: $walletCreator.style) {
            ForEach(WalletPassStyle.allCases) { Text($0.title).tag($0) }
        }
        if walletCreator.style == .boardingPass {
            Picker("Transit type", selection: $walletCreator.transitType) {
                ForEach(WalletTransitType.allCases) { Text($0.title).tag($0) }
            }
        }
        TextField("Pass name", text: $walletCreator.passName)
        TextField("Organization", text: $walletCreator.organizationName)
        TextField("Serial number", text: $walletCreator.serialNumber)
        Section("Relevance (optional)") {
            Toggle("Location", isOn: $walletCreator.includeLocation)
            if walletCreator.includeLocation {
                TextField("Latitude", value: $walletCreator.latitude, format: .number)
                TextField("Longitude", value: $walletCreator.longitude, format: .number)
            }
            Toggle("iBeacon", isOn: $walletCreator.includeBeacon)
            if walletCreator.includeBeacon {
                TextField("Proximity UUID", text: $walletCreator.beaconUUID).font(.body.monospaced()).autocorrectionDisabled()
                TextField("Major", value: $walletCreator.beaconMajor, format: .number)
                TextField("Minor", value: $walletCreator.beaconMinor, format: .number)
            }
            Toggle("Relevant date", isOn: $walletCreator.includeRelevantDate)
            #if !os(tvOS)
            if walletCreator.includeRelevantDate {
                DatePicker("Date", selection: $walletCreator.relevantDate)
            }
            #endif
        }
        Section("Server-only keys") {
            Text(WalletPassJSON.serverOnlyKeys).font(.caption).foregroundStyle(.secondary)
        }
        Button("Create Wallet Pass Draft", action: walletCreator.createDraft).buttonStyle(.borderedProminent)
        #if !os(tvOS)
        if let draftURL = walletCreator.draftURL {
            ShareLink(item: draftURL) { Label("Share pass.json draft", systemImage: "square.and.arrow.up") }
        }
        #endif
        OutputView(text: walletCreator.output, isError: walletCreator.isError)
        Section("Pass library changes") {
            Button(walletCreator.isObserving ? "Stop Observing" : "Observe PKPassLibraryDidChange") {
                walletCreator.isObserving ? walletCreator.stopObserving() : walletCreator.startObserving()
            }
            .experimentSession(walletCreator)
            ForEach(walletCreator.libraryChanges) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.date, style: .time).font(.caption2).foregroundStyle(.secondary)
                    Text(change.summary).font(.caption)
                }
            }
        }
    }
}

struct AppIntentsRunView: View {
    @StateObject private var intents = AppIntentsExperimentService()

    var body: some View {
        LabeledContent("Registered App Shortcuts", value: "\(intents.registeredCount)")
        TextField("Text to hash", text: $intents.text)
        Picker("Category", selection: $intents.category) {
            ForEach(ExperimentCategory.allCases) { Text($0.rawValue).tag($0) }
        }
        Picker("Experiment", selection: $intents.experimentID) {
            ForEach(ExperimentRegistry.all) { Text($0.name).tag($0.id) }
        }
        ForEach(intents.shortcuts) { shortcut in
            VStack(alignment: .leading, spacing: 6) {
                Label(shortcut.title, systemImage: shortcut.symbol).font(.headline)
                Text(shortcut.summary).font(.caption).foregroundStyle(.secondary)
                Text("“\(shortcut.phrase)”").font(.caption.italic())
                Button(intents.running == shortcut.id ? "Running…" : shortcut.opensApp ? "Run perform() · navigates" : "Run perform()") { intents.run(shortcut) }
                    .buttonStyle(.bordered)
                    .disabled(intents.running != nil)
            }
            .padding(.vertical, 4)
        }
        OutputView(text: intents.output, isError: intents.isError)
    }
}

private struct MapResultsView: View {
    let results: [MapSearchResult]

    var body: some View {
        Section("Map results (\(results.count))") {
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
