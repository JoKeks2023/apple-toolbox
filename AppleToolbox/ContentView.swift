import SwiftUI

private enum SidebarItem: Hashable {
    case category(ExperimentCategory)
    case entitlements
}

struct ContentView: View {
    @State private var selection: SidebarItem?
    @State private var detailPath = NavigationPath()
    @Environment(\.scenePhase) private var scenePhase
    private let experiments = ExperimentRegistry.all

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Explore") {
                    ForEach(ExperimentCategory.allCases) { category in
                        let count = experiments.filter { $0.category == category }.count
                        NavigationLink(value: SidebarItem.category(category)) {
                            Label {
                                HStack { Text(category.rawValue); Spacer(); if count > 0 { Text("\(count)").foregroundStyle(.secondary) } }
                            } icon: { Image(systemName: category.symbolName).foregroundStyle(.tint) }
                        }
                    }
                }
                Section("Inspect") {
                    NavigationLink(value: SidebarItem.entitlements) {
                        Label {
                            HStack { Text("Entitlements"); Spacer(); Text("\(CapabilityRegistry.all.count)").foregroundStyle(.secondary) }
                        } icon: { Image(systemName: "checkmark.seal").foregroundStyle(.tint) }
                    }
                }
            }
            .navigationTitle("Apple Toolbox")
        } detail: {
            NavigationStack(path: $detailPath) {
                Group {
                    switch selection {
                    case .category(let category):
                        CategoryView(category: category, experiments: experiments.filter { $0.category == category })
                    case .entitlements:
                        EntitlementExplorerView()
                    case nil:
                        WelcomeView()
                    }
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
        .onChange(of: selection) { detailPath = NavigationPath() }
        // Permissions can change in Settings while the app is in the background.
        .task { await PermissionCenter.shared.refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await PermissionCenter.shared.refresh() } } }
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
    @ObservedObject private var permissions = PermissionCenter.shared
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
