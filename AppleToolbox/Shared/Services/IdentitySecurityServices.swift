import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if os(macOS)
import Security
#elseif targetEnvironment(simulator)
import MachO
#endif

enum IdentitySecurityExperimentService {
    static func passkeyStatus() -> String {
        #if canImport(AuthenticationServices)
        return "AuthenticationServices is available. Passkeys require a configured associated domain and relying-party server; this experiment does not fake a credential."
        #else
        return "AuthenticationServices is not available on this platform."
        #endif
    }
}

extension ExperimentAvailability {
    static func signInWithApple() -> ExperimentStatus {
        #if canImport(AuthenticationServices)
        IdentityEntitlements.signInWithApple.isPresent ? .available : .entitlementRequired
        #else
        .platformUnsupported
        #endif
    }
}

/// What the running app can show about an identity entitlement. The embedded provisioning profile decides; only when no
/// profile is readable (Simulator, local signing) do the entitlements the binary was signed with count, reported as `.declared`.
enum IdentityEntitlements {
    private static let lookup = ProvisioningInspector.load()

    static var signInWithApple: ProvisioningState { state(ofCapability: "sign-in-with-apple") }

    static func state(ofCapability id: String) -> ProvisioningState {
        guard let capability = CapabilityRegistry.descriptor(for: id) else { return .unknown("\(id) is not in the capability registry.") }
        let profileState = ProvisioningInspector.state(of: capability, in: lookup)
        guard case .unknown(let reason) = profileState else { return profileState }
        guard SignedEntitlements.isReadable else { return .unknown(reason) }
        return capability.keys.lazy.compactMap(SignedEntitlements.value(for:)).first.map(ProvisioningState.declared) ?? .notDeclared
    }

    static func summary(of state: ProvisioningState, key: String) -> String {
        switch state {
        case .provisioned(let value): "\(key): provisioned by the embedded profile (\(value))."
        case .notProvisioned: "\(key): not listed in the embedded provisioning profile."
        case .declared(let value): "\(key): declared in this build's signed entitlements (\(value)). No provisioning profile is embedded, so whether the App ID really has the capability only shows when the request runs."
        case .notDeclared: "\(key): no provisioning profile is embedded, and this build's signed entitlements do not include it."
        case .unknown(let reason): "\(key): cannot be checked. \(reason)"
        }
    }
}

/// Entitlements the running binary was signed with, read only where a public API exposes them: the code signature on
/// macOS and the `__TEXT,__entitlements` section Xcode links into Simulator builds. iOS, tvOS and watchOS device builds
/// carry them only in the code signature, which apps there cannot read.
enum SignedEntitlements {
    #if os(macOS)
    static let isReadable = true

    static func value(for key: String) -> String? {
        guard let task = SecTaskCreateFromSelf(nil), let value = SecTaskCopyValueForEntitlement(task, key as CFString, nil) else { return nil }
        return ProvisioningInspector.render(value)
    }
    #elseif targetEnvironment(simulator)
    private static let section = simulatorSection()
    static var isReadable: Bool { section != nil }

    static func value(for key: String) -> String? { section?[key] }

    private static func simulatorSection() -> [String: String]? {
        let bundlePath = Bundle.main.bundlePath
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index), String(cString: name).hasPrefix(bundlePath),
                  let header = _dyld_get_image_header(index) else { continue }
            var size: UInt = 0
            guard let bytes = getsectiondata(UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self), "__TEXT", "__entitlements", &size), size > 0,
                  let plist = try? PropertyListSerialization.propertyList(from: Data(bytes: bytes, count: Int(size)), format: nil) as? [String: Any]
            else { continue }
            return plist.mapValues(ProvisioningInspector.render)
        }
        return nil
    }
    #else
    static let isReadable = false

    static func value(for key: String) -> String? { nil }
    #endif
}

#if canImport(AuthenticationServices)
/// Renders an AuthenticationServices error with its code name and underlying system error, which usually names the real cause.
enum AuthorizationErrorReport {
    static func describe(_ error: Error, context: String) -> String {
        let nsError = error as NSError
        var lines = [nsError.domain == ASAuthorizationError.errorDomain
            ? "\(context) failed with ASAuthorizationError \(nsError.code) (\(name(of: nsError.code))): \(nsError.localizedDescription)"
            : "\(context) failed (\(nsError.domain) \(nsError.code)): \(nsError.localizedDescription)"]
        if let reason = nsError.localizedFailureReason { lines.append("Reason: \(reason)") }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append("Underlying: \(underlying.domain) \(underlying.code): \(underlying.localizedDescription)")
        }
        return lines.joined(separator: "\n")
    }

    private static func name(of code: Int) -> String {
        switch code {
        case 1000: "unknown"
        case 1001: "canceled"
        case 1002: "invalidResponse"
        case 1003: "notHandled"
        case 1004: "failed"
        case 1005: "notInteractive"
        case 1006: "matchedExcludedCredential"
        case 1007: "credentialImport"
        case 1008: "credentialExport"
        case 1009: "preferSignInWithApple"
        case 1010: "deviceNotConfiguredForPasskeyCreation"
        default: "unrecognized code"
        }
    }
}
#endif

/// Random bytes generated on this device. The identity labs have no server, so they use them as challenges; in production
/// the server issues every challenge and verifies the result.
enum LocalChallenge {
    static func randomBytes(_ count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    static func hexPrefix(_ data: Data, bytes: Int = 8) -> String {
        data.prefix(bytes).map { String(format: "%02x", $0) }.joined() + (data.count > bytes ? "…" : "")
    }
}
