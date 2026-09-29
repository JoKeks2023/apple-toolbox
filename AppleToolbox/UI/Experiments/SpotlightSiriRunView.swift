import SwiftUI

/// Spotlight & Siri (spec §27): the experiments as indexed App Intents entities, Spotlight results that open
/// the experiment, and the Open Experiment donations that feed Siri Suggestions.
struct SpotlightSiriRunView: View {
    #if os(iOS) || os(macOS)
    @StateObject private var service = SpotlightSiriExperimentService()

    var body: some View {
        SpotlightIndexSection(service: service)
        SpotlightOpenSection()
        SiriDonationSection(service: service)
    }
    #else
    var body: some View {
        OutputView(text: "Core Spotlight keeps no searchable app index on \(CurrentPlatform.value.rawValue), and IndexedEntity is only available on iOS, iPadOS and macOS.", isError: true)
    }
    #endif
}

#if os(iOS) || os(macOS)
private struct SpotlightIndexSection: View {
    @ObservedObject var service: SpotlightSiriExperimentService
    @State private var isConfirmingDelete = false

    var body: some View {
        Section("Spotlight index · CSSearchableIndex") {
            LabeledContent("Indexing available", value: service.isIndexingSupported ? "Yes" : "No")
            LabeledContent("Index") { Text(SpotlightExperimentMetadata.indexName).font(.body.monospaced()) }
            LabeledContent("Experiments in the registry", value: "\(service.registryCount)")
            LabeledContent("Items found by CSSearchQuery", value: service.hasQueried ? "\(service.indexedItems.count)" : "Not queried yet")
            if service.staleCount > 0 {
                LabeledContent("Stale items", value: "\(service.staleCount)")
            }
            LabeledContent("Last indexed", value: service.lastSynchronized?.formatted(date: .abbreviated, time: .standard) ?? "Never")
            HStack {
                Button(service.isWorking ? "Working…" : "Query Index", action: service.queryIndex)
                    .buttonStyle(.borderedProminent)
                Button("Re-index All", action: service.reindex)
                    .buttonStyle(.bordered)
                Button("Delete Index", role: .destructive) { isConfirmingDelete = true }
                    .buttonStyle(.bordered)
            }
            .disabled(service.isWorking || !service.isIndexingSupported)
            .confirmationDialog("Delete all experiments from Spotlight?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete Index", role: .destructive, action: service.deleteIndex)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Spotlight stops showing Apple Toolbox experiments until you re-index or relaunch the app.")
            }
            OutputView(text: service.output, isError: service.isError)
            if !service.indexedItems.isEmpty {
                DisclosureGroup("Indexed items (\(service.indexedItems.count))") {
                    ForEach(service.indexedItems) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(item.title)
                                if item.isStale { Text("stale").font(.caption.weight(.semibold)).foregroundStyle(.orange) }
                            }
                            Text(item.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Every experiment is an ExperimentEntity that adopts IndexedEntity: title, category and symbol come from its display representation, the description, framework keywords and a symbol thumbnail from its attribute set. The app indexes them with indexAppEntities(_:) at launch and deletes experiments that no longer exist.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SpotlightOpenSection: View {
    @ObservedObject private var log = ToolboxActivityLog.shared

    var body: some View {
        Section("Open from Spotlight") {
            let entries = log.entries(in: [.spotlight])
            if entries.isEmpty {
                Text("Nothing handled yet in this session. Search for an experiment or a framework name in Spotlight and tap the Apple Toolbox result.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    ActivityLogRow(entry: entry)
                }
            }
            Text("A result opens through OpenExperimentIntent, the entity's OpenIntent. Results that arrive as a CSSearchableItemActionType user activity are routed by the item identifier instead; both paths end in the app's navigator.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct SiriDonationSection: View {
    @ObservedObject var service: SpotlightSiriExperimentService
    @ObservedObject private var donations = IntentDonationLog.shared
    @State private var isConfirmingDelete = false

    var body: some View {
        Section("Siri donations · IntentDonationManager") {
            LabeledContent("Donated intent", value: "Open Experiment (OpenIntent)")
            LabeledContent("Recorded donations", value: "\(donations.records.count)")
            if donations.records.isEmpty {
                Text("Open any experiment: Apple Toolbox donates OpenExperimentIntent for it and records the returned donation identifier here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(donations.records) { record in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(record.experimentName)
                            Spacer()
                            Text(record.date, style: .relative).font(.caption).foregroundStyle(.secondary)
                        }
                        if let error = record.error {
                            Text(error).font(.caption).foregroundStyle(.red)
                        } else if let identifier = record.donationIdentifier {
                            Text(String(describing: identifier)).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
            Button("Delete All Donations", role: .destructive) { isConfirmingDelete = true }
                .disabled(service.isWorking)
                .confirmationDialog("Delete all Open Experiment donations?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                    Button("Delete Donations", role: .destructive, action: service.deleteDonations)
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Siri and Spotlight forget which experiments you opened in Apple Toolbox.")
                }
            Text("The system uses donations for Siri Suggestions, Shortcuts suggestions and Spotlight's suggested actions. There is no API that lists the system's donations or shows how it ranks them, so this list is the app's own record.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#endif

struct ActivityLogRow: View {
    let entry: ToolboxActivityLog.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.title)
                Spacer()
                Text(entry.date, style: .time).font(.caption).foregroundStyle(.secondary)
            }
            if !entry.detail.isEmpty {
                Text(entry.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        }
    }
}
