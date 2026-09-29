import Foundation
import Combine

#if canImport(PassKit) && !os(watchOS) && !os(tvOS)
import PassKit
#endif
#if canImport(SecureElementCredential) && os(iOS)
import SecureElementCredential
#endif
#if canImport(ProximityReader) && os(iOS)
import ProximityReader
#endif

/// An advanced Wallet credential (spec §8 Advanced/restricted, §25 Advanced Wallet). Apps can only issue these through an
/// Apple program, so this is reference data; the live state comes from the app's own provisioning and public PassKit checks.
nonisolated struct AdvancedCredential: Identifiable, Sendable {
    let id: String
    let name: String
    let summary: String
    let frameworks: [String]
    /// The Apple program or agreement that gates the credential.
    let program: String
    /// Capability registry ids whose entitlements open a public issuing path for approved partners.
    let capabilityIDs: [String]
    /// The public API an approved issuer uses.
    let issuerAPI: String
    /// "Why doesn't this work?"
    let reason: String
    let nextStep: String
    let documentationPath: String
    /// Tap to Pay on iPhone also depends on the device model (PaymentCardReader.isSupported).
    var checksPaymentCardReader = false

    var documentationURL: URL { URL(string: "https://developer.apple.com/documentation/" + documentationPath)! }
}

nonisolated enum AdvancedCredentialCatalog {
    static let all: [AdvancedCredential] = [
        AdvancedCredential(id: "corporate-badge", name: "Corporate Badge",
            summary: "Employee badges in Apple Wallet that open doors, turnstiles and elevators with a tap.",
            frameworks: ["PassKit", "SecureElementCredential"],
            program: "Apple's employee badge program through a supported access-control provider, or the NFC & SE Platform",
            capabilityIDs: ["in-app-provisioning", "secure-element-credential"],
            issuerAPI: "Approved issuers add the badge from their app with PKAddPaymentPassViewController in the access pass style, or provision their own applet with SecureElementCredential on the NFC & SE Platform.",
            reason: "Corporate badges are provisioned by the employer's access-control provider under an agreement with Apple. This app has neither the In-App Provisioning nor the Secure Element Credential entitlement, and no public API creates a badge without one of them.",
            nextStep: "Badges come from the employer's issuing app. Developers work through a supported access-control provider or request access to the NFC & SE Platform.",
            documentationPath: "passkit/pkaddpaymentpassstyle/access"),
        AdvancedCredential(id: "access-keys", name: "Access Keys",
            summary: "Keys for residential buildings, offices, gyms and campuses, stored in the Secure Element as Wallet access passes.",
            frameworks: ["PassKit", "SecureElementCredential"],
            program: "Apple Wallet access partnership for access-control providers, or the NFC & SE Platform",
            capabilityIDs: ["contactless-pass-provisioning", "secure-element-credential"],
            issuerAPI: "Approved providers add access passes with PKAddSecureElementPassViewController and a PKAddShareablePassConfiguration (optionally requiring a Unified Access capable device), or through SecureElementCredential.",
            reason: "Access keys are issued by access-control providers Apple has approved. Without the Contactless Pass Provisioning or Secure Element Credential entitlement PassKit does not add them.",
            nextStep: "Keys are added from the provider's app. Developers request the entitlement as part of an access-control partnership with Apple.",
            documentationPath: "passkit/pkaddshareablepassconfiguration"),
        AdvancedCredential(id: "home-key", name: "Home Key",
            summary: "An NFC key for Home Key compatible smart locks, created by the Apple Home app and kept in Wallet.",
            frameworks: ["HomeKit", "SecureElementCredential"],
            program: "MFi Program for lock manufacturers; the NFC & SE Platform lists home keys for approved partners",
            capabilityIDs: ["secure-element-credential"],
            issuerAPI: "No PassKit API: the Home app creates the Home Key when a compatible lock joins the home. HomeKit only exposes the lock accessory. On the NFC & SE Platform, approved partners can provision home keys with SecureElementCredential.",
            reason: "Home Key is created by the Apple Home app for locks built under Apple's MFi Program. Third-party apps can neither add nor read a Home Key, and this app has no Secure Element Credential entitlement.",
            nextStep: "Add a Home Key compatible lock in the Home app. Lock makers build Home Key support through the MFi Program.",
            documentationPath: "secureelementcredential"),
        AdvancedCredential(id: "car-key", name: "Car Key",
            summary: "Digital car keys (CCC Digital Key) in the Secure Element that unlock and start supported vehicles and can be shared.",
            frameworks: ["PassKit", "SecureElementCredential"],
            program: "Apple's Car Key program for vehicle manufacturers (Car Connectivity Consortium Digital Key)",
            capabilityIDs: ["contactless-pass-provisioning", "secure-element-credential"],
            issuerAPI: "Car makers' apps create the key with PKAddCarKeyPassConfiguration and PKAddSecureElementPassViewController, using a one-time password from the manufacturer; PKVehicleConnectionSession exchanges data with the car.",
            reason: "Only vehicle manufacturers in Apple's Car Key program can issue car keys. The configuration needs a manufacturer one-time password and an entitlement Apple grants to those manufacturers.",
            nextStep: "Car keys are set up from the vehicle or the car maker's app. There is no developer path without a car maker partnership.",
            documentationPath: "passkit/pkaddcarkeypassconfiguration"),
        AdvancedCredential(id: "student-id", name: "Student ID",
            summary: "Contactless student IDs in Wallet for campus buildings, dining and payments at participating schools.",
            frameworks: ["PassKit", "SecureElementCredential"],
            program: "Apple's contactless student ID program through supported campus card providers",
            capabilityIDs: ["in-app-provisioning", "secure-element-credential"],
            issuerAPI: "Campus card providers provision student IDs from their app with PKAddPaymentPassViewController (In-App Provisioning) or with SecureElementCredential on the NFC & SE Platform.",
            reason: "Student IDs are only issued by schools working with an Apple-approved campus card provider. This app has no In-App Provisioning or Secure Element Credential entitlement.",
            nextStep: "Students add the ID from the school's app. Institutions work with a supported campus card provider.",
            documentationPath: "passkit/pkaddpaymentpassviewcontroller"),
        AdvancedCredential(id: "hotel-key", name: "Hotel Key",
            summary: "Room keys in Wallet from participating hotels, valid from check-in to check-out and shareable with other guests.",
            frameworks: ["PassKit", "SecureElementCredential"],
            program: "Apple Wallet hotel key partnership for hospitality and lock providers, or the NFC & SE Platform",
            capabilityIDs: ["contactless-pass-provisioning", "secure-element-credential"],
            issuerAPI: "Hotel apps add room keys with PKAddSecureElementPassViewController and a shareable pass configuration, or provision them with SecureElementCredential on the NFC & SE Platform.",
            reason: "Hotel keys come from hotels and lock vendors working with Apple. Without the Contactless Pass Provisioning or Secure Element Credential entitlement PassKit does not add them.",
            nextStep: "Guests add the key from the hotel's app. Hotels work with Apple through a supported lock or hospitality partner.",
            documentationPath: "passkit/pkaddsecureelementpassviewcontroller"),
        AdvancedCredential(id: "tap-to-pay", name: "Tap to Pay on iPhone",
            summary: "Accept contactless cards and Apple Pay on iPhone without extra hardware, through a payment service provider.",
            frameworks: ["ProximityReader"],
            program: "Tap to Pay on iPhone entitlement, requested by the Account Holder, plus a supported payment service provider",
            capabilityIDs: ["tap-to-pay"],
            issuerAPI: "ProximityReader's PaymentCardReader, prepared with a token from the payment service provider. PaymentCardReader.isSupported checks the device model.",
            reason: "Tap to Pay needs the com.apple.developer.proximity-reader.payment.acceptance entitlement, which Apple grants to organizations that integrate a supported payment service provider in supported regions.",
            nextStep: "The Account Holder requests the entitlement and integrates a supported payment service provider. The device check below runs without it.",
            documentationPath: "proximityreader/paymentcardreader", checksPaymentCardReader: true),
    ]

    /// Entitlements that let an issuer's app see and add Secure Element passes.
    static let issuerCapabilityIDs = ["in-app-provisioning", "contactless-pass-provisioning", "secure-element-credential"]

    static func credential(for id: String) -> AdvancedCredential? { all.first { $0.id == id } }
}

extension ExperimentAvailability {
    /// Secure Element passes are only revealed to their issuer's app, which needs an Apple issuer entitlement.
    static func secureElementPasses() -> ExperimentStatus {
        let library = wallet()
        guard library == .available else { return library }
        let issuer = AdvancedCredentialCatalog.issuerCapabilityIDs.contains { IdentityEntitlements.state(ofCapability: $0).isPresent }
        return issuer ? .available : .appleProgramRequired
    }

    /// An advanced credential is usable only once one of its program entitlements is provisioned.
    static func advancedCredential(_ id: String) -> ExperimentStatus {
        guard let credential = AdvancedCredentialCatalog.credential(for: id) else { return .unavailable }
        #if canImport(ProximityReader) && os(iOS)
        if credential.checksPaymentCardReader, !PaymentCardReader.isSupported { return .hardwareUnsupported }
        #endif
        if credential.checksPaymentCardReader,
           !RegionRestrictedFeature.tapToPay.isSupported(inRegion: RegionRestrictedFeature.currentRegion) { return .regionRestricted }
        return credential.capabilityIDs.contains { IdentityEntitlements.state(ofCapability: $0).isPresent } ? .available : .appleProgramRequired
    }
}

/// One live check in the advanced Wallet run views.
struct AdvancedWalletCheck: Identifiable {
    let id: String
    let title: String
    let value: String
    let passed: Bool?
}

nonisolated struct SecureElementPassSummary: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let organization: String
    let account: String
    let activation: String
    let location: String
}

/// Live checks for Secure Element passes and advanced credentials. It never creates, simulates or requests a credential.
@MainActor
final class AdvancedWalletService: ObservableObject {
    @Published private(set) var checks: [AdvancedWalletCheck] = []
    @Published private(set) var passes: [SecureElementPassSummary] = []
    @Published private(set) var hasRun = false
    @Published private(set) var output = "Run the checks to query PassKit and the app's provisioning."
    @Published private(set) var isError = false

    /// Checks for one credential, or for Secure Element passes in general when `credential` is nil.
    func inspect(_ credential: AdvancedCredential?) async {
        var checks: [AdvancedWalletCheck] = []
        let capabilityIDs = credential?.capabilityIDs ?? AdvancedCredentialCatalog.issuerCapabilityIDs
        for id in capabilityIDs {
            guard let capability = CapabilityRegistry.descriptor(for: id) else { continue }
            let state = IdentityEntitlements.state(ofCapability: id)
            checks.append(AdvancedWalletCheck(id: id, title: capability.name, value: IdentityEntitlements.summary(of: state, key: capability.keys.first ?? id), passed: state.isPresent))
        }
        var summaries: [SecureElementPassSummary] = []
        #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
        let libraryAvailable = PKPassLibrary.isPassLibraryAvailable()
        checks.append(AdvancedWalletCheck(id: "library", title: "PKPassLibrary.isPassLibraryAvailable()", value: "\(libraryAvailable)", passed: libraryAvailable))
        if libraryAvailable {
            let library = PKPassLibrary()
            let activation = library.isSecureElementPassActivationAvailable
            checks.append(AdvancedWalletCheck(id: "activation", title: "isSecureElementPassActivationAvailable", value: activation ? "true" : "false (PassKit returns false without Apple's special entitlement)", passed: activation))
            summaries = library.passes(of: .secureElement).compactMap(\.secureElementPass).map(Self.summary)
            #if os(iOS)
            summaries += library.remoteSecureElementPasses.map(Self.summary)
            #endif
            checks.append(AdvancedWalletCheck(id: "se-passes", title: "Secure Element passes visible to this app", value: "\(summaries.count)", passed: nil))
        }
        #endif
        #if canImport(SecureElementCredential) && os(iOS)
        do {
            let eligible = try await CredentialSession.isEligible
            checks.append(AdvancedWalletCheck(id: "credential-session", title: "CredentialSession.isEligible", value: eligible ? "true" : "false (NFC & SE Platform entitlement, region or device)", passed: eligible))
        } catch {
            checks.append(AdvancedWalletCheck(id: "credential-session", title: "CredentialSession.isEligible", value: "Threw: \(error.localizedDescription)", passed: false))
        }
        #endif
        #if canImport(ProximityReader) && os(iOS)
        if credential?.checksPaymentCardReader == true {
            let supported = PaymentCardReader.isSupported
            checks.append(AdvancedWalletCheck(id: "tap-to-pay-device", title: "PaymentCardReader.isSupported", value: supported ? "true (iPhone XS or later)" : "false: this device model cannot run Tap to Pay on iPhone", passed: supported))
            let region = RegionRestrictedFeature.currentRegion
            let inRegion = RegionRestrictedFeature.tapToPay.isSupported(inRegion: region)
            checks.append(AdvancedWalletCheck(id: "tap-to-pay-region", title: "Device region", value: RegionRestrictedFeature.regionDescription(region) + (inRegion ? " · Tap to Pay on iPhone is offered here" : " · not on Apple's Tap to Pay on iPhone country list"), passed: inRegion))
        }
        #endif
        self.checks = checks
        passes = summaries
        hasRun = true
        let blocked = checks.filter { $0.passed == false }.map(\.title)
        if let credential {
            let provisioned = credential.capabilityIDs.contains { IdentityEntitlements.state(ofCapability: $0).isPresent }
            report(provisioned
                ? "\(credential.name): a program entitlement is provisioned. Issuing still needs the partner's server-side credentials, which this toolbox does not have."
                : "\(credential.name) cannot be issued by this app. \(credential.reason)", isError: !provisioned)
        } else {
            report("PassKit shows this app \(summaries.count) Secure Element pass\(summaries.count == 1 ? "" : "es"). "
                + (summaries.isEmpty ? "Apps only see Secure Element passes they are associated with as issuer; without such an entitlement the list stays empty, whatever Wallet holds." : "")
                + (blocked.isEmpty ? "" : "\nNot available: \(blocked.joined(separator: ", ")).") , isError: false)
        }
    }

    private func report(_ message: String, isError: Bool) {
        output = message
        self.isError = isError
    }

    #if canImport(PassKit) && !os(watchOS) && !os(tvOS)
    static func summary(_ pass: PKSecureElementPass) -> SecureElementPassSummary {
        let activation = switch pass.passActivationState {
        case .activated: "Activated"
        case .requiresActivation: "Requires activation"
        case .activating: "Activating"
        case .suspended: "Suspended"
        case .deactivated: "Deactivated"
        @unknown default: "Unknown state"
        }
        return SecureElementPassSummary(id: pass.passTypeIdentifier + "/" + pass.serialNumber + (pass.isRemotePass ? "/remote" : ""),
                                        name: pass.localizedName, organization: pass.organizationName,
                                        account: "•••• \(pass.primaryAccountNumberSuffix) · device •••• \(pass.deviceAccountNumberSuffix)",
                                        activation: activation, location: pass.isRemotePass ? "On \(pass.deviceName)" : "On this device")
    }
    #endif
}
