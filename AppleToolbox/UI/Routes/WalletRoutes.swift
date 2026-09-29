import SwiftUI

/// Run views for the Wallet category.
struct WalletRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "wallet-status": StatusCheckRunView(experiment: experiment, title: "Inspect Wallet Capability", check: WalletExperimentService.statusText)
        case "wallet-creator": WalletPassCreatorRunView()
        default: UnroutedExperimentView()
        }
    }
}
