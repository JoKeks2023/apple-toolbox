import Foundation

extension ExperimentDescriptor {
    func explanation(for status: ExperimentStatus) -> ExperimentExplanation? {
        guard status != .available else { return nil }
        return explanations[status] ?? defaultExplanation(for: status)
    }

    private func defaultExplanation(for status: ExperimentStatus) -> ExperimentExplanation {
        let platforms = supportedPlatforms.map(\.rawValue).joined(separator: ", ")
        let hardware = hardwareRequirements.isEmpty ? "Supported hardware" : hardwareRequirements.joined(separator: ", ")
        let permissionList = permissions.isEmpty ? "The related system permission" : permissions.joined(separator: ", ")
        let entitlementList = entitlements.isEmpty ? "A capability that is not provisioned" : entitlements.joined(separator: ", ")
        return switch status {
        case .available:
            ExperimentExplanation(reason: "", required: "", nextStep: "")
        case .permissionRequired:
            ExperimentExplanation(reason: "The app has not been granted access yet.", required: permissionList,
                                  nextStep: "Start the experiment; the system asks for permission once.")
        case .permissionDenied:
            ExperimentExplanation(reason: "Access was denied or is restricted on this device.", required: permissionList,
                                  nextStep: "Allow access in Settings › Privacy & Security, then return to the app.")
        case .entitlementRequired:
            ExperimentExplanation(reason: "Required entitlement is not provisioned for this app.", required: entitlementList,
                                  nextStep: "Enable the capability for the App ID and signing team.")
        case .approvalRequired:
            ExperimentExplanation(reason: "This capability needs Apple approval before it can be provisioned.", required: entitlementList,
                                  nextStep: "Request the entitlement from Apple for this App ID.")
        case .hardwareUnsupported:
            ExperimentExplanation(reason: "This device does not provide the required hardware.", required: hardware,
                                  nextStep: "Run the experiment on a device with this hardware.")
        case .osUnsupported:
            ExperimentExplanation(reason: "The installed OS version does not support this API.", required: osRequirements.joined(separator: ", "),
                                  nextStep: "Update the operating system.")
        case .platformUnsupported:
            ExperimentExplanation(reason: "The framework is not available on \(CurrentPlatform.value.rawValue).", required: platforms,
                                  nextStep: "Open Apple Toolbox on one of the supported platforms.")
        case .regionRestricted:
            ExperimentExplanation(reason: "The feature is not offered in the current region.", required: "A supported region",
                                  nextStep: "Check Apple's regional availability for this feature.")
        case .appleProgramRequired:
            ExperimentExplanation(reason: "The feature is part of an Apple program the team is not enrolled in.", required: entitlementList,
                                  nextStep: "Apply for the Apple program that grants this capability.")
        case .deviceOnly:
            ExperimentExplanation(reason: "The Simulator cannot provide this feature.", required: "A physical device",
                                  nextStep: "Run the app on a real device.")
        case .unavailable:
            ExperimentExplanation(reason: "The system reports the feature as currently unavailable.", required: hardware,
                                  nextStep: "Check the device settings and try again later.")
        }
    }
}
