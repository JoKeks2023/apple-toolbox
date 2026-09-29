import SwiftUI
import WidgetKit
import AppIntents

/// Control Center / Lock Screen / Action button control that opens the app on the WidgetKit experiment.
struct ToolboxOpenAppControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ToolboxWidgetStore.openAppControlKind) {
            ControlWidgetButton(action: OpenWidgetKitExperimentIntent()) {
                Label("Apple Toolbox", systemImage: "wrench.and.screwdriver")
            }
        }
        .displayName("Open Apple Toolbox")
        .description("Opens the WidgetKit experiment in Apple Toolbox.")
    }
}

/// Toggle control that pins the last opened experiment; shares its state with the interactive widget.
struct ToolboxFavoriteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ToolboxWidgetStore.favoriteControlKind, provider: ToolboxFavoriteControlProvider()) { isPinned in
            ControlWidgetToggle("Pin Experiment", isOn: isPinned, action: SetFavoriteExperimentIntent()) { isOn in
                Label(isOn ? "Pinned" : "Not pinned", systemImage: isOn ? "pin.fill" : "pin")
            }
        }
        .displayName("Pin Last Experiment")
        .description("Pins the experiment you opened last in Apple Toolbox.")
    }
}

/// Nonisolated: the system asks for the value outside the main actor.
nonisolated struct ToolboxFavoriteControlProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        ToolboxWidgetStore.loadInteractive().favorite != nil
    }
}
