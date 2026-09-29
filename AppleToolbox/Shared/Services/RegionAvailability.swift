import Foundation

/// Features Apple only offers in some regions, checked against the device region (`Locale.current.region`).
///
/// The device region is the setting under Settings › General › Language & Region. It is a proxy: Apple decides HCE
/// eligibility by the Apple Account region (`CardSession.isEligible` is the authoritative, asynchronous answer) and Tap
/// to Pay by the merchant's payment service provider. The lists are snapshots of Apple's published availability.
enum RegionRestrictedFeature: String, CaseIterable {
    /// CoreNFC CardSession for contactless transactions: European Economic Area (EU 27 plus Iceland, Liechtenstein, Norway).
    case hostCardEmulation
    /// ProximityReader PaymentCardReader: countries listed on Apple's Tap to Pay on iPhone page.
    case tapToPay

    static let europeanEconomicArea: Set<String> = [
        "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT", "LV", "LT", "LU",
        "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO",
    ]

    static let tapToPayCountries: Set<String> = [
        "AE", "AT", "AU", "BE", "BR", "CA", "CH", "CZ", "DE", "DK", "ES", "FI", "FR", "GB", "HK", "IE", "IT", "JP",
        "MY", "NL", "NO", "NZ", "PL", "SA", "SE", "SG", "TW", "UA", "US",
    ]

    var supportedRegions: Set<String> {
        switch self {
        case .hostCardEmulation: Self.europeanEconomicArea
        case .tapToPay: Self.tapToPayCountries
        }
    }

    /// `nil` region (no region set) is not treated as restricted: the device cannot tell, so the live APIs decide.
    func isSupported(inRegion region: String?) -> Bool {
        guard let region, !region.isEmpty else { return true }
        return supportedRegions.contains(region.uppercased())
    }

    /// Returns `.regionRestricted` outside the supported regions, otherwise `status` unchanged.
    func status(region: String?, otherwise status: @autoclosure () -> ExperimentStatus) -> ExperimentStatus {
        isSupported(inRegion: region) ? status() : .regionRestricted
    }

    static var currentRegion: String? { Locale.current.region?.identifier }

    static func regionDescription(_ region: String?) -> String {
        guard let region else { return "no region set" }
        let name = Locale.current.localizedString(forRegionCode: region) ?? region
        return "\(name) (\(region))"
    }
}

/// Apple Intelligence reports locale support itself (`SystemLanguageModel.supportsLocale(_:)`).
enum AppleIntelligenceRegionMapping {
    /// An available model whose language/region combination is unsupported is region restricted; other states pass through.
    static func status(modelStatus: ExperimentStatus, supportsCurrentLocale: Bool) -> ExperimentStatus {
        guard modelStatus == .available else { return modelStatus }
        return supportsCurrentLocale ? .available : .regionRestricted
    }
}
