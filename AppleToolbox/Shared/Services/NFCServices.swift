import Foundation
import Combine

#if canImport(CoreNFC) && os(iOS)
import CoreNFC
#endif

// MARK: - NDEF reader

@MainActor
final class NFCExperimentService: NSObject, ObservableObject {
    @Published private(set) var output = "NFC tag reading is ready."
    @Published private(set) var isScanning = false
    @Published private(set) var records: [NFCRecordResult] = []
    #if canImport(CoreNFC) && os(iOS)
    private var session: NFCNDEFReaderSession?
    #endif

    func start() {
        #if canImport(CoreNFC) && os(iOS)
        guard NFCNDEFReaderSession.readingAvailable else { output = "NFC reading is not available on this device."; return }
        records.removeAll()
        let session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        session.alertMessage = "Hold your iPhone near an NFC tag."
        self.session = session
        isScanning = true
        session.begin()
        #else
        output = "Core NFC is only available for NFC-capable iOS devices."
        #endif
    }

    func stop() {
        #if canImport(CoreNFC) && os(iOS)
        session?.invalidate()
        session = nil
        #endif
        isScanning = false
    }
}

#if canImport(CoreNFC) && os(iOS)
extension NFCExperimentService: NFCNDEFReaderSessionDelegate {
    // Core NFC calls the delegate on its own serial queue; results hop to the main actor.
    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        let records = messages.flatMap(\.records).enumerated().map { index, record in
            NFCRecordResult(id: index, format: record.typeNameFormat.rawValue, type: String(data: record.type, encoding: .utf8) ?? "Unknown", payloadBytes: record.payload.count)
        }
        let messageCount = messages.count
        Task { @MainActor [weak self] in
            self?.records = records
            self?.output = "Detected \(messageCount) NDEF message(s) with \(records.count) record(s)."
            self?.isScanning = false
        }
    }

    nonisolated func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        let code = (error as? NFCReaderError)?.code
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            isScanning = false
            switch code {
            case .readerSessionInvalidationErrorFirstNDEFTagRead:
                break // Expected after a successful read with invalidateAfterFirstRead.
            case .readerSessionInvalidationErrorUserCanceled:
                if records.isEmpty { output = "NFC scan cancelled." }
            default:
                output = "NFC session error: \(message)"
            }
        }
    }
}
#endif

struct NFCRecordResult: Identifiable, Equatable {
    let id: Int
    let format: UInt8
    let type: String
    let payloadBytes: Int
}

// MARK: - NFC Inspector

/// What an inspector or writer session reports back to the main actor.
nonisolated enum NFCInspectionEvent: Sendable {
    case active
    case progress(String)
    case inspected(NFCInspectedTag)
    case wrote(String)
    case failed(String)
    case invalidated(NFCSessionEnd)
}

/// Why a reader session ended, already rendered for the output card.
nonisolated struct NFCSessionEnd: Sendable {
    let message: String
    let isCancellation: Bool
    let isError: Bool
}

/// NFC Inspector (spec §9/§40): an `NFCTagReaderSession` for ISO 7816, ISO 15693, FeliCa and MIFARE tags with per-type
/// metadata, a SELECT APDU for an Info.plist-declared AID, NDEF status and records, plus NDEF writing and locking.
@MainActor
final class NFCInspectorService: ObservableObject {
    enum Polling: String, CaseIterable, Identifiable {
        case all = "All technologies"
        case iso14443 = "ISO 14443 · ISO 7816 and MIFARE"
        case iso15693 = "ISO 15693 · vicinity tags"
        case iso18092 = "ISO 18092 · FeliCa"

        var id: String { rawValue }
        var includesFeliCa: Bool { self == .all || self == .iso18092 }
    }

    enum Activity: Equatable { case inspecting, writing }

    @Published var polling: Polling = .all
    /// AID for the explicit SELECT after connecting; the picker only offers AIDs declared in Info.plist.
    @Published var selectedAID: String
    /// FeliCa system code used for polling; the picker only offers codes declared in Info.plist.
    @Published var selectedSystemCode: String
    @Published var recordKind: NDEFRecordKind = .uri
    @Published var recordContent = "https://developer.apple.com/documentation/corenfc"
    @Published var lockAfterWriting = false
    /// ISO 15693 block range and MIFARE Ultralight page for the extra read commands.
    @Published var readOptions = NFCReadOptions()
    @Published private(set) var output = "Choose the polling technologies, then hold one tag near the top of the iPhone."
    @Published private(set) var isError = false
    @Published private(set) var activity: Activity?
    @Published private(set) var lastTag: NFCInspectedTag?
    @Published private(set) var history: [NFCInspectedTag]

    let declaredAIDs: [String]
    let declaredSystemCodes: [String]
    /// Set once the current session delivered a result, so its closing invalidation does not overwrite it.
    private var sessionHadResult = false

    #if canImport(CoreNFC) && os(iOS)
    private var tagSession: NFCTagReaderSession?
    private var writeSession: NFCNDEFReaderSession?
    /// Reader sessions hold their delegate weakly.
    private var sessionDelegate: NSObject?
    #endif

    init() {
        let info = Bundle.main.infoDictionary
        declaredAIDs = NFCInfoPlist.declaredHexValues(for: NFCInfoPlist.iso7816SelectIdentifiersKey, in: info)
        declaredSystemCodes = NFCInfoPlist.declaredHexValues(for: NFCInfoPlist.feliCaSystemCodesKey, in: info)
        selectedAID = declaredAIDs.first ?? ""
        selectedSystemCode = declaredSystemCodes.first ?? ""
        history = NFCInspectorHistory.load()
    }

    var isActive: Bool { activity != nil }

    func inspect() {
        #if canImport(CoreNFC) && os(iOS)
        guard activity == nil else { return }
        guard NFCTagReaderSession.readingAvailable else { report("NFC tag reading is not available on this device.", isError: true); return }
        let delegate = NFCTagInspectionDelegate(selectAID: declaredAIDs.contains(selectedAID) ? selectedAID : nil, options: readOptions) { @Sendable [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        // An empty AID list means "every AID declared in Info.plist"; the explicit SELECT below uses the picked one.
        let systemCodes = polling.includesFeliCa && !selectedSystemCode.isEmpty ? [selectedSystemCode] : []
        let configuration = NFCTagReaderSession.Configuration(pollingOption: polling.option, iso7816SelectIdentifiers: [], feliCaSystemCodes: systemCodes)
        let session = NFCTagReaderSession(configuration: configuration, delegate: delegate, queue: nil)
        session.alertMessage = "Hold your iPhone near the tag you want to inspect."
        begin(.inspecting, delegate: delegate)
        tagSession = session
        report("Polling \(polling.rawValue)\(systemCodes.isEmpty ? "" : " · FeliCa system code \(selectedSystemCode)")…")
        session.begin()
        #else
        report("Core NFC tag reader sessions are only available on NFC-capable iPhones.", isError: true)
        #endif
    }

    func write() {
        if let problem = recordKind.validationError(for: recordContent) { report(problem, isError: true); return }
        #if canImport(CoreNFC) && os(iOS)
        guard activity == nil else { return }
        guard NFCNDEFReaderSession.readingAvailable else { report("NFC is not available on this device, so tags cannot be written.", isError: true); return }
        let request = NFCNDEFWriteRequest(kind: recordKind, content: recordContent.trimmingCharacters(in: .whitespacesAndNewlines), lock: lockAfterWriting)
        let delegate = NFCNDEFWriteDelegate(request: request) { @Sendable [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        let session = NFCNDEFReaderSession(delegate: delegate, queue: nil, invalidateAfterFirstRead: false)
        session.alertMessage = request.lock ? "Hold your iPhone near the tag to write and permanently lock it." : "Hold your iPhone near the tag to write."
        begin(.writing, delegate: delegate)
        writeSession = session
        report("Waiting for a writable NDEF tag…")
        session.begin()
        #else
        report("Writing NDEF tags needs Core NFC on an NFC-capable iPhone.", isError: true)
        #endif
    }

    func stop() {
        #if canImport(CoreNFC) && os(iOS)
        tagSession?.invalidate()
        writeSession?.invalidate()
        #endif
        endSession()
    }

    /// Shows a tag from the history in the detail section.
    func show(_ tag: NFCInspectedTag) {
        lastTag = tag
    }

    func clearHistory() {
        history = []
        NFCInspectorHistory.save(history)
    }

    private func handle(_ event: NFCInspectionEvent) {
        switch event {
        case .active:
            report(activity == .writing ? "Session active. Hold a writable tag near the top of the iPhone." : "Session active. Hold one tag near the top of the iPhone.")
        case .progress(let message):
            report(message)
        case .inspected(let tag):
            sessionHadResult = true
            lastTag = tag
            history = NFCInspectorHistory.appending(tag, to: history)
            NFCInspectorHistory.save(history)
            let failedExchanges = tag.exchanges.filter { $0.error != nil }.count
            report("Inspected a \(tag.technology) tag (\(tag.identifier)). \(tag.fields.count) metadata fields, \(tag.exchanges.count) APDU exchange(s)\(failedExchanges > 0 ? ", \(failedExchanges) failed" : "").")
        case .wrote(let message):
            sessionHadResult = true
            report(message)
        case .failed(let message):
            sessionHadResult = true
            report(message, isError: true)
        case .invalidated(let end):
            let hadResult = sessionHadResult
            endSession()
            if !(end.isCancellation && hadResult) { report(end.message, isError: end.isError) }
        }
    }

    #if canImport(CoreNFC) && os(iOS)
    private func begin(_ activity: Activity, delegate: NSObject) {
        self.activity = activity
        sessionDelegate = delegate
        sessionHadResult = false
    }
    #endif

    private func endSession() {
        #if canImport(CoreNFC) && os(iOS)
        tagSession = nil
        writeSession = nil
        sessionDelegate = nil
        #endif
        activity = nil
    }

    private func report(_ message: String, isError: Bool = false) {
        output = message
        self.isError = isError
    }
}

#if canImport(CoreNFC) && os(iOS)
private extension NFCInspectorService.Polling {
    var option: NFCTagReaderSession.PollingOption {
        switch self {
        case .all: [.iso14443, .iso15693, .iso18092]
        case .iso14443: .iso14443
        case .iso15693: .iso15693
        case .iso18092: .iso18092
        }
    }
}

nonisolated extension NFCSessionEnd {
    init(_ error: any Error, cancellation: String) {
        let message = error.localizedDescription
        switch (error as? NFCReaderError)?.code {
        case .readerSessionInvalidationErrorUserCanceled:
            self.init(message: cancellation, isCancellation: true, isError: false)
        case .readerSessionInvalidationErrorSessionTimeout:
            self.init(message: "The session timed out after 60 seconds without a completed tag interaction.", isCancellation: false, isError: true)
        case .readerSessionInvalidationErrorSystemIsBusy:
            self.init(message: "Core NFC is busy with another session. Try again in a moment.", isCancellation: false, isError: true)
        case .readerErrorSecurityViolation:
            self.init(message: "Security violation: the Tag Reading entitlement, NFCReaderUsageDescription or the Info.plist AID / FeliCa system code lists are missing or invalid. (\(message))", isCancellation: false, isError: true)
        case .readerErrorUnsupportedFeature:
            self.init(message: "This device does not support the requested reader mode. (\(message))", isCancellation: false, isError: true)
        case .readerErrorRadioDisabled:
            self.init(message: "The NFC radio is turned off. (\(message))", isCancellation: false, isError: true)
        default:
            self.init(message: "NFC session ended: \(message)", isCancellation: false, isError: true)
        }
    }
}

/// Delegate for one inspector session. Core NFC calls it on the session's own serial queue.
nonisolated final class NFCTagInspectionDelegate: NSObject, NFCTagReaderSessionDelegate {
    private let selectAID: String?
    private let options: NFCReadOptions
    private let report: @Sendable (NFCInspectionEvent) -> Void

    init(selectAID: String?, options: NFCReadOptions, report: @escaping @Sendable (NFCInspectionEvent) -> Void) {
        self.selectAID = selectAID
        self.options = options
        self.report = report
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        report(.active)
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: any Error) {
        report(.invalidated(NFCSessionEnd(error, cancellation: "Inspection cancelled.")))
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard tags.count == 1, let detected = tags.first else {
            session.alertMessage = "More than one tag found. Present a single tag."
            session.restartPolling()
            return
        }
        let session = NFCSessionObject(session), tag = NFCSessionObject(detected)
        let selectAID = selectAID, options = options, report = report
        Task { await NFCTagInspector.run(session: session, tag: tag, selectAID: selectAID, options: options, report: report) }
    }
}

/// Carries a Core NFC session or tag into the task that talks to it. The objects are not Sendable, but each one is used
/// by exactly one task that sends one command at a time, and Core NFC serializes the radio work itself.
nonisolated struct NFCSessionObject<Object>: @unchecked Sendable {
    let object: Object
    init(_ object: Object) { self.object = object }
}

/// Reads the metadata Core NFC exposes for each tag type and runs the explicit commands.
nonisolated enum NFCTagInspector {
    @concurrent static func run(session box: NFCSessionObject<NFCTagReaderSession>, tag tagBox: NFCSessionObject<NFCTag>, selectAID: String?,
                                options: NFCReadOptions = NFCReadOptions(), report: @Sendable (NFCInspectionEvent) -> Void) async {
        let session = box.object, tag = tagBox.object
        do {
            try await session.connect(to: tag)
        } catch {
            report(.failed("Could not connect to the tag: \(error.localizedDescription)"))
            session.invalidate(errorMessage: "Could not connect to the tag.")
            return
        }
        report(.progress("Connected. Reading tag metadata…"))
        let inspected = await inspect(tag, selectAID: selectAID, options: options)
        report(.inspected(inspected))
        session.alertMessage = "\(inspected.technology) tag inspected."
        session.invalidate()
    }

    @concurrent static func inspect(_ tag: NFCTag, selectAID: String?, options: NFCReadOptions = NFCReadOptions()) async -> NFCInspectedTag {
        var fields: [NFCTagField] = []
        var exchanges: [NFCAPDUExchange] = []
        let technology: String
        let identifier: Data
        let ndefTag: any NFCNDEFTag
        switch tag {
        case .iso7816(let card):
            technology = "ISO 7816"
            identifier = card.identifier
            fields.append(NFCTagField(label: "Selected during discovery", value: "\(card.initialSelectedAID) · \(NFCKnownIdentifiers.applicationName(forAID: card.initialSelectedAID))"))
            fields.append(NFCTagField(label: "Historical bytes (Type A)", value: card.historicalBytes.map { NFCHex.string($0) } ?? "None"))
            fields.append(NFCTagField(label: "Application data (Type B)", value: card.applicationData.map { NFCHex.string($0) } ?? "None"))
            fields.append(NFCTagField(label: "Proprietary application data coding", value: card.proprietaryApplicationDataCoding ? "Yes" : "No"))
            fields.append(NFCTagField(label: "PACE support", value: card.supportsPACE ? "Yes" : "No"))
            if let selectAID { exchanges.append(await select(selectAID, on: card)) }
            ndefTag = card
        case .miFare(let mifare):
            technology = "MIFARE \(familyName(mifare.mifareFamily))"
            identifier = mifare.identifier
            fields.append(NFCTagField(label: "Family", value: familyName(mifare.mifareFamily)))
            fields.append(NFCTagField(label: "Historical bytes", value: mifare.historicalBytes.map { NFCHex.string($0) } ?? "None"))
            // DESFire speaks ISO 7816-4 APDUs natively; other families only accept their native command set.
            if mifare.mifareFamily == .desfire, let selectAID { exchanges.append(await select(selectAID, onMiFare: mifare)) }
            exchanges += await mifareReads(mifare, options: options)
            ndefTag = mifare
        case .iso15693(let vicinity):
            technology = "ISO 15693"
            identifier = vicinity.identifier
            fields.append(NFCTagField(label: "IC manufacturer", value: NFCKnownIdentifiers.icManufacturer(vicinity.icManufacturerCode)))
            fields.append(NFCTagField(label: "IC serial number", value: NFCHex.string(vicinity.icSerialNumber)))
            do {
                let info = try await vicinity.systemInfo(requestFlags: [.highDataRate])
                fields.append(NFCTagField(label: "DSFID", value: reported(info.dataStorageFormatIdentifier)))
                fields.append(NFCTagField(label: "AFI", value: reported(info.applicationFamilyIdentifier)))
                fields.append(NFCTagField(label: "Memory", value: info.totalBlocks < 0 || info.blockSize < 0 ? "Not reported" : "\(info.totalBlocks) blocks × \(info.blockSize) bytes = \(info.totalBlocks * info.blockSize) bytes"))
                fields.append(NFCTagField(label: "IC reference", value: reported(info.icReference)))
                exchanges += await blockReads(vicinity, options: options, totalBlocks: info.totalBlocks)
            } catch {
                fields.append(NFCTagField(label: "System information", value: "Not returned: \(error.localizedDescription)"))
                exchanges += await blockReads(vicinity, options: options, totalBlocks: -1)
            }
            ndefTag = vicinity
        case .feliCa(let felica):
            technology = "FeliCa"
            identifier = felica.currentIDm
            let current = NFCHex.string(felica.currentSystemCode, separator: "")
            fields.append(NFCTagField(label: "Polled system code", value: "\(current) · \(NFCKnownIdentifiers.systemCodeName(current))"))
            do {
                let codes = try await felica.requestSystemCode()
                fields.append(NFCTagField(label: "System codes on card", value: codes.isEmpty ? "None reported" : codes.map { NFCHex.string($0, separator: "") }.joined(separator: ", ")))
            } catch {
                fields.append(NFCTagField(label: "System codes on card", value: "Request System Code failed: \(error.localizedDescription)"))
            }
            ndefTag = felica
        @unknown default:
            return NFCInspectedTag(id: UUID(), date: Date(), technology: "Unknown tag type", identifier: "—", fields: [], exchanges: [], ndefRecords: [])
        }
        let (ndefField, records) = await ndef(of: ndefTag)
        fields.append(ndefField)
        return NFCInspectedTag(id: UUID(), date: Date(), technology: technology, identifier: NFCHex.string(identifier), fields: fields, exchanges: exchanges, ndefRecords: records)
    }

    /// Native MIFARE reads: Ultralight/NTAG GET_VERSION and READ, DESFire GetVersion wrapped in ISO 7816-4.
    @concurrent private static func mifareReads(_ tag: any NFCMiFareTag, options: NFCReadOptions) async -> [NFCAPDUExchange] {
        switch tag.mifareFamily {
        case .ultralight:
            var result: [NFCAPDUExchange] = []
            let version = await native("GET_VERSION (0x60)", MiFareCommand.ultralightGetVersion, on: tag) { data in
                UltralightVersion(data).map { "\($0.vendorName) \($0.productName), \($0.storageDescription) user memory" }
            }
            result.append(version)
            let page = options.ultralightPage
            result.append(await native("READ page \(page) (0x30): pages \(page)–\(Int(page) + 3)", MiFareCommand.ultralightRead(page: page), on: tag) { data in
                data.count == 16 ? "16 bytes = 4 pages × 4 bytes" : "\(data.count) bytes (a 4-bit NAK means the page is out of range or protected)"
            })
            return result
        case .desfire:
            var result: [NFCAPDUExchange] = []
            var command = MiFareCommand.desfireGetVersion
            for frame in 1...3 {
                let title = frame == 1 ? "DESFire GetVersion (90 60, frame 1: hardware)" : "DESFire ADDITIONAL_FRAME (90 AF, frame \(frame): \(frame == 2 ? "software" : "UID, batch, production date"))"
                guard let apdu = NFCISO7816APDU(data: command) else { result.append(rejected(title, command)); break }
                do {
                    let response: NFCISO7816ResponseAPDU = try await tag.sendMiFareISO7816Command(apdu)
                    let sw1 = response.statusWord1, sw2 = response.statusWord2
                    result.append(NFCAPDUExchange(title: title, command: NFCHex.string(command), response: response.payload.map { NFCHex.string($0) } ?? "No data",
                                                  statusWord: String(format: "%02X %02X", sw1, sw2), meaning: MiFareCommand.desfireStatus(sw1: sw1, sw2: sw2), error: nil))
                    guard MiFareCommand.desfireHasMoreFrames(sw1: sw1, sw2: sw2) else { break }
                    command = MiFareCommand.desfireAdditionalFrame
                } catch {
                    result.append(NFCAPDUExchange(title: title, command: NFCHex.string(command), response: nil, statusWord: nil, meaning: nil, error: error.localizedDescription))
                    break
                }
            }
            return result
        case .plus:
            return [NFCAPDUExchange(title: "MIFARE Plus", command: "—", response: nil, statusWord: nil, meaning: nil,
                                    error: "Not read: MIFARE Plus needs AES authentication with the card's keys before any read; Apple Toolbox has no keys for your card.")]
        default:
            return [NFCAPDUExchange(title: "MIFARE", command: "—", response: nil, statusWord: nil, meaning: nil,
                                    error: "Core NFC reported an unknown MIFARE family. MIFARE Classic (Crypto1) is not supported by Core NFC.")]
        }
    }

    @concurrent private static func native(_ title: String, _ command: Data, on tag: any NFCMiFareTag, describe: @Sendable (Data) -> String?) async -> NFCAPDUExchange {
        do {
            let response = try await tag.sendMiFareCommand(commandPacket: command)
            return NFCAPDUExchange(title: title, command: NFCHex.string(command), response: response.isEmpty ? "No data" : NFCHex.string(response),
                                   statusWord: nil, meaning: describe(response), error: nil)
        } catch {
            return NFCAPDUExchange(title: title, command: NFCHex.string(command), response: nil, statusWord: nil, meaning: nil, error: error.localizedDescription)
        }
    }

    /// ISO 15693 Read Single Block (0x20) for the first block and Read Multiple Blocks (0x23) for the chosen range.
    @concurrent private static func blockReads(_ tag: any NFCISO15693Tag, options: NFCReadOptions, totalBlocks: Int) async -> [NFCAPDUExchange] {
        guard let range = ISO15693BlockRange.clamp(start: options.blockStart, count: options.blockCount, totalBlocks: totalBlocks) else {
            return [NFCAPDUExchange(title: "Read blocks", command: "—", response: nil, statusWord: nil, meaning: nil,
                                    error: "Block \(options.blockStart) is beyond the tag's \(totalBlocks) blocks.")]
        }
        var result: [NFCAPDUExchange] = []
        let first = UInt8(range.lowerBound)
        let singleTitle = "Read Single Block \(first) (0x20)"
        let singleCommand = String(format: "22 20 [UID] %02X", first)
        do {
            let block = try await tag.readSingleBlock(requestFlags: [.highDataRate, .address], blockNumber: first)
            result.append(NFCAPDUExchange(title: singleTitle, command: singleCommand, response: NFCHex.string(block), statusWord: nil, meaning: "\(block.count) bytes", error: nil))
        } catch {
            result.append(NFCAPDUExchange(title: singleTitle, command: singleCommand, response: nil, statusWord: nil, meaning: nil, error: error.localizedDescription))
        }
        guard range.count > 1 else { return result }
        let multiTitle = "Read Multiple Blocks \(range.lowerBound)–\(range.upperBound) (0x23)"
        let multiCommand = String(format: "22 23 [UID] %02X %02X", range.lowerBound, range.count - 1)
        do {
            let blocks = try await tag.readMultipleBlocks(requestFlags: [.highDataRate, .address], blockRange: NSRange(location: range.lowerBound, length: range.count))
            let text = blocks.enumerated().map { "\(range.lowerBound + $0.offset): \(NFCHex.string($0.element))" }.joined(separator: "\n")
            result.append(NFCAPDUExchange(title: multiTitle, command: multiCommand, response: text, statusWord: nil, meaning: "\(blocks.count) blocks", error: nil))
        } catch {
            result.append(NFCAPDUExchange(title: multiTitle, command: multiCommand, response: nil, statusWord: nil, meaning: nil, error: error.localizedDescription))
        }
        return result
    }

    @concurrent private static func select(_ aid: String, on card: any NFCISO7816Tag) async -> NFCAPDUExchange {
        let (title, bytes, apdu) = selectCommand(aid)
        guard let apdu else { return rejected(title, bytes) }
        do {
            let response: NFCISO7816ResponseAPDU = try await card.sendCommand(apdu: apdu)
            return exchange(title, bytes, response)
        } catch {
            return NFCAPDUExchange(title: title, command: NFCHex.string(bytes), response: nil, statusWord: nil, meaning: nil, error: error.localizedDescription)
        }
    }

    @concurrent private static func select(_ aid: String, onMiFare tag: any NFCMiFareTag) async -> NFCAPDUExchange {
        let (title, bytes, apdu) = selectCommand(aid)
        guard let apdu else { return rejected(title, bytes) }
        do {
            let response: NFCISO7816ResponseAPDU = try await tag.sendMiFareISO7816Command(apdu)
            return exchange(title, bytes, response)
        } catch {
            return NFCAPDUExchange(title: title, command: NFCHex.string(bytes), response: nil, statusWord: nil, meaning: nil, error: error.localizedDescription)
        }
    }

    private static func selectCommand(_ aid: String) -> (String, Data, NFCISO7816APDU?) {
        let bytes = ISO7816Command.selectByName(NFCHex.data(aid) ?? Data())
        return ("SELECT \(aid) · \(NFCKnownIdentifiers.applicationName(forAID: aid))", bytes, NFCISO7816APDU(data: bytes))
    }

    private static func rejected(_ title: String, _ bytes: Data) -> NFCAPDUExchange {
        NFCAPDUExchange(title: title, command: NFCHex.string(bytes), response: nil, statusWord: nil, meaning: nil, error: "Core NFC rejected the APDU encoding.")
    }

    private static func exchange(_ title: String, _ bytes: Data, _ response: NFCISO7816ResponseAPDU) -> NFCAPDUExchange {
        let status = ISO7816StatusWord(sw1: response.statusWord1, sw2: response.statusWord2)
        return NFCAPDUExchange(title: title, command: NFCHex.string(bytes), response: response.payload.map { NFCHex.string($0) } ?? "No data",
                               statusWord: status.hex, meaning: status.meaning, error: nil)
    }

    @concurrent private static func ndef(of tag: any NFCNDEFTag) async -> (NFCTagField, [String]) {
        do {
            let (status, capacity) = try await tag.queryNDEFStatus()
            let state = switch status {
            case .notSupported: "Not NDEF formatted"
            case .readWrite: "Read/write"
            case .readOnly: "Read-only (locked)"
            @unknown default: "Unknown status"
            }
            guard status != .notSupported else { return (NFCTagField(label: "NDEF", value: state), []) }
            let field = NFCTagField(label: "NDEF", value: "\(state) · capacity \(capacity) bytes")
            do {
                let message = try await tag.readNDEF()
                return (field, message.records.map(describe))
            } catch {
                return (field, ["No NDEF message read: \(error.localizedDescription)"])
            }
        } catch {
            return (NFCTagField(label: "NDEF", value: "Status query failed: \(error.localizedDescription)"), [])
        }
    }

    static func describe(_ record: NFCNDEFPayload) -> String {
        let type = String(data: record.type, encoding: .utf8) ?? NFCHex.string(record.type)
        if record.typeNameFormat == .nfcWellKnown {
            if type == "U", let url = record.wellKnownTypeURIPayload() { return "URI · \(url.absoluteString)" }
            if type == "T" {
                let (text, locale) = record.wellKnownTypeTextPayload()
                if let text { return "Text (\(locale?.identifier ?? "no language")) · \(text)" }
            }
        }
        return "\(formatName(record.typeNameFormat)) · type \(type.isEmpty ? "—" : type) · \(record.payload.count) bytes"
    }

    private static func formatName(_ format: NFCTypeNameFormat) -> String {
        switch format {
        case .empty: "Empty"
        case .nfcWellKnown: "NFC well-known"
        case .media: "MIME media"
        case .absoluteURI: "Absolute URI"
        case .nfcExternal: "NFC external"
        case .unknown: "Unknown"
        case .unchanged: "Unchanged (chunk)"
        @unknown default: "TNF \(format.rawValue)"
        }
    }

    private static func familyName(_ family: NFCMiFareFamily) -> String {
        switch family {
        case .ultralight: "Ultralight"
        case .plus: "Plus"
        case .desfire: "DESFire"
        case .unknown: "(family not identified)"
        @unknown default: "(family \(family.rawValue))"
        }
    }

    /// ISO 15693 system information uses -1 for values the tag did not include.
    private static func reported(_ value: Int) -> String {
        value < 0 ? "Not reported" : String(format: "0x%02X", value)
    }
}

nonisolated struct NFCNDEFWriteRequest: Sendable {
    let kind: NDEFRecordKind
    let content: String
    let lock: Bool
}

/// Delegate for one NDEF write session. Implementing `readerSession(_:didDetect:)` turns the NDEF session into a read-write session.
nonisolated final class NFCNDEFWriteDelegate: NSObject, NFCNDEFReaderSessionDelegate {
    private let request: NFCNDEFWriteRequest
    private let report: @Sendable (NFCInspectionEvent) -> Void

    init(request: NFCNDEFWriteRequest, report: @escaping @Sendable (NFCInspectionEvent) -> Void) {
        self.request = request
        self.report = report
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        report(.active)
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Not called: Core NFC reports tags through readerSession(_:didDetect:) instead.
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: any Error) {
        report(.invalidated(NFCSessionEnd(error, cancellation: "Writing cancelled.")))
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [any NFCNDEFTag]) {
        guard tags.count == 1, let detected = tags.first else {
            session.alertMessage = "More than one tag found. Present a single tag."
            session.restartPolling()
            return
        }
        let session = NFCSessionObject(session), tag = NFCSessionObject(detected)
        let request = request, report = report
        Task { await Self.write(request, session: session, tag: tag, report: report) }
    }

    @concurrent private static func write(_ request: NFCNDEFWriteRequest, session box: NFCSessionObject<NFCNDEFReaderSession>, tag tagBox: NFCSessionObject<any NFCNDEFTag>,
                                          report: @Sendable (NFCInspectionEvent) -> Void) async {
        let session = box.object, tag = tagBox.object
        func fail(_ alert: String, _ message: String) {
            report(.failed(message))
            session.invalidate(errorMessage: alert)
        }
        do {
            try await session.connect(to: tag)
            let (status, capacity) = try await tag.queryNDEFStatus()
            switch status {
            case .readWrite: break
            case .readOnly: return fail("This tag is locked.", "The tag is read-only (locked), so it cannot be written.")
            default: return fail("This tag is not NDEF formatted.", "The tag does not support NDEF, so Core NFC cannot write a record to it.")
            }
            let payload = switch request.kind {
            case .uri: NFCNDEFPayload.wellKnownTypeURIPayload(string: request.content)
            case .text: NFCNDEFPayload.wellKnownTypeTextPayload(string: request.content, locale: Locale.current)
            }
            guard let payload else { return fail("Invalid record.", "Core NFC could not encode “\(request.content)” as a \(request.kind.rawValue) record.") }
            let message = NFCNDEFMessage(records: [payload])
            guard message.length <= capacity else {
                return fail("The record does not fit.", "The \(request.kind.rawValue) record needs \(message.length) bytes, but the tag holds \(capacity) bytes.")
            }
            try await tag.writeNDEF(message)
            var summary = "Wrote a \(request.kind.rawValue) record (\(message.length) of \(capacity) bytes)."
            if request.lock {
                do {
                    try await tag.writeLock()
                    summary += " The tag is now permanently read-only."
                } catch {
                    return fail("Written, but not locked.", summary + " Locking failed: \(error.localizedDescription)")
                }
            }
            report(.wrote(summary))
            session.alertMessage = request.lock ? "Written and locked." : "Written."
            session.invalidate()
        } catch {
            fail("Writing failed.", "Writing failed: \(error.localizedDescription)")
        }
    }
}
#endif
