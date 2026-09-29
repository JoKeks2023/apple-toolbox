import Foundation

nonisolated extension ImplementationGuides {
    static let security: [String: ImplementationGuide] = [
        "localauthentication": ImplementationGuide(
            snippet: #"""
            import LocalAuthentication

            /// Asks for Face ID / Touch ID, falling back to the device passcode.
            func authenticateOwner(reason: String) async -> Bool {
                let context = LAContext()
                context.localizedCancelTitle = "Not Now"
                var error: NSError?
                guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
                    print("Authentication unavailable: \(error?.localizedDescription ?? "unknown")")
                    return false
                }
                do {
                    return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
                } catch let error as LAError where error.code == .userCancel {
                    return false
                } catch {
                    print("Authentication failed: \(error)")
                    return false
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSFaceIDUsageDescription", value: "Unlocks your private notes with Face ID."),
            ],
            notes: [
                "Without NSFaceIDUsageDescription the app crashes the first time it evaluates a Face ID policy.",
                "A successful evaluation is only a local yes/no; to protect data, store it in the Keychain with SecAccessControl instead.",
                "Check context.biometryType after canEvaluatePolicy to label the button (Face ID, Touch ID, Optic ID).",
            ]
        ),
        "cryptokit": ImplementationGuide(
            snippet: #"""
            import CryptoKit
            import Foundation

            /// Encrypts with AES-GCM and signs with P-256 — the two most common CryptoKit jobs.
            enum Crypto {
                static func encrypt(_ plaintext: Data, key: SymmetricKey) throws -> Data {
                    // `combined` = nonce + ciphertext + tag; non-nil for the default 12-byte nonce.
                    try AES.GCM.seal(plaintext, using: key).combined!
                }

                static func decrypt(_ combined: Data, key: SymmetricKey) throws -> Data {
                    try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key)
                }

                static func signAndVerify(_ message: Data) throws -> Bool {
                    let privateKey = P256.Signing.PrivateKey()
                    let signature = try privateKey.signature(for: message)
                    return privateKey.publicKey.isValidSignature(signature, for: message)
                }
            }

            let key = SymmetricKey(size: .bits256)
            """#,
            notes: [
                "Never reuse a nonce with the same key; let AES.GCM.seal pick a random one.",
                "Persist keys in the Keychain (key.withUnsafeBytes / rawRepresentation), not in UserDefaults or files.",
                "Uses of encryption may need an export compliance answer in App Store Connect (ITSAppUsesNonExemptEncryption).",
            ]
        ),
        "keychain": ImplementationGuide(
            snippet: #"""
            import Foundation
            import Security

            /// Stores a secret that can only be read after Face ID / Touch ID / passcode.
            enum SecretStore {
                static func save(_ secret: Data, account: String) throws {
                    let access = SecAccessControlCreateWithFlags(
                        nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .userPresence, nil)!
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: account,
                        kSecAttrAccessControl as String: access,
                        kSecValueData as String: secret,
                    ]
                    SecItemDelete(query.filter { $0.key != kSecValueData as String } as CFDictionary)
                    let status = SecItemAdd(query as CFDictionary, nil)
                    guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
                }

                /// Blocks while the system prompt is shown: call it off the main thread.
                static func load(account: String) throws -> Data {
                    let query: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrAccount as String: account,
                        kSecReturnData as String: true,
                        kSecMatchLimit as String: kSecMatchLimitOne,
                    ]
                    var result: CFTypeRef?
                    let status = SecItemCopyMatching(query as CFDictionary, &result)
                    guard status == errSecSuccess, let data = result as? Data else {
                        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
                    }
                    return data
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSFaceIDUsageDescription", value: "Unlocks your saved password with Face ID."),
            ],
            notes: [
                "SecItemCopyMatching on a protected item blocks until the user answers the prompt; never call it on the main thread.",
                "Keychain items survive app deletion on iOS; clear them on first launch if that is not what you want.",
                "errSecDuplicateItem (-25299) means you need SecItemUpdate or a delete first.",
            ]
        ),
        "secure-enclave": ImplementationGuide(
            snippet: #"""
            import CryptoKit
            import Foundation
            import Security

            /// Creates a P-256 signing key that never leaves the Secure Enclave.
            enum EnclaveSigner {
                static func makeKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
                    guard SecureEnclave.isAvailable else { throw CryptoKitError.underlyingCoreCryptoError(error: 0) }
                    var error: Unmanaged<CFError>?
                    guard let access = SecAccessControlCreateWithFlags(
                        nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, [.privateKeyUsage, .biometryCurrentSet], &error
                    ) else { throw error!.takeRetainedValue() as Error }
                    return try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
                }

                /// `dataRepresentation` is an encrypted blob only this device's enclave can use; store it in the Keychain.
                static func restore(_ blob: Data) throws -> SecureEnclave.P256.Signing.PrivateKey {
                    try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob)
                }

                static func sign(_ message: Data, with key: SecureEnclave.P256.Signing.PrivateKey) throws -> Data {
                    try key.signature(for: message).derRepresentation // prompts for biometrics
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSFaceIDUsageDescription", value: "Confirms it is you before signing in."),
            ],
            notes: [
                "Only P-256 keys are supported; the Simulator has no Secure Enclave (SecureEnclave.isAvailable is false).",
                ".biometryCurrentSet invalidates the key when fingerprints/faces change — plan a re-enrolment path.",
                "Signing prompts for biometrics synchronously; do it off the main thread.",
            ]
        ),
        "app-attest": ImplementationGuide(
            snippet: #"""
            import CryptoKit
            import DeviceCheck
            import Foundation

            /// Proves to your server that requests come from a genuine copy of your app.
            enum Attestation {
                /// Once per install: create a key, attest it with a server challenge, send keyID + attestation to the server.
                static func attest(serverChallenge: Data) async throws -> (keyID: String, attestation: Data) {
                    let service = DCAppAttestService.shared
                    guard service.isSupported else { throw DCError(.featureUnsupported) }
                    let keyID = try await service.generateKey()
                    let hash = Data(SHA256.hash(data: serverChallenge))
                    let attestation = try await service.attestKey(keyID, clientDataHash: hash)
                    return (keyID, attestation)
                }

                /// Per request: sign the request body; the server checks it against the attested public key.
                static func assertion(keyID: String, requestBody: Data) async throws -> Data {
                    let hash = Data(SHA256.hash(data: requestBody))
                    return try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: hash)
                }
            }
            """#,
            entitlements: ["com.apple.developer.devicecheck.appattest-environment = production"],
            capabilities: ["App Attest"],
            notes: [
                "Verification happens on your server (Apple's attestation certificate chain, counter, App ID hash); the client alone proves nothing.",
                "Not supported in the Simulator or in app extensions on older OS versions — always check isSupported and degrade gracefully.",
                "Without the entitlement, development builds use the sandbox environment; ship with production.",
            ]
        ),
        "passkeys": ImplementationGuide(
            snippet: #"""
            import AuthenticationServices
            import SwiftUI

            /// Registers and signs in with a passkey via SwiftUI's authorization controller.
            struct PasskeyButtons: View {
                @Environment(\.authorizationController) private var authorizationController
                private let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")

                var body: some View {
                    VStack {
                        Button("Create passkey") { Task { await register(challenge: Data(), userID: Data("user-42".utf8)) } }
                        Button("Sign in") { Task { await signIn(challenge: Data()) } }
                    }
                }

                // Challenges must come from your server.
                private func register(challenge: Data, userID: Data) async {
                    let request = provider.createCredentialRegistrationRequest(challenge: challenge, name: "jane@example.com", userID: userID)
                    if case .passkeyRegistration(let credential) = try? await authorizationController.performRequest(request) {
                        print("Send attestation to server:", credential.rawAttestationObject ?? Data())
                    }
                }

                private func signIn(challenge: Data) async {
                    let request = provider.createCredentialAssertionRequest(challenge: challenge)
                    if case .passkeyAssertion(let credential) = try? await authorizationController.performRequest(request) {
                        print("Send signature to server:", credential.signature ?? Data())
                    }
                }
            }
            """#,
            entitlements: ["com.apple.developer.associated-domains = [webcredentials:example.com]"],
            capabilities: ["Associated Domains"],
            notes: [
                "The relying-party domain must serve /.well-known/apple-app-site-association listing your TEAMID.bundleID under webcredentials.",
                "The server generates challenges and verifies attestations/assertions (WebAuthn); never create challenges on the device.",
                "Apple's CDN caches the association file; add ?mode=developer to the entitlement while iterating.",
            ]
        ),
        "sign-in-with-apple": ImplementationGuide(
            snippet: #"""
            import AuthenticationServices
            import SwiftUI

            struct SignInView: View {
                var body: some View {
                    SignInWithAppleButton(.signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        switch result {
                        case .success(let authorization):
                            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else { return }
                            // Name and email arrive only on the first sign-in: store them now.
                            print(credential.user, credential.fullName ?? PersonNameComponents(), credential.email ?? "")
                            // Send credential.identityToken to your server to verify it.
                        case .failure(let error):
                            print("Sign in failed: \(error)")
                        }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 44)
                }
            }

            /// Call on launch: the user may have revoked access in Settings.
            func isStillSignedIn(userID: String) async -> Bool {
                (try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)) == .authorized
            }
            """#,
            entitlements: ["com.apple.developer.applesignin = [Default]"],
            capabilities: ["Sign in with Apple"],
            notes: [
                "Full name and email are delivered only once, on the very first authorization; persist them immediately.",
                "App Review (4.8) requires Sign in with Apple, or an equivalent private option, when you offer third-party social login.",
                "Verify identityToken (a JWT) on your server against Apple's public keys; the client result alone is not proof.",
            ]
        ),
        "keychain-sharing": ImplementationGuide(
            snippet: #"""
            import Foundation
            import Security

            /// Writes an item that other apps of the same team (and optionally other devices) can read.
            enum SharedKeychain {
                /// Full group name: your Team ID prefix plus the group listed in the entitlement.
                static let accessGroup = "ABCDE12345.com.example.shared"

                static func save(token: Data, account: String, syncToICloud: Bool) -> OSStatus {
                    let base: [String: Any] = [
                        kSecClass as String: kSecClassGenericPassword,
                        kSecAttrService as String: "com.example.auth",
                        kSecAttrAccount as String: account,
                        kSecAttrAccessGroup as String: accessGroup,
                        kSecAttrSynchronizable as String: syncToICloud,
                        kSecUseDataProtectionKeychain as String: true,
                    ]
                    SecItemDelete(base as CFDictionary)
                    var item = base
                    item[kSecValueData as String] = token
                    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
                    return SecItemAdd(item as CFDictionary, nil)
                }
            }
            """#,
            entitlements: ["keychain-access-groups = [$(AppIdentifierPrefix)com.example.shared]"],
            capabilities: ["Keychain Sharing"],
            notes: [
                "All apps must share the same Team ID; the group name at runtime includes the Team ID prefix.",
                "Synchronizable items require an accessibility class without ThisDeviceOnly and iCloud Keychain turned on by the user.",
                "App Groups (com.apple.security.application-groups) can also be used as keychain access groups.",
            ]
        ),
        "security-keys": ImplementationGuide(
            snippet: #"""
            import AuthenticationServices
            import SwiftUI

            /// Signs in with a physical FIDO2 security key (NFC, USB or Lightning).
            struct SecurityKeySignIn: View {
                @Environment(\.authorizationController) private var authorizationController

                var body: some View {
                    Button("Use security key") { Task { await signIn(challenge: Data()) } }
                }

                private func signIn(challenge: Data) async { // challenge comes from your server
                    let provider = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: "example.com")
                    let request = provider.createCredentialAssertionRequest(challenge: challenge)
                    request.userVerificationPreference = .preferred
                    do {
                        let result = try await authorizationController.performRequest(request)
                        if case .securityKeyAssertion(let credential) = result {
                            print("Verify on server:", credential.signature ?? Data(), credential.credentialID)
                        }
                    } catch {
                        print("Security key sign-in failed: \(error)")
                    }
                }
            }
            """#,
            entitlements: ["com.apple.developer.associated-domains = [webcredentials:example.com]"],
            capabilities: ["Associated Domains"],
            notes: [
                "Same webcredentials association as passkeys; register keys with createCredentialRegistrationRequest first.",
                "Offer security keys alongside platform passkeys in one controller request so the system sheet shows both.",
                "NFC keys need an NFC iPhone; USB-C/Lightning keys work on iPad too.",
            ]
        ),
        "credential-provider": ImplementationGuide(
            snippet: #"""
            import AuthenticationServices

            /// Principal class of the AutoFill Credential Provider extension.
            final class CredentialProviderViewController: ASCredentialProviderViewController {
                /// QuickType bar: return the credential without UI when you can (e.g. unlocked vault).
                override func provideCredentialWithoutUserInteraction(for credentialRequest: any ASCredentialRequest) {
                    guard let identity = credentialRequest.credentialIdentity as? ASPasswordCredentialIdentity,
                          let password = lookUpPassword(recordID: identity.recordIdentifier) else {
                        extensionContext.cancelRequest(withError: ASExtensionError(.userInteractionRequired))
                        return
                    }
                    extensionContext.completeRequest(withSelectedCredential: ASPasswordCredential(user: identity.user, password: password))
                }

                private func lookUpPassword(recordID: String?) -> String? { nil } // read your shared vault here
            }

            /// In the containing app: tell the system which logins you can fill.
            func publishIdentities() async throws {
                let service = ASCredentialServiceIdentifier(identifier: "example.com", type: .domain)
                let identity = ASPasswordCredentialIdentity(serviceIdentifier: service, user: "jane", recordIdentifier: "1")
                try await ASCredentialIdentityStore.shared.replaceCredentialIdentities([identity])
            }
            """#,
            infoPlist: [
                .init(key: "NSExtension", value: "<dict><key>NSExtensionPointIdentifier</key><string>com.apple.authentication-services-credential-provider-ui</string><key>NSExtensionPrincipalClass</key><string>$(PRODUCT_MODULE_NAME).CredentialProviderViewController</string><key>NSExtensionAttributes</key><dict><key>ASCredentialProviderExtensionCapabilities</key><dict><key>ProvidesPasswords</key><true/><key>ProvidesPasskeys</key><true/></dict></dict></dict>"),
            ],
            entitlements: [
                "com.apple.developer.authentication-services.autofill-credential-provider = true (app and extension)",
                "com.apple.security.application-groups = [group.com.example.vault]",
            ],
            capabilities: ["AutoFill Credential Provider", "App Groups"],
            notes: [
                "The user must enable your app in Settings › General › AutoFill & Passwords; iOS 18 can ask via ASSettingsHelper.requestToTurnOnCredentialProviderExtension().",
                "The extension runs in its own process with a tight memory limit; share the vault through an App Group and keychain group.",
                "Keep the identity store in sync after every vault change, or QuickType suggestions go stale.",
            ]
        ),
    ]
}
