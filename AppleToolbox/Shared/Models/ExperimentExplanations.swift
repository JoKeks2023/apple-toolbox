import Foundation

/// "Why doesn't this work?" (spec §38): reason, requirement and next step for an unavailable experiment.
struct ExperimentExplanation: Equatable {
    let reason: String
    let required: String
    let nextStep: String
}

extension ExperimentDescriptor {
    func explanation(for status: ExperimentStatus) -> ExperimentExplanation? {
        guard status != .available else { return nil }
        return Self.specificExplanations[id]?[status] ?? defaultExplanation(for: status)
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
        case .developmentOnly:
            ExperimentExplanation(reason: "The API only works in development builds.", required: "A development-signed build",
                                  nextStep: "Run a debug build from Xcode.")
        case .deviceOnly:
            ExperimentExplanation(reason: "The Simulator cannot provide this feature.", required: "A physical device",
                                  nextStep: "Run the app on a real device.")
        case .simulatorOnly:
            ExperimentExplanation(reason: "The feature is only available in the Simulator.", required: "The Simulator",
                                  nextStep: "Run the app in the Simulator.")
        case .unavailable:
            ExperimentExplanation(reason: "The system reports the feature as currently unavailable.", required: hardware,
                                  nextStep: "Check the device settings and try again later.")
        }
    }

    private static let specificExplanations: [String: [ExperimentStatus: ExperimentExplanation]] = [
        "localauthentication": [
            .unavailable: ExperimentExplanation(reason: "No device passcode is set, so owner authentication cannot run.", required: "A device passcode (and optionally Face ID or Touch ID)",
                                                nextStep: "Set a passcode in Settings › Face ID & Passcode."),
            .hardwareUnsupported: ExperimentExplanation(reason: "Neither biometrics nor passcode authentication can be evaluated here.", required: "Face ID, Touch ID or a device passcode",
                                                        nextStep: "Run on a device with a passcode; in the Simulator enroll Face ID via Features › Face ID."),
        ],
        "secure-enclave": [
            .hardwareUnsupported: ExperimentExplanation(reason: "This device or simulator does not provide a Secure Enclave.", required: "A device with a Secure Enclave (iPhone 5s or later, Apple silicon or T2 Mac, Apple Watch)",
                                                        nextStep: "Run the experiment on a physical device."),
        ],
        "core-motion": [
            .hardwareUnsupported: ExperimentExplanation(reason: "Device motion data is not available (for example in the Simulator).", required: "Accelerometer and gyroscope",
                                                        nextStep: "Run on an iPhone, iPad or Apple Watch."),
        ],
        "core-nfc": [
            .hardwareUnsupported: ExperimentExplanation(reason: "This device has no NFC reader available to apps.", required: "iPhone 7 or later (iPad has no NFC reader)",
                                                        nextStep: "Run the experiment on an NFC-capable iPhone."),
        ],
        "nearby-interaction": [
            .hardwareUnsupported: ExperimentExplanation(reason: "This device does not provide an Ultra Wideband chip.", required: "iPhone 11 or later, or Apple Watch Series 6 or later",
                                                        nextStep: "Use two UWB-capable devices running Apple Toolbox."),
        ],
        "continuity": [
            .hardwareUnsupported: ExperimentExplanation(reason: "WatchConnectivity is only supported on iPhone.", required: "An iPhone paired with an Apple Watch",
                                                        nextStep: "Run the experiment on the iPhone that is paired with your watch."),
        ],
        "arkit": [
            .hardwareUnsupported: ExperimentExplanation(reason: "World tracking is not supported on this device.", required: "A device with an A9 chip or later and a rear camera",
                                                        nextStep: "Run the experiment on a recent iPhone or iPad."),
        ],
        "roomplan": [
            .hardwareUnsupported: ExperimentExplanation(reason: "This device does not provide LiDAR.", required: "A LiDAR-capable iPhone Pro or iPad Pro",
                                                        nextStep: "Run the experiment on a LiDAR device."),
        ],
        "healthkit-status": [
            .hardwareUnsupported: ExperimentExplanation(reason: "Health data is not available on this device.", required: "iPhone, Apple Watch or an iPad with the Health app",
                                                        nextStep: "Run the experiment on iPhone or Apple Watch."),
        ],
        "foundation-models": [
            .hardwareUnsupported: ExperimentExplanation(reason: "This device is not eligible for Apple Intelligence.", required: "An Apple Intelligence-capable device",
                                                        nextStep: "Run on a device that supports Apple Intelligence."),
            .unavailable: ExperimentExplanation(reason: "Apple Intelligence is turned off or the on-device model is not ready yet.", required: "Apple Intelligence enabled with the model downloaded",
                                                nextStep: "Turn on Apple Intelligence in Settings and wait for the model download to finish."),
        ],
        "passkeys": [
            .entitlementRequired: ExperimentExplanation(reason: "Passkeys are bound to a relying-party domain, and this app has no associated domain.", required: "Associated Domains entitlement with webcredentials:<domain> and an apple-app-site-association file on that domain",
                                                        nextStep: "Add the Associated Domains capability for your relying party and host the association file."),
        ],
        "sign-in-with-apple": [
            .entitlementRequired: ExperimentExplanation(reason: "The Sign in with Apple capability is not enabled for this app.", required: "com.apple.developer.applesignin",
                                                        nextStep: "Enable Sign in with Apple for the App ID in Xcode › Signing & Capabilities."),
        ],
        "game-controller": [
            .unavailable: ExperimentExplanation(reason: "No game controller is connected right now.", required: "A paired MFi, Xbox, PlayStation, or Switch controller (the Siri Remote counts on Apple TV)",
                                                nextStep: "Pair the controller in Bluetooth settings, or put an MFi controller in pairing mode and start wireless discovery below."),
        ],
        "app-attest": [
            .hardwareUnsupported: ExperimentExplanation(reason: "DCAppAttestService reports that App Attest is not supported here (for example in the Simulator).", required: "A physical device with a Secure Enclave and an App ID registered with Apple",
                                                        nextStep: "Run the experiment on a real device; the DeviceCheck token can still be tried below."),
        ],
    ]
}
