import SwiftUI

/// Run views for the NFC category.
struct NFCRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "core-nfc": CoreNFCRunView()
        default: UnroutedExperimentView()
        }
    }
}
