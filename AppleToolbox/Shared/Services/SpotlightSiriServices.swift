import Foundation
import Combine
#if canImport(AppIntents)
import AppIntents
#endif
#if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
import CoreSpotlight
import UniformTypeIdentifiers
#endif
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension ExperimentAvailability {
    /// Core Spotlight indexes app entities on iOS, iPadOS and macOS; a device can still report indexing as unavailable.
    static func spotlightIndexing() -> ExperimentStatus {
        #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
        CSSearchableIndex.isIndexingAvailable() ? .available : .unavailable
        #else
        .platformUnsupported
        #endif
    }
}

/// Pure rules for the experiments' Spotlight entries.
nonisolated enum SpotlightExperimentMetadata {
    /// The app's own named index; Apple reserves the default index for prototyping.
    static let indexName = "AppleToolbox.Experiments"

    /// The experiment an indexed item stands for. Items created from an `IndexedEntity` use "<EntityType>/<id>"
    /// as their unique identifier; a bare experiment ID is accepted as well.
    static func experimentID(fromItemIdentifier identifier: String) -> String? {
        let id = identifier.components(separatedBy: "/").last?.trimmingCharacters(in: .whitespaces) ?? ""
        return id.isEmpty ? nil : id
    }

    /// Identifiers that are still in the index but no longer in the registry.
    static func staleIdentifiers(indexed: [String], current: [String]) -> [String] {
        Set(indexed).subtracting(current).sorted()
    }

    /// Search keywords: frameworks, category, app name and the words of the experiment ID, without case-insensitive duplicates.
    static func keywords(id: String, category: String, frameworks: [String]) -> [String] {
        var seen = Set<String>()
        let candidates = frameworks + [category, "Apple Toolbox"] + id.split(separator: "-").map(String.init)
        return candidates.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}

#if canImport(CoreSpotlight) && canImport(AppIntents) && (os(iOS) || os(macOS))
/// Spotlight indexes the entity's display representation (title, category subtitle, category symbol) plus this attribute set.
nonisolated extension ExperimentEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.title = name
        attributes.displayName = name
        attributes.contentDescription = summary
        attributes.keywords = SpotlightExperimentMetadata.keywords(id: id, category: categoryName, frameworks: frameworks)
        attributes.thumbnailData = SymbolThumbnail.pngData(systemName: symbolName)
        return attributes
    }
}

/// Renders an SF Symbol as PNG data for a Spotlight thumbnail.
nonisolated enum SymbolThumbnail {
    static func pngData(systemName: String, side: CGFloat = 64) -> Data? {
        #if os(iOS)
        let configuration = UIImage.SymbolConfiguration(pointSize: side * 0.55, weight: .semibold)
        guard let symbol = UIImage(systemName: systemName, withConfiguration: configuration)?
            .withTintColor(.systemBlue, renderingMode: .alwaysOriginal) else { return nil }
        let canvas = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: canvas).pngData { _ in
            let origin = CGPoint(x: (canvas.width - symbol.size.width) / 2, y: (canvas.height - symbol.size.height) / 2)
            symbol.draw(in: CGRect(origin: origin, size: symbol.size))
        }
        #else
        let configuration = NSImage.SymbolConfiguration(pointSize: side * 0.55, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.systemBlue]))
        guard let symbol = NSImage(systemSymbolName: systemName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
              let image = symbol.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        #endif
    }
}

/// Keeps every experiment in the app's Spotlight index and opens Spotlight results.
@MainActor
enum ExperimentSpotlightIndex {
    struct IndexedItem: Identifiable, Equatable {
        /// The item's `uniqueIdentifier`.
        let id: String
        let experimentID: String?
        let title: String
    }

    struct SyncReport {
        let indexed: Int
        let removed: [String]
    }

    private static let recordKey = "spotlight.indexedExperimentIDs"
    private static let dateKey = "spotlight.lastSynchronized"
    private static var launchSyncStarted = false

    static var isIndexingAvailable: Bool { CSSearchableIndex.isIndexingAvailable() }
    /// Experiment IDs of the last successful indexing run.
    static var recordedIDs: [String] { UserDefaults.standard.stringArray(forKey: recordKey) ?? [] }
    static var lastSynchronized: Date? { UserDefaults.standard.object(forKey: dateKey) as? Date }

    /// Indexes the registry once per launch.
    static func synchronizeOnLaunch() async {
        guard !launchSyncStarted else { return }
        launchSyncStarted = true
        do {
            let report = try await synchronize()
            ToolboxActivityLog.shared.record(.spotlight, "Indexed \(report.indexed) experiments at launch",
                                             report.removed.isEmpty ? "No stale entries." : "Removed stale entries: \(report.removed.joined(separator: ", "))")
        } catch {
            ToolboxActivityLog.shared.record(.spotlight, "Launch indexing failed", describe(error))
        }
    }

    /// Indexes all experiments and deletes entries of experiments that no longer exist (from the last run's record
    /// plus any identifiers a live query found).
    static func synchronize(alsoIndexed found: [String] = []) async throws -> SyncReport {
        guard isIndexingAvailable else {
            throw ExperimentServiceError.unavailable("CSSearchableIndex.isIndexingAvailable() returned false on this device.")
        }
        let entities = ExperimentRegistry.all.map(ExperimentEntity.init)
        let stale = SpotlightExperimentMetadata.staleIdentifiers(indexed: recordedIDs + found, current: entities.map(\.id))
        let index = CSSearchableIndex(name: SpotlightExperimentMetadata.indexName)
        if !stale.isEmpty {
            try await index.deleteAppEntities(identifiedBy: stale, ofType: ExperimentEntity.self)
        }
        try await index.indexAppEntities(entities)
        UserDefaults.standard.set(entities.map(\.id), forKey: recordKey)
        UserDefaults.standard.set(Date(), forKey: dateKey)
        return SyncReport(indexed: entities.count, removed: stale)
    }

    static func deleteAll() async throws {
        let index = CSSearchableIndex(name: SpotlightExperimentMetadata.indexName)
        try await index.deleteAppEntities(ofType: ExperimentEntity.self)
        UserDefaults.standard.removeObject(forKey: recordKey)
        UserDefaults.standard.removeObject(forKey: dateKey)
    }

    /// Asks Core Spotlight which items of this app are really in the index. A query searches all of the app's indexes.
    static func queryIndexedItems() async throws -> [IndexedItem] {
        let context = CSSearchQueryContext()
        context.fetchAttributes = ["title"]
        let query = CSSearchQuery(queryString: "title == \"*\"", queryContext: context)
        var items: [IndexedItem] = []
        for try await result in query.results {
            let item = result.item
            items.append(IndexedItem(id: item.uniqueIdentifier,
                                     experimentID: SpotlightExperimentMetadata.experimentID(fromItemIdentifier: item.uniqueIdentifier),
                                     title: item.attributeSet.title ?? item.uniqueIdentifier))
        }
        return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Handles a tapped Spotlight result that reached the app as `CSSearchableItemActionType`.
    static func continueFromSpotlight(_ activity: NSUserActivity) {
        let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String ?? ""
        guard let id = SpotlightExperimentMetadata.experimentID(fromItemIdentifier: identifier),
              let experiment = ExperimentRegistry.descriptor(for: id) else {
            ToolboxActivityLog.shared.record(.spotlight, "Spotlight result without experiment",
                                             "CSSearchableItemActivityIdentifier “\(identifier)” matches no experiment.")
            return
        }
        ToolboxNavigator.shared.request = .experiment(experiment.id)
        ToolboxActivityLog.shared.record(.spotlight, "Opened \(experiment.name) from Spotlight", identifier)
    }

    static func describe(_ error: Error) -> String {
        let error = error as NSError
        if error.domain == CSIndexErrorDomain {
            return "CSIndexError \(error.code): \(error.localizedDescription)"
        }
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
#endif

#if canImport(AppIntents) && !os(watchOS)
/// One donation of the Open Experiment intent. The system keeps no list of donations that an app can read,
/// so the app stores its own record, including the identifier `IntentDonationManager` returned.
nonisolated struct IntentDonationRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let experimentID: String
    let experimentName: String
    let donationIdentifier: IntentDonationIdentifier?
    let error: String?
}

/// Donates `OpenExperimentIntent` whenever an experiment is opened, so Siri Suggestions and Spotlight can learn the habit.
@MainActor
final class IntentDonationLog: ObservableObject {
    static let shared = IntentDonationLog()
    private static let key = "siri.recentDonations"
    private static let limit = 20

    @Published private(set) var records: [IntentDonationRecord]

    private init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        records = data.flatMap { try? JSONDecoder().decode([IntentDonationRecord].self, from: $0) } ?? []
    }

    func donateOpen(_ experiment: ExperimentDescriptor) async {
        let intent = OpenExperimentIntent(experiment: ExperimentEntity(experiment))
        do {
            let identifier = try await IntentDonationManager.shared.donate(intent: intent)
            append(IntentDonationRecord(id: UUID(), date: Date(), experimentID: experiment.id, experimentName: experiment.name, donationIdentifier: identifier, error: nil))
        } catch {
            let message = "\((error as NSError).domain) \((error as NSError).code): \(error.localizedDescription)"
            append(IntentDonationRecord(id: UUID(), date: Date(), experimentID: experiment.id, experimentName: experiment.name, donationIdentifier: nil, error: message))
            ToolboxActivityLog.shared.record(.siri, "Donation failed for \(experiment.name)", message)
        }
    }

    /// Deletes every donated Open Experiment intent from the system and returns how many it removed.
    func deleteAll() async throws -> Int {
        let deleted = try await IntentDonationManager.shared.deleteDonations(matching: .intentType(OpenExperimentIntent.self))
        records = []
        save()
        return deleted.count
    }

    private func append(_ record: IntentDonationRecord) {
        records.insert(record, at: 0)
        if records.count > Self.limit { records.removeLast(records.count - Self.limit) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(records), forKey: Self.key)
    }
}

/// State of the Spotlight & Siri run view: the live index contents and the actions on it.
@MainActor
final class SpotlightSiriExperimentService: ObservableObject {
    @Published private(set) var indexedItems: [IndexedItemRow] = []
    @Published private(set) var hasQueried = false
    @Published private(set) var isWorking = false
    @Published private(set) var output = "Query the index to see which experiments Spotlight really holds."
    @Published private(set) var isError = false

    struct IndexedItemRow: Identifiable, Equatable {
        let id: String
        let title: String
        let isStale: Bool
    }

    let registryCount = ExperimentRegistry.all.count
    var staleCount: Int { indexedItems.filter(\.isStale).count }

    var isIndexingSupported: Bool {
        #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
        ExperimentSpotlightIndex.isIndexingAvailable
        #else
        false
        #endif
    }

    var lastSynchronized: Date? {
        #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
        ExperimentSpotlightIndex.lastSynchronized
        #else
        nil
        #endif
    }

    func queryIndex() {
        run("Query") { service in
            let count = try await service.refreshItems()
            return "CSSearchQuery found \(count) item(s) of Apple Toolbox in Spotlight; the registry has \(service.registryCount) experiments."
        }
    }

    func reindex() {
        run("Re-index") { service in
            #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
            let found = service.indexedItems.compactMap { SpotlightExperimentMetadata.experimentID(fromItemIdentifier: $0.id) }
            let report = try await ExperimentSpotlightIndex.synchronize(alsoIndexed: found)
            ToolboxActivityLog.shared.record(.spotlight, "Re-indexed \(report.indexed) experiments", report.removed.joined(separator: ", "))
            let count = try await service.refreshItems()
            return "indexAppEntities(_:) indexed \(report.indexed) experiments"
                + (report.removed.isEmpty ? "" : ", deleteAppEntities(identifiedBy:ofType:) removed \(report.removed.joined(separator: ", "))")
                + ".\nThe index now reports \(count) item(s). Indexing is asynchronous, so a query right after it may still show the previous state."
            #else
            throw ExperimentServiceError.unavailable("Core Spotlight has no searchable index on this platform.")
            #endif
        }
    }

    func deleteIndex() {
        run("Delete") { service in
            #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
            try await ExperimentSpotlightIndex.deleteAll()
            ToolboxActivityLog.shared.record(.spotlight, "Deleted all experiments from the index")
            let count = try await service.refreshItems()
            return "deleteAppEntities(ofType:) removed all ExperimentEntity items; the index now reports \(count) item(s). The next launch indexes them again."
            #else
            throw ExperimentServiceError.unavailable("Core Spotlight has no searchable index on this platform.")
            #endif
        }
    }

    func deleteDonations() {
        run("Delete donations") { _ in
            let count = try await IntentDonationLog.shared.deleteAll()
            ToolboxActivityLog.shared.record(.siri, "Deleted \(count) donation(s)")
            return "deleteDonations(matching: .intentType(OpenExperimentIntent.self)) removed \(count) donation(s)."
        }
    }

    private func refreshItems() async throws -> Int {
        #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
        let registryIDs = Set(ExperimentRegistry.all.map(\.id))
        indexedItems = try await ExperimentSpotlightIndex.queryIndexedItems().map { item in
            IndexedItemRow(id: item.id, title: item.title, isStale: !(item.experimentID.map(registryIDs.contains) ?? false))
        }
        hasQueried = true
        return indexedItems.count
        #else
        throw ExperimentServiceError.unavailable("Core Spotlight has no searchable index on this platform.")
        #endif
    }

    private func run(_ action: String, _ work: @escaping @MainActor (SpotlightSiriExperimentService) async throws -> String) {
        isWorking = true
        Task {
            do {
                output = try await work(self)
                isError = false
            } catch {
                #if canImport(CoreSpotlight) && (os(iOS) || os(macOS))
                output = "\(action) failed: \(ExperimentSpotlightIndex.describe(error))"
                #else
                output = "\(action) failed: \(error.localizedDescription)"
                #endif
                isError = true
            }
            isWorking = false
        }
    }
}
#endif
