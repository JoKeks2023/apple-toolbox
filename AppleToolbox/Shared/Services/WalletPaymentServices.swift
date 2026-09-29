import Foundation
import Combine

#if canImport(PassKit) && !os(watchOS) && !os(tvOS)
import PassKit
#endif
#if os(macOS)
import AppKit
#endif

extension ExperimentAvailability {
    /// Apple Pay needs a device that can make payments; without a provisioned Merchant ID the sheet cannot complete.
    static func applePay() -> ExperimentStatus {
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        guard PKPaymentAuthorizationController.canMakePayments() else { return .unavailable }
        return IdentityEntitlements.state(ofCapability: "apple-pay").isPresent ? .available : .entitlementRequired
        #else
        return .platformUnsupported
        #endif
    }
}

/// A pass as PassKit shows it to this app, reduced to displayable values.
nonisolated struct WalletPassSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let organization: String
    let detail: String
    let passTypeIdentifier: String
    let serialNumber: String
    let kind: String
    let location: String
}

/// Readable text for PassKit's error codes (PKPassKitErrorDomain), which the framework itself only numbers.
nonisolated enum PassKitErrorText {
    static func describe(code: Int, message: String) -> String {
        let meaning = switch code {
        case 1: "invalid data: the file is not a valid .pkpass package"
        case 2: "unsupported version: pass.json uses a format version this OS does not support"
        case 3: "invalid signature: the manifest signature does not verify against Apple's WWDR chain and a Pass Type ID certificate"
        case 4: "not entitled: the app lacks the entitlement for this pass type"
        default: "unknown PassKit error"
        }
        return "PassKit error \(code), \(meaning). (\(message))"
    }
}

/// Wallet pass library (spec §25): passes visible to the app and adding a user-selected .pkpass through the system sheet.
@MainActor
final class WalletPassLibraryService: ObservableObject {
    @Published private(set) var passes: [WalletPassSummary] = []
    @Published private(set) var hasRead = false
    @Published private(set) var output = "Read the pass library or choose a signed .pkpass file."
    @Published private(set) var isError = false
    #if canImport(PassKit) && os(iOS)
    /// The validated pass waiting for PKAddPassesViewController.
    @Published var passToAdd: PKPass?
    #endif

    func refresh() {
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        guard PKPassLibrary.isPassLibraryAvailable() else { report("PKPassLibrary.isPassLibraryAvailable() is false on this device.", isError: true); return }
        let library = PKPassLibrary()
        passes = library.passes().map(Self.summary)
        hasRead = true
        let wallet = IdentityEntitlements.state(ofCapability: "wallet")
        let visibility = wallet.isPresent
            ? "The app sees passes whose pass type identifier is listed in its Wallet entitlement, plus Secure Element passes associated with it."
            : "No Wallet entitlement (Pass Type IDs) is provisioned, so PassKit shows this app none of the passes in Wallet, even though Wallet may hold many."
        report("PKPassLibrary.passes() returned \(passes.count) pass\(passes.count == 1 ? "" : "es").\n\(visibility)\n\(IdentityEntitlements.summary(of: wallet, key: "com.apple.developer.pass-type-identifiers"))")
        #else
        report("PKPassLibrary is not available on this platform.", isError: true)
        #endif
    }

    /// Validates a user-picked .pkpass with PassKit and hands it to the system's add-pass flow.
    func importPass(from url: URL) {
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let pass: PKPass
        do {
            pass = try PKPass(data: try Data(contentsOf: url))
        } catch {
            let nsError = error as NSError
            let detail = nsError.domain == PKPassKitErrorDomain
                ? PassKitErrorText.describe(code: nsError.code, message: nsError.localizedDescription)
                : "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
            report("PKPass(data:) rejected \(url.lastPathComponent): \(detail)", isError: true)
            return
        }
        let described = "\(pass.localizedName) from \(pass.organizationName) · \(pass.passTypeIdentifier) · serial \(pass.serialNumber)"
        if PKPassLibrary().containsPass(pass) {
            report("PassKit verified \(described).\nThis pass is already in Wallet.")
            return
        }
        #if os(iOS)
        guard PKAddPassesViewController.canAddPasses() else { report("PassKit verified \(described), but PKAddPassesViewController.canAddPasses() is false on this device.", isError: true); return }
        passToAdd = pass
        report("PassKit verified \(described). Review it in the add-pass sheet.")
        #else
        report("PassKit verified \(described). Asking Wallet to add it…")
        PKPassLibrary().addPasses([pass]) { @Sendable [weak self] status in
            let raw = status.rawValue
            Task { @MainActor in self?.addFinished(status: raw, name: described) }
        }
        #endif
        #else
        report("Adding passes needs PassKit on iPhone, iPad or Mac.", isError: true)
        #endif
    }

    #if canImport(PassKit) && os(iOS)
    /// Called when PKAddPassesViewController finishes; the library tells whether the person added the pass.
    func addSheetFinished(_ pass: PKPass) {
        passToAdd = nil
        let added = PKPassLibrary().containsPass(pass)
        report(added ? "\(pass.localizedName) was added to Wallet." : "The add-pass sheet closed without adding \(pass.localizedName).")
        if hasRead { refresh() }
    }
    #endif

    func importFailed(_ error: Error) {
        report("The file could not be opened: \(error.localizedDescription)", isError: true)
    }

    private func addFinished(status: Int, name: String) {
        let text = switch status {
        case 0: "Wallet added \(name)."
        case 1: "Wallet asks for a review of \(name) before adding it."
        default: "Adding \(name) was cancelled."
        }
        report(text)
        if hasRead { refresh() }
    }

    private func report(_ message: String, isError: Bool = false) {
        output = message
        self.isError = isError
    }

    #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
    static func summary(_ pass: PKPass) -> WalletPassSummary {
        WalletPassSummary(id: pass.passTypeIdentifier + "/" + pass.serialNumber, name: pass.localizedName, organization: pass.organizationName,
                          detail: pass.localizedDescription, passTypeIdentifier: pass.passTypeIdentifier, serialNumber: pass.serialNumber,
                          kind: pass.passType == .secureElement ? "Secure Element pass" : "Barcode pass",
                          location: pass.isRemotePass ? "On \(pass.deviceName)" : "On this device")
    }
    #endif
}

/// Options for the Apple Pay experiment. Only enumerable values, picked in the UI.
nonisolated enum ApplePayOptions {
    /// Clearly not a registered Merchant ID: Apple Pay rejects it unless an identical ID is in the app's entitlement.
    static let placeholderMerchantID = "merchant.com.example.apple-toolbox.placeholder"

    enum Region: String, CaseIterable, Identifiable, Sendable {
        case germany = "Germany · EUR"
        case unitedStates = "United States · USD"
        case unitedKingdom = "United Kingdom · GBP"
        case japan = "Japan · JPY"
        case switzerland = "Switzerland · CHF"

        var id: String { rawValue }
        var countryCode: String {
            switch self { case .germany: "DE"; case .unitedStates: "US"; case .unitedKingdom: "GB"; case .japan: "JP"; case .switzerland: "CH" }
        }
        var currencyCode: String {
            switch self { case .germany: "EUR"; case .unitedStates: "USD"; case .unitedKingdom: "GBP"; case .japan: "JPY"; case .switzerland: "CHF" }
        }
        /// Japanese yen has no minor unit, so the demo amount has none either.
        var demoAmount: String { self == .japan ? "1" : "0.01" }
    }

    enum Network: String, CaseIterable, Identifiable, Sendable {
        case visa = "Visa", masterCard = "Mastercard", amex = "American Express", discover = "Discover", maestro = "Maestro"
        case girocard = "girocard", cartesBancaires = "Cartes Bancaires", jcb = "JCB", chinaUnionPay = "China UnionPay", interac = "Interac"
        case eftpos = "eftpos", suica = "Suica", quicPay = "QUICPay", idCredit = "iD", vPay = "V PAY", electron = "Visa Electron"

        var id: String { rawValue }
    }

    enum ButtonType: String, CaseIterable, Identifiable, Sendable {
        case plain = "Plain", buy = "Buy", setUp = "Set Up", inStore = "In Store", donate = "Donate", checkout = "Check Out", book = "Book"
        case subscribe = "Subscribe", reload = "Reload", addMoney = "Add Money", topUp = "Top Up", order = "Order", rent = "Rent"
        case support = "Support", contribute = "Contribute", tip = "Tip", continueButton = "Continue"

        var id: String { rawValue }
    }

    enum ButtonStyle: String, CaseIterable, Identifiable, Sendable {
        case automatic = "Automatic", black = "Black", white = "White", whiteOutline = "White Outline"
        var id: String { rawValue }
    }
}

nonisolated struct PaymentNetworkResult: Identifiable, Equatable, Sendable {
    let network: ApplePayOptions.Network
    let canMakePayments: Bool
    var id: String { network.id }
}

/// Apple Pay (spec §25 Payments): canMakePayments per network, the payment button styles, and a real PKPaymentRequest
/// through PKPaymentAuthorizationController. No payment processor exists here, so an authorized payment is always declined.
@MainActor
final class ApplePayService: NSObject, ObservableObject {
    @Published var region: ApplePayOptions.Region = .germany
    @Published var buttonType: ApplePayOptions.ButtonType = .buy
    @Published var buttonStyle: ApplePayOptions.ButtonStyle = .automatic
    @Published private(set) var canMakePayments: Bool?
    @Published private(set) var networks: [PaymentNetworkResult] = []
    @Published private(set) var isPresenting = false
    @Published private(set) var output = "Check the payment networks or start the payment sheet."
    @Published private(set) var isError = false
    #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
    private var controller: PKPaymentAuthorizationController?
    #endif

    var merchantEntitlement: ProvisioningState { IdentityEntitlements.state(ofCapability: "apple-pay") }

    func checkNetworks() {
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        let general = PKPaymentAuthorizationController.canMakePayments()
        canMakePayments = general
        networks = ApplePayOptions.Network.allCases.map {
            PaymentNetworkResult(network: $0, canMakePayments: PKPaymentAuthorizationController.canMakePayments(usingNetworks: [$0.paymentNetwork]))
        }
        let usable = networks.filter(\.canMakePayments).map(\.network.rawValue)
        report("canMakePayments(): \(general)\n" + (usable.isEmpty
            ? "canMakePayments(usingNetworks:) is false for every listed network: no card of these networks is in Wallet, or payments are restricted."
            : "Cards available for: \(usable.joined(separator: ", "))."))
        #else
        report("Apple Pay is not available on this platform.", isError: true)
        #endif
    }

    func pay() {
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        guard !isPresenting else { return }
        let request = PKPaymentRequest()
        request.merchantIdentifier = ApplePayOptions.placeholderMerchantID
        request.countryCode = region.countryCode
        request.currencyCode = region.currencyCode
        request.supportedNetworks = ApplePayOptions.Network.allCases.map(\.paymentNetwork)
        request.merchantCapabilities = .threeDSecure
        request.paymentSummaryItems = [
            PKPaymentSummaryItem(label: "Apple Toolbox demo (never charged)", amount: NSDecimalNumber(string: region.demoAmount), type: .final),
        ]
        let controller = PKPaymentAuthorizationController(paymentRequest: request)
        controller.delegate = self
        self.controller = controller
        isPresenting = true
        report("Presenting the payment sheet for \(region.demoAmount) \(region.currencyCode) with merchant ID \(ApplePayOptions.placeholderMerchantID)…")
        controller.present { @Sendable [weak self] presented in
            Task { @MainActor in self?.presentationFinished(presented) }
        }
        #else
        report("Apple Pay is not available on this platform.", isError: true)
        #endif
    }

    private func presentationFinished(_ presented: Bool) {
        guard !presented else { return }
        isPresenting = false
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        controller = nil
        #endif
        let entitlement = IdentityEntitlements.summary(of: merchantEntitlement, key: "com.apple.developer.in-app-payments")
        report("present(completion:) returned false: PassKit did not show the payment sheet. The placeholder merchant identifier is not a Merchant ID registered for this app, and canMakePayments may be false.\n\(entitlement)", isError: true)
    }

    private func report(_ message: String, isError: Bool = false) {
        output = message
        self.isError = isError
    }
}

#if canImport(PassKit) && !os(watchOS) && !os(tvOS)
extension ApplePayService: PKPaymentAuthorizationControllerDelegate {
    func paymentAuthorizationController(_ controller: PKPaymentAuthorizationController, didAuthorizePayment payment: PKPayment,
                                        handler completion: @escaping (PKPaymentAuthorizationResult) -> Void) {
        // There is no payment processor behind the placeholder merchant: the token is neither sent anywhere nor charged.
        let method = payment.token.paymentMethod
        let error = NSError(domain: PKPaymentErrorDomain, code: PKPaymentError.unknownError.rawValue,
                            userInfo: [NSLocalizedDescriptionKey: "Apple Toolbox has no payment processor. Nothing was charged."])
        completion(PKPaymentAuthorizationResult(status: .failure, errors: [error]))
        report("The person authorized the sheet. Payment method: \(method.displayName ?? "—") · network \(method.network?.rawValue ?? "—") · \(Self.typeName(method.type)).\nToken: \(payment.token.paymentData.count) bytes of encrypted payment data for a processor. It was discarded and the payment declined, because no processor exists here.")
    }

    func paymentAuthorizationControllerDidFinish(_ controller: PKPaymentAuthorizationController) {
        controller.dismiss(completion: nil)
        self.controller = nil
        isPresenting = false
        if !output.hasPrefix("The person authorized") {
            report("The payment sheet closed without an authorization. Without a registered Merchant ID and payment processing certificate the sheet cannot complete a payment.")
        }
    }

    #if os(macOS)
    /// Required on macOS: the window the payment sheet attaches to.
    func presentationWindow(for controller: PKPaymentAuthorizationController) -> NSWindow? {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first
    }
    #endif

    private static func typeName(_ type: PKPaymentMethodType) -> String {
        switch type {
        case .debit: "debit"
        case .credit: "credit"
        case .prepaid: "prepaid"
        case .store: "store card"
        case .eMoney: "e-money"
        default: "unknown type"
        }
    }
}

extension ApplePayOptions.Network {
    var paymentNetwork: PKPaymentNetwork {
        switch self {
        case .visa: .visa
        case .masterCard: .masterCard
        case .amex: .amex
        case .discover: .discover
        case .maestro: .maestro
        case .girocard: .girocard
        case .cartesBancaires: .cartesBancaires
        case .jcb: .JCB
        case .chinaUnionPay: .chinaUnionPay
        case .interac: .interac
        case .eftpos: .eftpos
        case .suica: .suica
        case .quicPay: .quicPay
        case .idCredit: .idCredit
        case .vPay: .vPay
        case .electron: .electron
        }
    }
}

extension ApplePayOptions.ButtonType {
    var paymentButtonType: PKPaymentButtonType {
        switch self {
        case .plain: .plain
        case .buy: .buy
        case .setUp: .setUp
        case .inStore: .inStore
        case .donate: .donate
        case .checkout: .checkout
        case .book: .book
        case .subscribe: .subscribe
        case .reload: .reload
        case .addMoney: .addMoney
        case .topUp: .topUp
        case .order: .order
        case .rent: .rent
        case .support: .support
        case .contribute: .contribute
        case .tip: .tip
        case .continueButton: .continue
        }
    }
}

extension ApplePayOptions.ButtonStyle {
    var paymentButtonStyle: PKPaymentButtonStyle {
        switch self {
        case .automatic: .automatic
        case .black: .black
        case .white: .white
        case .whiteOutline: .whiteOutline
        }
    }
}
#endif
