import Foundation
import Combine

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif

/// Sign in with Apple through the system sheet (spec §8). The identity token and authorization code are never shown:
/// a real app sends both to its server, which verifies the token and redeems the code with Apple.
@MainActor
final class SignInWithAppleExperimentService: ObservableObject {
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var isCheckingState = false
    /// The stable identifier Apple returned in this session; kept in memory only.
    @Published private(set) var userID: String?
    private var credentialReport = ""

    init(initialOutput: String) {
        output = initialOutput
    }

    static var entitlementSummary: String {
        IdentityEntitlements.summary(of: IdentityEntitlements.signInWithApple, key: "com.apple.developer.applesignin")
    }

    #if canImport(AuthenticationServices)
    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        finish("Waiting for the Sign in with Apple sheet (scopes: full name, email)…")
    }

    func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            userID = nil
            credentialReport = ""
            finish(AuthorizationErrorReport.describe(error, context: "Sign in with Apple") + Self.hint(for: error), isError: true)
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                return finish("The system returned an unexpected credential type: \(type(of: authorization.credential)).", isError: true)
            }
            userID = credential.user
            credentialReport = Self.report(for: credential)
            finish(credentialReport)
            Task { await checkCredentialState() }
        }
    }

    func checkCredentialState() async {
        guard let userID else { return }
        isCheckingState = true
        defer { isCheckingState = false }
        do {
            let state = try await ASAuthorizationAppleIDProvider().credentialState(forUserID: userID)
            let text = switch state {
            case .authorized: "authorized (the Apple Account still authorizes this app)"
            case .revoked: "revoked (the person stopped using Sign in with Apple for this app)"
            case .notFound: "notFound (no credential exists for this user identifier)"
            case .transferred: "transferred (the app moved to another team; the user must be migrated)"
            @unknown default: "unrecognized state \(state.rawValue)"
            }
            finish(credentialReport + "\nCredential state (getCredentialState): \(text)")
        } catch {
            finish(credentialReport + "\n" + AuthorizationErrorReport.describe(error, context: "Credential state query"), isError: true)
        }
    }

    private static func report(for credential: ASAuthorizationAppleIDCredential) -> String {
        let realUser = switch credential.realUserStatus {
        case .likelyReal: "likelyReal (Apple has high confidence that this is a real person)"
        case .unknown: "unknown (no signal; treat the account like any new user)"
        case .unsupported: "unsupported (not available on this platform; ignore the value)"
        @unknown default: "unrecognized value \(credential.realUserStatus.rawValue)"
        }
        let hasName = [credential.fullName?.givenName, credential.fullName?.familyName].contains { $0?.isEmpty == false }
        let email = credential.email.map { $0.hasSuffix("privaterelay.appleid.com") ? "returned (private relay address)" : "returned (shared address)" }
        return """
        Signed in with Apple.
        User identifier: \(shortened(credential.user)) (shortened; stable for this developer team)
        Real user status: \(realUser)
        Full name: \(hasName ? "returned" : "not returned")
        Email: \(email ?? "not returned")
          Apple shares name and email only on the first authorization; later sign-ins return the identifier only.
        Identity token: \(credential.identityToken.map { "returned, \($0.count) bytes (JWT, not shown)" } ?? "not returned")
        Authorization code: \(credential.authorizationCode.map { "returned, \($0.count) bytes (single use and short-lived, not shown)" } ?? "not returned")
        """
    }

    private static func shortened(_ identifier: String) -> String {
        identifier.count > 12 ? "\(identifier.prefix(6))…\(identifier.suffix(4))" : identifier
    }

    private static func hint(for error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == ASAuthorizationError.errorDomain else { return "" }
        switch nsError.code {
        case ASAuthorizationError.Code.unknown.rawValue:
            return "\nTypical causes: the signed app lacks the Sign in with Apple entitlement, or no Apple Account is signed in on this device."
        case ASAuthorizationError.Code.canceled.rawValue:
            return "\nThe sheet was closed without signing in."
        default:
            return ""
        }
    }
    #endif

    private func finish(_ text: String, isError: Bool = false) {
        output = text
        self.isError = isError
    }
}
