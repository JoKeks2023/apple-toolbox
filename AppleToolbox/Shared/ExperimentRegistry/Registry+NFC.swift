import Foundation

extension ExperimentRegistry {
    static let nfc: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "core-nfc", name: "Core NFC", category: .nfc,
            description: "Read NDEF tags and inspect their records with a real NFC reader session.", frameworks: ["CoreNFC"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["NFC-capable iPhone or iPad"], osRequirements: ["iOS 11+"], permissions: ["NFC Reader Usage Description"], capabilities: ["Near Field Communication"], entitlements: ["Near Field Communication Tag Reading"], documentationURL: URL(string: "https://developer.apple.com/documentation/corenfc")!, evaluate: ExperimentAvailability.nfc,
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "This device has no NFC reader available to apps.", required: "iPhone 7 or later (iPad has no NFC reader)",
                    nextStep: "Run the experiment on an NFC-capable iPhone."),
            ],
            applePrograms: ["Apple Developer Program: NFC Tag Reading is not available to free Personal Teams"]),
        ExperimentDescriptor(id: "nfc-inspector", name: "NFC Inspector", category: .nfc,
            description: "Inspect ISO 7816, ISO 15693, FeliCa and MIFARE tags with an NFC tag reader session: identifiers and per-type metadata, a SELECT APDU with its status word, NDEF status and records, NDEF writing with optional locking, and a history of the last tags.", frameworks: ["CoreNFC"], supportedPlatforms: [.iOS, .iPadOS], hardwareRequirements: ["NFC-capable iPhone"], osRequirements: ["iOS 13+ · session configuration iOS 26.4+"], permissions: ["NFC Reader Usage Description"], capabilities: ["Near Field Communication Tag Reading", "Info.plist lists of ISO 7816 AIDs and FeliCa system codes"], entitlements: ["com.apple.developer.nfc.readersession.formats (NDEF, TAG)"], documentationURL: URL(string: "https://developer.apple.com/documentation/corenfc/nfctagreadersession")!, evaluate: ExperimentAvailability.nfc,
            useCase: ExperimentUseCase(id: "nfc-inspector", title: "Identify and write a tag", summary: "Find out what a card or sticker is, which declared applications it answers to, and whether it holds or accepts NDEF data.", interaction: "Pick the polling technologies, an AID and a FeliCa system code, hold one tag to the iPhone and read its metadata, SELECT response and NDEF records. Write a URI or text record and optionally lock the tag for good."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "NFCTagReaderSession.readingAvailable is false: this device has no NFC reader available to apps.", required: "iPhone 7 or later (iPad has no NFC reader)",
                    nextStep: "Run the inspector on an NFC-capable iPhone. ISO 7816 cards are only reported for AIDs listed in Info.plist, FeliCa cards only for listed system codes."),
            ],
            applePrograms: ["Apple Developer Program: NFC Tag Reading is not available to free Personal Teams"]),
    ]
}
