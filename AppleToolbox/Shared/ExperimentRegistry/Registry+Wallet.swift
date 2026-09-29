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
            description: "Create and export a real pass.json draft in any pass style (boarding pass with transit type, coupon, event ticket, store card, generic) with optional locations, iBeacons and relevant date, and watch PKPassLibraryDidChange live. An installable pass still requires Apple signing credentials; webServiceURL and NFC need a server and an Apple NFC certificate.", frameworks: ["PassKit", "Foundation"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: [], osRequirements: ["iOS 6+ · macOS 10.9+"], permissions: ["User-selected export destination"], capabilities: ["Wallet pass format"], entitlements: ["Pass Type ID certificate for installable .pkpass"], documentationURL: URL(string: "https://developer.apple.com/documentation/walletpasses")!, evaluate: { [.iOS, .iPadOS, .macOS].contains(CurrentPlatform.value) ? .approvalRequired : .platformUnsupported },
            applePrograms: ["Apple Developer Program: signing an installable pass needs a Pass Type ID certificate"]),
        ExperimentDescriptor(id: "secure-element-passes", name: "Secure Element Passes", category: .wallet,
            description: "Query the Secure Element passes PassKit shows this app on this device and paired devices, with their activation state, plus the issuer entitlements and NFC & SE Platform eligibility that gate advanced Wallet credentials.", frameworks: ["PassKit", "SecureElementCredential"], supportedPlatforms: [.iOS, .iPadOS, .macOS], hardwareRequirements: ["Secure Element (iPhone, Apple Watch or Mac with Touch ID)"], osRequirements: ["iOS 13.4+ · macOS 11+ · SecureElementCredential iOS 18.1+"], permissions: [], capabilities: ["In-App Provisioning, Contactless Pass Provisioning or NFC & SE Platform (Apple approval)"], entitlements: ["com.apple.developer.payment-pass-provisioning", "com.apple.developer.contactless-payment-pass-provisioning", "com.apple.developer.secure-element-credential"], documentationURL: URL(string: "https://developer.apple.com/documentation/passkit/pksecureelementpass")!, evaluate: ExperimentAvailability.secureElementPasses,
            useCase: ExperimentUseCase(id: "secure-element-passes", title: "Look for issuer passes", summary: "See which cards, keys and badges in the Secure Element PassKit reveals to an app, and why an app that did not issue them sees none.", interaction: "Query PassKit: the pass list, activation availability and NFC & SE Platform eligibility come straight from the system."),
            explanations: [
                .appleProgramRequired: ExperimentExplanation(reason: "PassKit only reveals Secure Element passes to their issuer's app, and that app needs an issuer entitlement from Apple. This app has none, so the query returns no passes even when Wallet holds cards and keys.", required: "In-App Provisioning, Contactless Pass Provisioning or the NFC & SE Platform (Secure Element Credential), granted by Apple to card, access and credential issuers",
                    nextStep: "Take part in the matching Apple issuer program. The query below still runs and shows exactly what PassKit returns."),
                .unavailable: ExperimentExplanation(reason: "PKPassLibrary.isPassLibraryAvailable() is false, so Wallet cannot be queried here.", required: "A device with Wallet that is not restricted",
                    nextStep: "Run the experiment on iPhone or a Mac with Wallet."),
            ],
            applePrograms: ["Apple issuer programs: In-App Provisioning, Contactless Pass Provisioning or NFC & SE Platform"]),
    ] + AdvancedCredentialCatalog.all.map(\.descriptor)
}

private extension AdvancedCredential {
    /// Advanced credentials are listed apart from normal passes and marked with their Apple program (spec §25).
    var descriptor: ExperimentDescriptor {
        let capabilities = capabilityIDs.compactMap(CapabilityRegistry.descriptor(for:))
        let credentialID = id
        var explanations: [ExperimentStatus: ExperimentExplanation] = [
            .appleProgramRequired: ExperimentExplanation(reason: reason, required: program, nextStep: nextStep),
        ]
        if checksPaymentCardReader {
            explanations[.hardwareUnsupported] = ExperimentExplanation(reason: "PaymentCardReader.isSupported is false: this iPhone model cannot run Tap to Pay on iPhone.", required: "iPhone XS or later",
                                                                       nextStep: "Use a supported iPhone; Tap to Pay does not run on iPad or in the Simulator.")
            explanations[.regionRestricted] = ExperimentExplanation(reason: "The device region is not on Apple's Tap to Pay on iPhone country list. Availability is decided by the merchant's country and payment service provider; the device region is the closest signal the app can read.", required: "A merchant and payment service provider in a Tap to Pay on iPhone country",
                                                                    nextStep: "Check Apple's Tap to Pay on iPhone availability page for your country and provider.")
        }
        return ExperimentDescriptor(id: id, name: name, category: .wallet,
            description: summary + " Shown with its Apple program requirements; this app cannot issue it.", frameworks: frameworks, supportedPlatforms: [.iOS],
            hardwareRequirements: [checksPaymentCardReader ? "iPhone XS or later" : "iPhone with NFC and Secure Element"],
            osRequirements: [checksPaymentCardReader ? "iOS 15.4+" : "iOS 13.4+ · SecureElementCredential iOS 18.1+"], permissions: [],
            capabilities: capabilities.map(\.name), entitlements: capabilities.flatMap(\.keys), documentationURL: documentationURL,
            evaluate: { ExperimentAvailability.advancedCredential(credentialID) },
            useCase: ExperimentUseCase(id: id, title: "See the boundary", summary: "Find out which Apple program issues this credential and what an app needs to take part.", interaction: "Run the live checks: they read the app's provisioning for the program entitlements and query the public PassKit and eligibility APIs."),
            explanations: explanations,
            applePrograms: [program])
    }
}
