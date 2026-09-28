import Foundation

/// One pre-run check shown before an experiment runs (spec §37).
struct ExperimentCheck: Identifiable {
    enum Outcome { case passed, pending, failed, notApplicable }

    let id: String
    let title: String
    let detail: String
    let outcome: Outcome
}

extension ExperimentDescriptor {
    /// Platform, OS, hardware, permission and entitlement checks derived from the descriptor and its live status.
    func checks(for status: ExperimentStatus) -> [ExperimentCheck] {
        let platform = CurrentPlatform.value
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(platform.rawValue) \(version.majorVersion).\(version.minorVersion)"
        var checks: [ExperimentCheck] = []

        let platformSupported = supportedPlatforms.contains(platform)
        checks.append(ExperimentCheck(id: "platform", title: "Platform",
            detail: platformSupported ? "Supported on \(platform.rawValue)" : "Supported on \(supportedPlatforms.map(\.rawValue).joined(separator: ", ")) only",
            outcome: platformSupported ? .passed : .failed))

        checks.append(ExperimentCheck(id: "os", title: "Operating system",
            detail: "Running \(osVersion) · requires \(osRequirements.joined(separator: ", "))",
            outcome: status == .osUnsupported ? .failed : .passed))

        if !hardwareRequirements.isEmpty {
            let failed = status == .hardwareUnsupported
            checks.append(ExperimentCheck(id: "hardware", title: "Hardware",
                detail: (failed ? "Missing: " : "No blocker detected · ") + hardwareRequirements.joined(separator: ", "),
                outcome: failed ? .failed : .passed))
        }

        if !permissions.isEmpty {
            let outcome: ExperimentCheck.Outcome = switch status {
            case .permissionRequired: .pending
            case .permissionDenied: .failed
            default: .passed
            }
            let state = switch outcome {
            case .pending: "Not granted yet"
            case .failed: "Denied or restricted"
            default: "Granted or not required right now"
            }
            checks.append(ExperimentCheck(id: "permission", title: "Permissions", detail: "\(state) · \(permissions.joined(separator: ", "))", outcome: outcome))
        }

        if !entitlements.isEmpty {
            let blocked = [.entitlementRequired, .approvalRequired, .appleProgramRequired].contains(status)
            checks.append(ExperimentCheck(id: "entitlement", title: "Entitlements",
                detail: (blocked ? "Not provisioned for this app: " : "Declared: ") + entitlements.joined(separator: ", "),
                outcome: blocked ? .failed : .passed))
        }

        if status == .regionRestricted {
            checks.append(ExperimentCheck(id: "region", title: "Region", detail: "Not available in the current region", outcome: .failed))
        }
        return checks
    }
}
