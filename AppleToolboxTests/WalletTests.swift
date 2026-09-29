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
