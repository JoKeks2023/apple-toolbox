import Foundation
import Combine
#if canImport(AppIntents)
import AppIntents
#endif

#if !os(watchOS)
/// Navigation requested by an App Intent; `ContentView` applies it once the app is in the foreground.
@MainActor
final class ToolboxNavigator: ObservableObject {
    enum Request: Equatable {
        case category(ExperimentCategory)
        case experiment(String)
    }

    static let shared = ToolboxNavigator()
    @Published var request: Request?
}
#endif

#if canImport(AppIntents)
struct ToolboxStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Apple Toolbox Status"
    static let description = IntentDescription("Reports how many experiments are available on this device right now.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let statuses = ExperimentRegistry.all.map(\.currentStatus)
        let available = statuses.filter { $0 == .available }.count
        let summary = "\(available) of \(statuses.count) experiments are available on this \(CurrentPlatform.value.rawValue) device."
        let others = Dictionary(grouping: statuses.filter { $0 != .available }, by: \.title)
            .sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }
            .map { "\($0.key): \($0.value.count)" }
        return .result(value: ([summary] + others).joined(separator: "\n"), dialog: "\(summary)")
    }
}

struct HashTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Hash Text with SHA-256"
    static let description = IntentDescription("Computes the SHA-256 digest of a text with CryptoKit on this device and returns it as hex.")

    @Parameter(title: "Text", requestValueDialog: "Which text should be hashed?")
    var text: String

    static var parameterSummary: some ParameterSummary { Summary("Hash \(\.$text) with SHA-256") }

    init() {}
    init(text: String) { self.text = text }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        guard let digest = CryptoService.sha256Hex(text) else { throw ExperimentServiceError.unavailable("CryptoKit is not available on this platform.") }
        return .result(value: digest, dialog: "SHA-256: \(digest)")
    }
}

struct CapabilitySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "Summarize Device Capabilities"
    static let description = IntentDescription("Scans this device with public APIs and counts available, unavailable, and unknown capabilities per area.")

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let report = await DeviceScanner.scan()
        let summary = "\(report.platform): \(report.count(.available)) available, \(report.count(.unavailable)) unavailable, \(report.count(.unknown)) unknown."
        let sections = report.sections.map { section in
            "\(section.title): \(section.items.filter { $0.state == .available }.count) of \(section.items.count) available"
        }
        return .result(value: ([summary] + sections).joined(separator: "\n"), dialog: "\(summary)")
    }
}

#if !os(watchOS)
nonisolated extension ExperimentCategory: AppEnum {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Experiment Category"
    // App Intents reads these at build time, so they must stay literals.
    static let caseDisplayRepresentations: [ExperimentCategory: DisplayRepresentation] = [
        .security: DisplayRepresentation(title: "Security", image: .init(systemName: "lock.shield")),
        .location: DisplayRepresentation(title: "Location", image: .init(systemName: "location")),
        .sensors: DisplayRepresentation(title: "Sensors", image: .init(systemName: "waveform.path.ecg")),
        .connectivity: DisplayRepresentation(title: "Connectivity", image: .init(systemName: "point.3.connected.trianglepath.dotted")),
        .networking: DisplayRepresentation(title: "Networking", image: .init(systemName: "network")),
        .nfc: DisplayRepresentation(title: "NFC", image: .init(systemName: "wave.3.right")),
        .home: DisplayRepresentation(title: "Home", image: .init(systemName: "house")),
        .camera: DisplayRepresentation(title: "Camera", image: .init(systemName: "camera")),
        .audio: DisplayRepresentation(title: "Audio", image: .init(systemName: "waveform")),
        .ai: DisplayRepresentation(title: "AI", image: .init(systemName: "sparkles")),
        .maps: DisplayRepresentation(title: "Maps", image: .init(systemName: "map")),
        .wallet: DisplayRepresentation(title: "Wallet", image: .init(systemName: "wallet.pass")),
        .developer: DisplayRepresentation(title: "Developer", image: .init(systemName: "hammer")),
    ]
}

struct ExperimentEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Experiment"
    static let defaultQuery = ExperimentEntityQuery()

    let id: String
    let name: String
    let categoryName: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)", subtitle: "\(categoryName)") }

    @MainActor init(_ experiment: ExperimentDescriptor) {
        id = experiment.id
        name = experiment.name
        categoryName = experiment.category.rawValue
    }
}

struct ExperimentEntityQuery: EntityStringQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [ExperimentEntity] {
        identifiers.compactMap(ExperimentRegistry.descriptor(for:)).map(ExperimentEntity.init)
    }

    @MainActor func entities(matching string: String) async throws -> [ExperimentEntity] {
        ExperimentRegistry.all
            .filter { $0.name.localizedCaseInsensitiveContains(string) || $0.frameworks.contains { $0.localizedCaseInsensitiveContains(string) } }
            .map(ExperimentEntity.init)
    }

    @MainActor func suggestedEntities() async throws -> [ExperimentEntity] {
        ExperimentRegistry.all.map(ExperimentEntity.init)
    }
}

struct OpenCategoryIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Experiment Category"
    static let description = IntentDescription("Opens Apple Toolbox on the experiments of one category.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Category")
    var category: ExperimentCategory

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$category)") }

    init() {}
    init(category: ExperimentCategory) { self.category = category }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        ToolboxNavigator.shared.request = .category(category)
        let count = ExperimentRegistry.all.filter { $0.category == category }.count
        return .result(value: "Opened \(category.rawValue) with \(count) experiment(s).")
    }
}

struct OpenExperimentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Experiment"
    static let description = IntentDescription("Opens one experiment in Apple Toolbox and reports its current status.")
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Experiment")
    var experiment: ExperimentEntity

    static var parameterSummary: some ParameterSummary { Summary("Open \(\.$experiment)") }

    init() {}
    init(experiment: ExperimentEntity) { self.experiment = experiment }

    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<String> {
        guard let descriptor = ExperimentRegistry.descriptor(for: experiment.id) else {
            throw ExperimentServiceError.unavailable("No experiment with the identifier \(experiment.id) exists.")
        }
        ToolboxNavigator.shared.request = .experiment(descriptor.id)
        return .result(value: "Opened \(descriptor.name): \(descriptor.currentStatus.title).")
    }
}
#endif

struct ToolboxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ToolboxStatusIntent(), phrases: ["Show \(.applicationName) status", "How many experiments work in \(.applicationName)"],
                    shortTitle: "Toolbox Status", systemImageName: "checklist")
        AppShortcut(intent: HashTextIntent(), phrases: ["Hash text with \(.applicationName)", "Create a SHA-256 hash in \(.applicationName)"],
                    shortTitle: "SHA-256 Hash", systemImageName: "number")
        AppShortcut(intent: CapabilitySummaryIntent(), phrases: ["Summarize device capabilities in \(.applicationName)", "What can this device do in \(.applicationName)"],
                    shortTitle: "Device Capabilities", systemImageName: "cpu")
        #if !os(watchOS)
        AppShortcut(intent: OpenCategoryIntent(), phrases: ["Open \(\.$category) in \(.applicationName)", "Show \(\.$category) experiments in \(.applicationName)"],
                    shortTitle: "Open Category", systemImageName: "square.grid.2x2")
        AppShortcut(intent: OpenExperimentIntent(), phrases: ["Open an experiment in \(.applicationName)"],
                    shortTitle: "Open Experiment", systemImageName: "flask")
        #endif
    }
}

#if !os(watchOS)
/// One registered App Shortcut as shown in the run view. `AppShortcut` does not expose its phrases or symbol,
/// so the first phrase and the symbol above are repeated here; titles and descriptions come from the intent types.
struct ToolboxShortcutInfo: Identifiable {
    enum Kind { case status, hash, capabilities, category, experiment }

    let id: Kind
    let title: String
    let summary: String
    let phrase: String
    let symbol: String
    let opensApp: Bool

    static var all: [ToolboxShortcutInfo] {
        [
            info(.status, ToolboxStatusIntent.self, ToolboxStatusIntent.description, symbol: "checklist", phrase: "Show \(appName) status"),
            info(.hash, HashTextIntent.self, HashTextIntent.description, symbol: "number", phrase: "Hash text with \(appName)"),
            info(.capabilities, CapabilitySummaryIntent.self, CapabilitySummaryIntent.description, symbol: "cpu", phrase: "Summarize device capabilities in \(appName)"),
            info(.category, OpenCategoryIntent.self, OpenCategoryIntent.description, symbol: "square.grid.2x2", phrase: "Open <category> in \(appName)"),
            info(.experiment, OpenExperimentIntent.self, OpenExperimentIntent.description, symbol: "flask", phrase: "Open an experiment in \(appName)"),
        ]
    }

    /// The name Siri substitutes for `.applicationName`.
    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Apple Toolbox"
    }

    private static func info<Intent: AppIntent>(_ kind: Kind, _ intent: Intent.Type, _ description: IntentDescription, symbol: String, phrase: String) -> ToolboxShortcutInfo {
        ToolboxShortcutInfo(id: kind, title: String(localized: Intent.title), summary: String(localized: description.descriptionText),
                            phrase: phrase, symbol: symbol, opensApp: Intent.supportedModes.contains(.foreground))
    }
}

/// Runs the app's own intents in-process by calling `perform()`, exactly as Siri or Shortcuts would.
@MainActor
final class AppIntentsExperimentService: ObservableObject {
    @Published private(set) var output = "Run an intent to see the value its perform() returns."
    @Published private(set) var isError = false
    @Published private(set) var running: ToolboxShortcutInfo.Kind?
    @Published var text = "Joris Apple Toolbox"
    @Published var category: ExperimentCategory = .security
    @Published var experimentID = "cryptokit"

    let shortcuts = ToolboxShortcutInfo.all
    let registeredCount = ToolboxShortcuts.appShortcuts.count

    func run(_ shortcut: ToolboxShortcutInfo) {
        running = shortcut.id
        Task {
            do {
                let value = try await perform(shortcut.id)
                output = "\(shortcut.title)\n\(value ?? "perform() returned no value.")"
                isError = false
            } catch {
                output = "\(shortcut.title) failed: \(error.localizedDescription)"
                isError = true
            }
            running = nil
        }
    }

    private func perform(_ kind: ToolboxShortcutInfo.Kind) async throws -> String? {
        switch kind {
        case .status: return try await ToolboxStatusIntent().perform().value
        case .hash: return try await HashTextIntent(text: text).perform().value
        case .capabilities: return try await CapabilitySummaryIntent().perform().value
        case .category: return try await OpenCategoryIntent(category: category).perform().value
        case .experiment:
            guard let entity = try await ExperimentEntityQuery().entities(for: [experimentID]).first else {
                throw ExperimentServiceError.unavailable("The entity query found no experiment \(experimentID).")
            }
            return try await OpenExperimentIntent(experiment: entity).perform().value
        }
    }
}
#endif
#endif
