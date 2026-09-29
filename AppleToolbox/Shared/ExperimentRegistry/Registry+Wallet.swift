import Foundation

extension ExperimentRegistry {
    static let wallet: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "wallet-status", name: "Wallet & PassKit", category: .wallet,
            description: "List the passes PassKit shows this app and add a signed .pkpass you choose through the system's add-pass sheet.", frameworks: ["PassKit", "UniformTypeIdentifiers"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 6+ · macOS 11+"], permissions: ["User-selected .pkpass file", "Add-pass confirmation"], capabilities: ["Wallet (Pass Type IDs) to read the app's own passes"], entitlements: ["com.apple.developer.pass-type-identifiers"], documentationURL: URL(string: "https://developer.apple.com/documentation/passkit/pkpasslibrary")!, evaluate: ExperimentAvailability.wallet,
            useCase: ExperimentUseCase(id: "wallet-add-pass", title: "Add a pass", summary: "See which passes the app may read, and add a real signed pass such as a ticket or boarding pass you downloaded.", interaction: "Read the pass library, then choose a .pkpass file. PassKit verifies its signature before the add-pass sheet opens."),
            explanations: [
                .unavailable: ExperimentExplanation(reason: "PKPassLibrary.isPassLibraryAvailable() is false, so Wallet cannot be used here.", required: "A device with Wallet that is not restricted",
                    nextStep: "Run the experiment on iPhone or a Mac with Wallet, and check Screen Time restrictions."),
            ],
            applePrograms: ["Apple Developer Program: Pass Type IDs are not available to free Personal Teams"]),
        ExperimentDescriptor(id: "apple-pay", name: "Apple Pay", category: .wallet,
            description: "Check canMakePayments per payment network, render PKPaymentButton types and styles, and run a real PKPaymentRequest through the payment sheet with a clearly labelled placeholder merchant identifier.", frameworks: ["PassKit"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Apple Pay capable device with a card in Wallet"], osRequirements: ["iOS 10+ · macOS 11+"], permissions: ["Payment sheet authorization (Face ID, Touch ID or passcode)"], capabilities: ["Apple Pay with a registered Merchant ID"], entitlements: ["com.apple.developer.in-app-payments"], documentationURL: URL(string: "https://developer.apple.com/documentation/passkit/pkpaymentauthorizationcontroller")!, evaluate: ExperimentAvailability.applePay,
            useCase: ExperimentUseCase(id: "apple-pay-sheet", title: "Try the payment sheet", summary: "See which card networks this device can pay with and how Apple Pay treats a request without a registered merchant.", interaction: "Check the networks, pick a region and button style, then tap the Apple Pay button. The request uses a placeholder Merchant ID and is never charged."),
            explanations: [
                .entitlementRequired: ExperimentExplanation(reason: "No Merchant ID is provisioned in this app's Apple Pay entitlement, so the payment sheet cannot complete a payment. The request below uses a placeholder merchant identifier and fails honestly.", required: "com.apple.developer.in-app-payments with a registered Merchant ID and its payment processing certificate",
                    nextStep: "Register a Merchant ID, create its payment processing certificate, enable Apple Pay on the App ID and send that ID in the request."),
                .unavailable: ExperimentExplanation(reason: "PKPaymentAuthorizationController.canMakePayments() is false: this device cannot make Apple Pay payments, or payments are restricted.", required: "An Apple Pay capable device in a supported region, without payment restrictions",
                    nextStep: "Check Screen Time restrictions and Apple Pay availability in your region. The network checks below still run."),
            ],
            applePrograms: ["Apple Developer Program: Merchant IDs and payment processing certificates"]),
        ExperimentDescriptor(id: "wallet-creator", name: "Wallet Pass Creator", category: .wallet,
            description: "Create and export a real pass.json draft. An installable Apple Wallet pass still requires Apple signing credentials.", frameworks: ["PassKit", "Foundation"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 6+ · macOS 10.9+"], permissions: ["User-selected export destination"], capabilities: ["Wallet pass format"], entitlements: ["Pass Type ID certificate for installable .pkpass"], documentationURL: URL(string: "https://developer.apple.com/documentation/walletpasses")!, evaluate: { [.iOS, .iPadOS, .macOS].contains(CurrentPlatform.value) ? .approvalRequired : .platformUnsupported },
            applePrograms: ["Apple Developer Program: signing an installable pass needs a Pass Type ID certificate"]),
    ]
}
