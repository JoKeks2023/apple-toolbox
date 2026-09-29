import Foundation

extension ExperimentRegistry {
    static let nfc: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "core-nfc", name: "Core NFC", category: .nfc,
            description: "Read NDEF tags and inspect their records with a real NFC reader session.", frameworks: ["CoreNFC"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["NFC-capable iPhone or iPad"], osRequirements: ["iOS 11+"], permissions: ["NFC Reader Usage Description"], capabilities: ["Near Field Communication"], entitlements: ["Near Field Communication Tag Reading"], documentationURL: URL(string: "https://developer.apple.com/documentation/corenfc")!, evaluate: ExperimentAvailability.nfc,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "This device has no NFC reader available to apps.", required: "iPhone 7 or later (iPad has no NFC reader)",
                    nextStep: "Run the experiment on an NFC-capable iPhone."),
            ]),
    ]
}
