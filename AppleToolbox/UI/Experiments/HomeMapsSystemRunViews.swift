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

struct ARKitRunView: View {
    @StateObject private var ar = ARExperimentService()

    var body: some View {
        Group {
            if ar.isRunning {
                Button("Stop ARKit", action: ar.stop).buttonStyle(.borderedProminent)
            } else {
                Button("Start ARKit", action: ar.start).buttonStyle(.borderedProminent)
            }
        }
        .experimentSession(ar)
        OutputView(text: ar.output, isError: ar.output.localizedCaseInsensitiveContains("error") || ar.output.localizedCaseInsensitiveContains("not supported"))
    }
}

struct NotificationsRunView: View {
    @StateObject private var notifications = NotificationExperimentService()

    var body: some View {
        HStack {
            Button("Request Notification Authorization", action: notifications.requestAuthorization).buttonStyle(.borderedProminent)
            Button("Schedule Test Notification", action: notifications.scheduleTestNotification).buttonStyle(.bordered)
        }
        OutputView(text: notifications.output, isError: notifications.output.localizedCaseInsensitiveContains("error") || notifications.output.localizedCaseInsensitiveContains("denied"))
    }
}

struct WalletPassCreatorRunView: View {
    @StateObject private var walletCreator = WalletPassCreatorService()

    var body: some View {
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

struct WidgetKitRunView: View {
    @StateObject private var widgets = WidgetKitExperimentService()

    var body: some View {
        HStack {
            Button(widgets.isLoading ? "Loading…" : "List Installed Widgets", action: widgets.refresh).buttonStyle(.borderedProminent).disabled(widgets.isLoading)
            Button("Reload Timelines", action: widgets.reloadTimelines).buttonStyle(.bordered)
        }
        Section("Installed widgets (\(widgets.configurations.count))") {
            if widgets.configurations.isEmpty {
                Text("List the installed widgets to see each configuration's kind and family.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(widgets.configurations) { configuration in
                    LabeledContent(configuration.kind, value: configuration.family)
                }
            }
        }
        OutputView(text: widgets.output, isError: widgets.isError)
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
