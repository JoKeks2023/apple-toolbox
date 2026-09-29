#if os(tvOS)
import SwiftUI
import Combine

/// Apple TV home (spec §30): a sidebar-adaptable tab bar with one tab per category and large focusable cards,
/// instead of the iPhone/iPad split view. Every experiment stays reachable through its category tab.
struct TVHomeView: View {
    enum TVTab: Hashable {
        case tools
        case category(ExperimentCategory)
        case entitlements
    }

    @State private var selection: TVTab = .tools
    @State private var paths: [TVTab: NavigationPath] = [:]
    @ObservedObject private var navigator = ToolboxNavigator.shared
    private let experiments = ExperimentRegistry.all

    var body: some View {
        TabView(selection: $selection) {
            SwiftUI.Tab("Tools", systemImage: "wrench.and.screwdriver", value: TVTab.tools) {
                stack(for: .tools) {
                    TVCardGrid(title: "Tools", subtitle: "Start with a tool, or pick a category in the sidebar.",
                               experiments: ToolboxTools.all.compactMap(\.experiment))
                }
            }
            TabSection("Explore") {
                ForEach(ExperimentCategory.allCases) { category in
                    SwiftUI.Tab(category.rawValue, systemImage: category.symbolName, value: TVTab.category(category)) {
                        stack(for: .category(category)) {
                            TVCardGrid(title: category.rawValue, subtitle: "Experiments for \(category.rawValue.lowercased()). Cards show the live status on this Apple TV.",
                                       experiments: experiments.filter { $0.category == category })
                        }
                    }
                }
            }
            TabSection("Inspect") {
                SwiftUI.Tab("Entitlements", systemImage: "checkmark.seal", value: TVTab.entitlements) {
                    stack(for: .entitlements) { EntitlementExplorerView() }
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .onChange(of: navigator.request, initial: true) {
            guard let request = navigator.request else { return }
            navigator.request = nil
            switch request {
            case .category(let category):
                paths[.category(category)] = NavigationPath()
                selection = .category(category)
            case .experiment(let id):
                guard let experiment = ExperimentRegistry.descriptor(for: id) else { return }
                paths[.category(experiment.category)] = NavigationPath([id])
                selection = .category(experiment.category)
            }
        }
    }

    private func stack(for tab: TVTab, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(get: { paths[tab] ?? NavigationPath() }, set: { paths[tab] = $0 })) {
            root().navigationDestination(for: String.self) { experimentID in
                if let experiment = ExperimentRegistry.descriptor(for: experimentID) {
                    ExperimentDetailView(experiment: experiment)
                } else {
                    ContentUnavailableView("Experiment unavailable", systemImage: "questionmark.circle")
                }
            }
        }
    }
}

/// Large focusable cards in a grid; the focus engine lifts the focused card (`.card` button style).
private struct TVCardGrid: View {
    let title: String
    let subtitle: String
    let experiments: [ExperimentDescriptor]
    @ObservedObject private var permissions = PermissionCenter.shared

    private let columns = [GridItem(.adaptive(minimum: 420, maximum: 560), spacing: 48)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                Text(subtitle).font(.headline).foregroundStyle(.secondary)
                if experiments.isEmpty {
                    ContentUnavailableView("No experiments", systemImage: "square.dashed")
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 48) {
                        ForEach(experiments) { experiment in
                            NavigationLink(value: experiment.id) { TVExperimentCard(experiment: experiment) }
                                .buttonStyle(.card)
                                .accessibilityIdentifier("experiment.\(experiment.id)")
                        }
                    }
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        .navigationTitle(title)
    }
}

private struct TVExperimentCard: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: experiment.category.symbolName).font(.title2)
                    .frame(width: 64, height: 64)
                    .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                Spacer()
                StatusBadge(status: experiment.currentStatus)
            }
            Text(experiment.name).font(.title3.weight(.semibold)).lineLimit(2)
            Text(experiment.frameworks.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(experiment.description).font(.caption2).foregroundStyle(.secondary).lineLimit(3)
            Spacer(minLength: 0)
        }
        .padding(28)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
    }
}
#endif
