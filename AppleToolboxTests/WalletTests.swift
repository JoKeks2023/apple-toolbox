import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct WalletPaymentTests {

    @Test func placeholderMerchantIsClearlyLabelled() {
        #expect(ApplePayOptions.placeholderMerchantID.hasPrefix("merchant."))
        #expect(ApplePayOptions.placeholderMerchantID.contains("placeholder"))
    }

    @Test func regionsUseISOCodes() throws {
        for region in ApplePayOptions.Region.allCases {
            #expect(region.countryCode.count == 2 && region.countryCode == region.countryCode.uppercased(), "\(region)")
            #expect(Locale.Currency.isoCurrencies.contains(Locale.Currency(region.currencyCode)), "\(region)")
            let amount = try #require(Decimal(string: region.demoAmount))
            #expect(amount > 0, "\(region)")
        }
        #expect(!ApplePayOptions.Region.japan.demoAmount.contains("."))
    }

    @Test func pickerOptionsAreUnique() {
        #expect(Set(ApplePayOptions.Network.allCases.map(\.rawValue)).count == ApplePayOptions.Network.allCases.count)
        #expect(Set(ApplePayOptions.ButtonType.allCases.map(\.rawValue)).count == ApplePayOptions.ButtonType.allCases.count)
        #expect(Set(ApplePayOptions.ButtonStyle.allCases.map(\.rawValue)).count == ApplePayOptions.ButtonStyle.allCases.count)
    }

    @Test func passKitErrorsAreNamed() {
        #expect(PassKitErrorText.describe(code: 1, message: "x").contains("invalid data"))
        #expect(PassKitErrorText.describe(code: 3, message: "x").contains("signature"))
        #expect(PassKitErrorText.describe(code: 4, message: "x").contains("not entitled"))
        #expect(PassKitErrorText.describe(code: 99, message: "x").contains("unknown"))
    }

    @Test func walletCapabilitiesPointToTheirExperiments() {
        #expect(CapabilityRegistry.descriptor(for: "apple-pay")?.experimentID == "apple-pay")
        #expect(CapabilityRegistry.descriptor(for: "wallet")?.experimentID == "wallet-status")
        #expect(ExperimentRegistry.descriptor(for: "apple-pay")?.entitlements.contains("com.apple.developer.in-app-payments") == true)
    }
}

struct WalletPassJSONTests {

    @Test func boardingPassHasTransitTypeAndStructure() throws {
        var draft = WalletPassDraft()
        draft.style = .boardingPass
        draft.transitType = .train
        let pass = WalletPassJSON.build(draft)
        let structure = try #require(pass["boardingPass"] as? [String: Any])
        #expect(structure["transitType"] as? String == "PKTransitTypeTrain")
        #expect((structure["primaryFields"] as? [[String: String]])?.count == 2)
        #expect(pass["generic"] == nil)
    }

    @Test func everyStyleUsesItsOwnKey() {
        for style in WalletPassStyle.allCases {
            var draft = WalletPassDraft()
            draft.style = style
            let pass = WalletPassJSON.build(draft)
            #expect(pass[style.rawValue] is [String: Any])
            let structure = pass[style.rawValue] as? [String: Any]
            #expect((structure?["transitType"] != nil) == (style == .boardingPass))
        }
    }

    @Test func optionalRelevanceKeys() throws {
        var draft = WalletPassDraft()
        #expect(WalletPassJSON.build(draft)["locations"] == nil)
        draft.includeLocation = true
        draft.includeBeacon = true
        draft.beaconUUID = "e2c56db5-dffb-48d2-b060-d0f5a71096e0"
        draft.includeRelevantDate = true
        draft.relevantDate = Date(timeIntervalSince1970: 0)
        let pass = WalletPassJSON.build(draft)
        #expect((pass["locations"] as? [[String: Any]])?.count == 1)
        let beacon = try #require((pass["beacons"] as? [[String: Any]])?.first)
        #expect(beacon["proximityUUID"] as? String == "E2C56DB5-DFFB-48D2-B060-D0F5A71096E0")
        #expect(pass["relevantDate"] as? String == "1970-01-01T00:00:00Z")
        #expect(pass["webServiceURL"] == nil && pass["nfc"] == nil)
    }

    @Test func reportsInvalidDrafts() {
        var draft = WalletPassDraft()
        #expect(WalletPassJSON.issues(draft).isEmpty)
        draft.includeBeacon = true
        draft.beaconUUID = "not-a-uuid"
        draft.includeLocation = true
        draft.latitude = 120
        #expect(WalletPassJSON.issues(draft).count == 2)
    }
}
