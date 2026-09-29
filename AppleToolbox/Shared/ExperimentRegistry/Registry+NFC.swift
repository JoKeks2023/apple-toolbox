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
        ExperimentDescriptor(id: "nfc-card-emulation", name: "NFC Card Emulation", category: .nfc,
            description: "Check CardSession support and eligibility, hold a presentment intent, and emulate an ISO 7816 card that answers a reader's SELECT for a demo AID, with every session lifecycle event and APDU logged.", frameworks: ["CoreNFC"], supportedPlatforms: [.iOS], hardwareRequirements: ["NFC-capable iPhone that supports card emulation"], osRequirements: ["iOS 17.4+"], permissions: ["Card emulation consent on the first session"], capabilities: ["Host Card Emulation (HCE), approved by Apple"], entitlements: ["com.apple.developer.nfc.hce", "com.apple.developer.nfc.hce.iso7816.select-identifier-prefixes"], documentationURL: URL(string: "https://developer.apple.com/documentation/corenfc/cardsession")!, evaluate: ExperimentAvailability.nfcCardEmulation,
            useCase: ExperimentUseCase(id: "hce-demo-card", title: "Emulate a card", summary: "See what an approved HCE app goes through: support and eligibility checks, the presentment intent, and APDUs from a real reader.", interaction: "Run the checks; when eligible, start a card session and hold the iPhone to an ISO 7816 reader that selects the demo AID. Each event and APDU exchange is logged."),
            explanations: [
                .approvalRequired: ExperimentExplanation(reason: "The HCE entitlement is not provisioned for this app. Apple grants it on request for contactless transactions in the European Economic Area, and CardSession() terminates apps that lack it, so the toolbox does not create a session.", required: "com.apple.developer.nfc.hce plus select-identifier-prefixes covering the demo AID, approved for this App ID; an NFC iPhone with iOS 17.4+ and an Apple Account in the EEA",
                    nextStep: "Apply on Apple's HCE page for contactless transactions in the EEA, enable the capability on the App ID and add both keys to the app's entitlements. The eligibility checks below still run."),
                .hardwareUnsupported: ExperimentExplanation(reason: "This device has no NFC reader available to apps, or CardSession.isSupported is false for this model.", required: "An NFC-capable iPhone that supports card emulation (iOS 17.4+)",
                    nextStep: "Run the experiment on a supported iPhone."),
            ],
            applePrograms: ["Host Card Emulation entitlement: Apple approval for contactless transactions in the European Economic Area"]),
    ]
}
