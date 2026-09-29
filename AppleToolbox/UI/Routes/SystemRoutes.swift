import SwiftUI

/// Run views for the System category.
struct SystemRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "app-intents": AppIntentsRunView()
        case "widgetkit": WidgetKitRunView()
        case "notifications": NotificationsRunView()
        case "live-activities": LiveActivitiesRunView()
        default: UnroutedExperimentView()
        }
    }
}
