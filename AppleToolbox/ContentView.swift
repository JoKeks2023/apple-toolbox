import SwiftUI

private enum SidebarItem: Hashable {
    case tool(String)
    case category(ExperimentCategory)
    case entitlements
}

struct ContentView: View {
    @State private var selection: SidebarItem?
    @State private var detailPath = NavigationPath()
    /// Experiment to push once a navigation request has switched the sidebar category.
    @State private var pendingExperimentID: String?
    @ObservedObject private var navigator = ToolboxNavigator.shared
    @Environment(\.scenePhase) private var scenePhase
    private let experiments = ExperimentRegistry.all

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Tools") {
                    ForEach(ToolboxTools.all.filter { $0.experiment != nil }) { tool in
                        NavigationLink(value: SidebarItem.tool(tool.id)) {
                            Label(tool.title, systemImage: tool.symbolName)
                        }
                        .accessibilityIdentifier("tool.\(tool.id)")
                    }
                }
                Section("Explore") {
                    ForEach(ExperimentCategory.allCases) { category in
                        let count = experiments.filter { $0.category == category }.count
                        NavigationLink(value: SidebarItem.category(category)) {
                            Label {
                                HStack { Text(category.rawValue); Spacer(); if count > 0 { Text("\(count)").foregroundStyle(.secondary) } }
                            } icon: { Image(systemName: category.symbolName).foregroundStyle(.tint) }
                        }
                        .accessibilityIdentifier("category.\(category.id)")
                    }
                }
                Section("Inspect") {
                    NavigationLink(value: SidebarItem.entitlements) {
                        Label {
                            HStack { Text("Entitlements"); Spacer(); Text("\(CapabilityRegistry.all.count)").foregroundStyle(.secondary) }
                        } icon: { Image(systemName: "checkmark.seal").foregroundStyle(.tint) }
                    }
                    .accessibilityIdentifier("inspect.entitlements")
                }
            }
            .navigationTitle("Apple Toolbox")
        } detail: {
            NavigationStack(path: $detailPath) {
                Group {
                    switch selection {
                    case .tool(let id):
                        if let experiment = ExperimentRegistry.descriptor(for: id) {
                            ExperimentDetailView(experiment: experiment).id(id)
                        }
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
        .onChange(of: selection) {
            detailPath = NavigationPath()
            if let pendingExperimentID { detailPath.append(pendingExperimentID) }
            pendingExperimentID = nil
        }
        // App Intents may request navigation before this view exists, so the pending request is also read initially.
        .onChange(of: navigator.request, initial: true) {
            guard let request = navigator.request else { return }
            navigator.request = nil
            open(request)
        }
        .toolboxActivityHandling()
        // Permissions can change in Settings while the app is in the background.
        .task { await PermissionCenter.shared.refresh() }
        .onChange(of: scenePhase) { if scenePhase == .active { Task { await PermissionCenter.shared.refresh() } } }
    }

    private func open(_ request: ToolboxNavigator.Request) {
        switch request {
        case .category(let category):
            selection = .category(category)
            detailPath = NavigationPath()
        case .experiment(let id):
            guard let experiment = ExperimentRegistry.descriptor(for: id) else { return }
            let target = SidebarItem.category(experiment.category)
            if selection == target {
                detailPath = NavigationPath([id])
            } else {
                pendingExperimentID = id
                selection = target
            }
        }
    }
}

private struct WelcomeView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Joris Apple Toolbox", systemImage: "wrench.and.screwdriver")
        } description: {
            Text("A native laboratory for discovering what your Apple devices can actually do. Start with a tool, or explore the experiments by category.")
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
                    .accessibilityIdentifier("experiment.\(experiment.id)")
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
