import SwiftUI

/// Run views for the Connectivity category.
struct ConnectivityRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "core-bluetooth": CoreBluetoothRunView()
        case "bluetooth-peripheral": BluetoothPeripheralModeRunView()
        case "accessory-setup-kit": AccessorySetupKitRunView()
        case "external-accessory": ExternalAccessoryRunView()
        case "bluetooth-midi": BluetoothMIDIRunView()
        case "multipeer-connectivity": MultipeerRunView()
        case "continuity": WatchConnectivityRunView()
        case "ecosystem-continuity": ContinuityLabRunView()
        case "nearby-interaction": NearbyInteractionRunView()
        case "spatial-link": SpatialLinkRunView()
        default: UnroutedExperimentView()
        }
    }
}
