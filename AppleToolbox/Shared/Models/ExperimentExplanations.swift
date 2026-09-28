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
            .unavailable: ExperimentExplanation(reason: "Apple Intelligence is turned off (appleIntelligenceNotEnabled) or the model is still downloading (modelNotReady); the run section shows which.", required: "Apple Intelligence enabled with the model downloaded",
                                                nextStep: "Turn on Apple Intelligence in Settings › Apple Intelligence & Siri and wait for the model download to finish."),
        ],
        "passkeys": [
            .entitlementRequired: ExperimentExplanation(reason: "Passkeys are bound to a relying-party domain, and no webcredentials: associated domain is provisioned for this app.", required: "Associated Domains entitlement with webcredentials:<domain> and an apple-app-site-association file on that domain listing this app",
                                                        nextStep: "Add the Associated Domains capability for your relying party and host the association file. The requests below still run and show the system's rejection."),
        ],
        "sign-in-with-apple": [
            .entitlementRequired: ExperimentExplanation(reason: "Neither the embedded provisioning profile nor this build's readable signed entitlements include Sign in with Apple.", required: "com.apple.developer.applesignin = [Default], enabled on the App ID of a paid developer team",
                                                        nextStep: "Add the Sign in with Apple capability to this target in Xcode › Signing & Capabilities; the button below still shows the system's real error."),
        ],
        "game-controller": [
            .unavailable: ExperimentExplanation(reason: "No game controller is connected right now.", required: "A paired MFi, Xbox, PlayStation, or Switch controller (the Siri Remote counts on Apple TV)",
                                                nextStep: "Pair the controller in Bluetooth settings, or put an MFi controller in pairing mode and start wireless discovery below."),
        ],
        "matter-status": [
            .platformUnsupported: ExperimentExplanation(reason: "Apple Toolbox starts Apple Home's accessory setup only on iPhone and iPad; watchOS and tvOS have no setup API.", required: "iOS or iPadOS 15.4+ with Apple Home",
                                                        nextStep: "Open Apple Toolbox on an iPhone or iPad."),
            .unavailable: ExperimentExplanation(reason: "The system reports that accessory setup is not supported on this device (HMAccessorySetupManager.isSupported is false).", required: "An iPhone or iPad that supports Apple Home accessory setup",
                                                nextStep: "Run the experiment on a physical iPhone or iPad with Apple Home set up."),
        ],
        "widgetkit": [
            .entitlementRequired: ExperimentExplanation(reason: "The App Group container is not provisioned, so the app cannot share data with its widget.", required: "com.apple.security.application-groups with group.com.jorisconrad.AppleToolbox for the app and the widget extension",
                                                        nextStep: "Register the App Group for both App IDs in Signing & Capabilities and reinstall the app."),
        ],
        "app-attest": [
            .hardwareUnsupported: ExperimentExplanation(reason: "DCAppAttestService reports that App Attest is not supported here (for example in the Simulator).", required: "A physical device with a Secure Enclave and an App ID registered with Apple",
                                                        nextStep: "Run the experiment on a real device; the DeviceCheck token can still be tried below."),
        ],
    ]
}
