import Foundation

nonisolated extension ImplementationGuides {
    static let wallet: [String: ImplementationGuide] = [
        "wallet-status": ImplementationGuide(
            snippet: #"""
            import PassKit
            import UIKit

            /// Checks Wallet, lists the app's own passes and offers a downloaded .pkpass for adding.
            @MainActor
            enum WalletPasses {
                static var canUseWallet: Bool {
                    PKPassLibrary.isPassLibraryAvailable() && PKAddPassesViewController.canAddPasses()
                }

                /// Only passes whose pass type ID is in the app's entitlement are returned.
                static func ownPasses() -> [PKPass] {
                    PKPassLibrary().passes(of: .any)
                }

                static func addPass(from data: Data, presenter: UIViewController) throws {
                    let pass = try PKPass(data: data)
                    if PKPassLibrary().containsPass(pass) { return }
                    guard let controller = PKAddPassesViewController(pass: pass) else { return }
                    presenter.present(controller, animated: true)
                }
            }
            """#,
            entitlements: ["com.apple.developer.pass-type-identifiers = [$(TeamIdentifierPrefix)pass.com.example.ticket]"],
            capabilities: ["Wallet"],
            notes: [
                "Adding any signed .pkpass needs no entitlement; reading passes back needs the pass type IDs you own.",
                "PKPass(data:) throws for unsigned or tampered passes; signing happens on your server.",
                "In SwiftUI, AddPassToWalletButton (iOS 16+) replaces the view controller.",
            ]
        ),
        "apple-pay": ImplementationGuide(
            snippet: #"""
            import PassKit
            import SwiftUI

            struct CheckoutButton: View {
                private var request: PKPaymentRequest {
                    let request = PKPaymentRequest()
                    request.merchantIdentifier = "merchant.com.example.shop"
                    request.countryCode = "DE"
                    request.currencyCode = "EUR"
                    request.merchantCapabilities = .threeDSecure
                    request.supportedNetworks = [.visa, .masterCard, .amex, .girocard]
                    request.paymentSummaryItems = [PKPaymentSummaryItem(label: "Example Shop", amount: 9.99)]
                    return request
                }

                var body: some View {
                    if PKPaymentAuthorizationController.canMakePayments() {
                        PayWithApplePayButton(.buy, request: request) { phase in
                            switch phase {
                            case .didAuthorize(let payment, let resultHandler):
                                // Send payment.token.paymentData to your payment processor, then report back.
                                print(payment.token.transactionIdentifier)
                                resultHandler(PKPaymentAuthorizationResult(status: .success, errors: nil))
                            default:
                                break
                            }
                        }
                        .frame(height: 48)
                    }
                }
            }
            """#,
            entitlements: ["com.apple.developer.in-app-payments = [merchant.com.example.shop]"],
            capabilities: ["Apple Pay"],
            notes: [
                "Create the Merchant ID and its Payment Processing Certificate in the developer portal (usually with your PSP).",
                "Apple Pay is only for physical goods and services; digital content must use In-App Purchase (guideline 3.1.1).",
                "Test with a Sandbox tester account on a real device; the Simulator only shows a mock sheet.",
            ]
        ),
        "wallet-creator": ImplementationGuide(
            snippet: #"""
            import CryptoKit
            import Foundation

            /// Builds the unsigned parts of a .pkpass bundle: pass.json and manifest.json.
            struct PassBundleBuilder {
                var files: [String: Data] = [:]

                mutating func addPassJSON(serial: String) throws {
                    let pass: [String: Any] = [
                        "formatVersion": 1,
                        "passTypeIdentifier": "pass.com.example.ticket",
                        "teamIdentifier": "ABCDE12345",
                        "serialNumber": serial,
                        "organizationName": "Example",
                        "description": "Event ticket",
                        "barcodes": [["format": "PKBarcodeFormatQR", "message": serial, "messageEncoding": "iso-8859-1"]],
                        "eventTicket": ["primaryFields": [["key": "event", "label": "EVENT", "value": "Swift Meetup"]]],
                    ]
                    files["pass.json"] = try JSONSerialization.data(withJSONObject: pass, options: [.sortedKeys])
                }

                /// manifest.json maps every file to its SHA-1; `signature` is a detached PKCS #7 of it.
                func manifest() throws -> Data {
                    let hashes = files.mapValues { Insecure.SHA1.hash(data: $0).map { String(format: "%02x", $0) }.joined() }
                    return try JSONSerialization.data(withJSONObject: hashes, options: [.sortedKeys])
                }
            }
            """#,
            notes: [
                "The signature must be made with your Pass Type ID certificate plus Apple's WWDR intermediate — do it on a server, never ship the key in the app.",
                "Zip pass.json, manifest.json, signature and icon.png (required) with no enclosing folder and serve it as application/vnd.apple.pkpass.",
                "passTypeIdentifier and teamIdentifier must match the signing certificate or Wallet rejects the pass.",
            ]
        ),
        "secure-element-passes": ImplementationGuide(
            snippet: #"""
            import PassKit
            import UIKit

            /// In-app provisioning of a payment card into Apple Pay (issuer apps only).
            @MainActor
            final class CardProvisioner: NSObject, @preconcurrency PKAddPaymentPassViewControllerDelegate {
                func start(from presenter: UIViewController, cardholder: String, suffix: String) {
                    guard PKAddPaymentPassViewController.canAddPaymentPass(),
                          let config = PKAddPaymentPassRequestConfiguration(encryptionScheme: .ECC_V2) else { return }
                    config.cardholderName = cardholder
                    config.primaryAccountSuffix = suffix
                    guard let controller = PKAddPaymentPassViewController(requestConfiguration: config, delegate: self) else { return }
                    presenter.present(controller, animated: true)
                }

                func addPaymentPassViewController(_ controller: PKAddPaymentPassViewController,
                                                  generateRequestWithCertificateChain certificates: [Data], nonce: Data,
                                                  nonceSignature: Data,
                                                  completionHandler handler: @escaping (PKAddPaymentPassRequest) -> Void) {
                    // Send certificates, nonce and signature to the issuer backend; it returns the encrypted card data.
                    let request = PKAddPaymentPassRequest()
                    request.encryptedPassData = Data(); request.activationData = Data(); request.ephemeralPublicKey = Data()
                    handler(request)
                }

                func addPaymentPassViewController(_ controller: PKAddPaymentPassViewController,
                                                  didFinishAdding pass: PKPaymentPass?, error: (any Error)?) {
                    controller.dismiss(animated: true)
                }
            }
            """#,
            entitlements: ["com.apple.developer.payment-pass-provisioning = true"],
            capabilities: ["In-App Provisioning (granted by Apple)"],
            notes: [
                "Apple grants the provisioning entitlement only to card issuers after a business review; without it the controller is nil.",
                "Cryptography (encryptedPassData, activationData) is produced by the issuer's backend together with the payment network.",
                "Access/ID passes use the separate Contactless Pass Provisioning or NFC & SE Platform programs (com.apple.developer.secure-element-credential).",
            ]
        ),
    ]
}
