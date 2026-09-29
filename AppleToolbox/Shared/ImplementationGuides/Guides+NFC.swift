import Foundation

nonisolated extension ImplementationGuides {
    static let nfc: [String: ImplementationGuide] = [
        "core-nfc": ImplementationGuide(
            snippet: #"""
            import CoreNFC

            /// Reads NDEF text/URL records from a tag. Delegate callbacks arrive on a background queue.
            final class NDEFScanner: NSObject, NFCNDEFReaderSessionDelegate {
                private var session: NFCNDEFReaderSession?
                private let onPayloads: @Sendable ([String]) -> Void

                init(onPayloads: @escaping @Sendable ([String]) -> Void) { self.onPayloads = onPayloads }

                func begin() {
                    guard NFCNDEFReaderSession.readingAvailable else { return }
                    session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
                    session?.alertMessage = "Hold your iPhone near the tag."
                    session?.begin()
                }

                func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
                    let payloads = messages.flatMap(\.records).compactMap { record in
                        record.wellKnownTypeURIPayload()?.absoluteString ?? record.wellKnownTypeTextPayload().0
                    }
                    onPayloads(payloads)
                }

                func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: any Error) {
                    // Also called after a successful read when invalidateAfterFirstRead is true.
                    print("Session ended: \(error.localizedDescription)")
                }
            }
            """#,
            infoPlist: [
                .init(key: "NFCReaderUsageDescription", value: "Reads the NFC tags on your products."),
            ],
            entitlements: ["com.apple.developer.nfc.readersession.formats = [NDEF]"],
            capabilities: ["Near Field Communication Tag Reading"],
            notes: [
                "Reading needs an iPhone 7 or later; iPad has no NFC reader for apps.",
                "Sessions only start in the foreground from a user action and time out after 60 seconds.",
                "Background tag reading (iPhone XS+) opens your app via universal links in the tag's NDEF URL — no code needed to start it.",
            ]
        ),
        "nfc-inspector": ImplementationGuide(
            snippet: #"""
            import CoreNFC

            /// Connects to raw ISO 7816 / MIFARE / ISO 15693 / FeliCa tags and reads their identifiers.
            final class TagInspector: NSObject, NFCTagReaderSessionDelegate {
                private var session: NFCTagReaderSession?

                func begin() {
                    session = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693, .iso18092], delegate: self, queue: nil)
                    session?.alertMessage = "Hold your iPhone near the card."
                    session?.begin()
                }

                func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

                func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
                    guard let tag = tags.first else { return }
                    session.connect(to: tag) { error in
                        if let error { return session.invalidate(errorMessage: error.localizedDescription) }
                        switch tag {
                        case .iso7816(let card): print("ISO 7816", card.identifier, card.initialSelectedAID)
                        case .miFare(let card): print("MIFARE", card.mifareFamily.rawValue, card.identifier)
                        case .iso15693(let card): print("ISO 15693", card.identifier)
                        case .feliCa(let card): print("FeliCa", card.currentSystemCode)
                        @unknown default: break
                        }
                        session.alertMessage = "Tag read."
                        session.invalidate()
                    }
                }

                func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
                    print("Session ended: \(error.localizedDescription)")
                }
            }
            """#,
            infoPlist: [
                .init(key: "NFCReaderUsageDescription", value: "Reads the NFC cards you hold to the iPhone."),
                .init(key: "com.apple.developer.nfc.readersession.iso7816.select-identifiers", value: "<array><string>A000000003101001</string></array>"),
                .init(key: "com.apple.developer.nfc.readersession.felica.systemcodes", value: "<array><string>12FC</string></array>"),
            ],
            entitlements: ["com.apple.developer.nfc.readersession.formats = [NDEF, TAG]"],
            capabilities: ["Near Field Communication Tag Reading"],
            notes: [
                "ISO 7816 cards are only detected if their AID is listed in select-identifiers; FeliCa needs its system codes (no wildcard).",
                "Payment cards (EMV) cannot be read — Core NFC blocks them regardless of the AIDs you list.",
                "Callbacks run on the session's queue; hop to the main actor before touching UI.",
            ]
        ),
        "nfc-card-emulation": ImplementationGuide(
            snippet: #"""
            import CoreNFC

            /// Emulates an ISO 7816 card with CardSession (iOS 17.4+, EEA, Apple-approved apps only).
            @MainActor
            func emulateCard() async throws {
                guard NFCReaderSession.readingAvailable, CardSession.isSupported, await CardSession.isEligible else { return }

                // Keeps the default contactless app (Wallet) from taking over while the session runs.
                let presentmentIntent = try await NFCPresentmentIntentAssertion.acquire()
                defer { withExtendedLifetime(presentmentIntent) {} }

                let session = try await CardSession()
                session.alertMessage = "Hold your iPhone near the reader."
                for try await event in session.eventStream {
                    switch event {
                    case .sessionStarted:
                        try await session.startEmulation()
                    case .received(let apdu):
                        // Answer the reader's command; 90 00 = success.
                        try await apdu.respond(response: Data([0x90, 0x00]))
                    case .readerDeselected:
                        await session.stopEmulation(status: .success)
                    case .sessionInvalidated(let reason):
                        print("Card session ended: \(reason)")
                        return
                    default:
                        break
                    }
                }
            }
            """#,
            entitlements: [
                "com.apple.developer.nfc.hce = true",
                "com.apple.developer.nfc.hce.iso7816.select-identifier-prefixes = [A000000999]",
            ],
            capabilities: ["Host Card Emulation (granted by Apple)"],
            notes: [
                "Apple grants the HCE entitlement on request, for contactless transactions in the European Economic Area only; CardSession() terminates apps without it.",
                "The reader only reaches your app for AIDs matching your select-identifier-prefixes.",
                "The user confirms card emulation the first time, and the app must be in the foreground during the session.",
            ]
        ),
    ]
}
