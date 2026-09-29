import SwiftUI

/// Run views for the Wallet category.
struct WalletRunRoutes: View {
    let experiment: ExperimentDescriptor

    var body: some View {
        switch experiment.id {
        case "wallet-status": WalletPassLibraryRunView()
        case "apple-pay": ApplePayRunView()
        case "wallet-creator": WalletPassCreatorRunView()
        default: UnroutedExperimentView()
        }
    }
}
