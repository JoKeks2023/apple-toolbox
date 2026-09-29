import SwiftUI

struct CoreNFCRunView: View {
    @StateObject private var nfc = NFCExperimentService()

    var body: some View {
        Button(nfc.isScanning ? "Scanning…" : "Scan NFC Tag", action: nfc.start).buttonStyle(.borderedProminent).disabled(nfc.isScanning)
            .experimentSession(nfc)
        NFCRecordsView(records: nfc.records)
        OutputView(text: nfc.output, isError: nfc.output.localizedCaseInsensitiveContains("not available") || nfc.output.localizedCaseInsensitiveContains("error"))
    }
}

private struct NFCRecordsView: View {
    let records: [NFCRecordResult]

    var body: some View {
        Section("NDEF records (\(records.count))") {
            if records.isEmpty {
                Text("Scan a physical NFC tag to inspect its records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(records) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.type)
                            .font(.headline)
                        Text("Format \(record.format) · Payload \(record.payloadBytes) bytes")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

struct NFCInspectorRunView: View {
    @StateObject private var nfc = NFCInspectorService()
    @State private var confirmLock = false

    var body: some View {
        Picker("Polling", selection: $nfc.polling) {
            ForEach(NFCInspectorService.Polling.allCases) { Text($0.rawValue).tag($0) }
        }
        if nfc.declaredAIDs.isEmpty {
            LabeledContent("SELECT AID", value: "None declared in Info.plist")
        } else {
            Picker("SELECT AID", selection: $nfc.selectedAID) {
                ForEach(nfc.declaredAIDs, id: \.self) { aid in
                    Text("\(NFCKnownIdentifiers.applicationName(forAID: aid)) · \(aid)").tag(aid)
                }
            }
        }
        if nfc.polling.includesFeliCa && !nfc.declaredSystemCodes.isEmpty {
            Picker("FeliCa system code", selection: $nfc.selectedSystemCode) {
                ForEach(nfc.declaredSystemCodes, id: \.self) { code in
                    Text("\(code) · \(NFCKnownIdentifiers.systemCodeName(code))").tag(code)
                }
            }
        }
        if nfc.polling == .all || nfc.polling == .iso14443 {
            Picker("MIFARE Ultralight READ page", selection: $nfc.readOptions.ultralightPage) {
                ForEach(NFCReadOptions.ultralightPageChoices, id: \.self) { Text("Pages \($0)–\(Int($0) + 3)").tag($0) }
            }
        }
        if nfc.polling == .all || nfc.polling == .iso15693 {
            Picker("ISO 15693 first block", selection: $nfc.readOptions.blockStart) {
                ForEach(NFCReadOptions.blockStartChoices, id: \.self) { Text("Block \($0)").tag($0) }
            }
            Picker("ISO 15693 block count", selection: $nfc.readOptions.blockCount) {
                ForEach(NFCReadOptions.blockCountChoices, id: \.self) { Text($0 == 1 ? "1 block (single read)" : "\($0) blocks").tag($0) }
            }
        }
        HStack {
            Button(nfc.activity == .inspecting ? "Inspecting…" : "Inspect Tag", systemImage: "wave.3.right", action: nfc.inspect)
                .buttonStyle(.borderedProminent)
                .disabled(nfc.isActive)
            if nfc.isActive {
                Button("Stop", action: nfc.stop).buttonStyle(.bordered)
            }
        }
        .experimentSession(nfc)
        OutputView(text: nfc.output, isError: nfc.isError)
        if let tag = nfc.lastTag {
            NFCInspectedTagView(tag: tag)
        }
        Section("Write NDEF") {
            Picker("Record", selection: $nfc.recordKind) {
                ForEach(NDEFRecordKind.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField(nfc.recordKind == .uri ? "URI, for example https://example.com" : "Text to write", text: $nfc.recordContent)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                .keyboardType(nfc.recordKind == .uri ? .URL : .default)
                #endif
            Toggle("Lock the tag after writing (permanent)", isOn: $nfc.lockAfterWriting)
            Button(nfc.activity == .writing ? "Writing…" : nfc.lockAfterWriting ? "Write and Lock Tag" : "Write Tag", systemImage: "square.and.pencil") {
                if nfc.lockAfterWriting { confirmLock = true } else { nfc.write() }
            }
            .disabled(nfc.isActive)
            .confirmationDialog("Permanently lock the tag?", isPresented: $confirmLock, titleVisibility: .visible) {
                Button("Write and Lock", role: .destructive, action: nfc.write)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("After writing, Core NFC makes the tag read-only. This cannot be undone on the tag or from any app.")
            }
            Text("Writing uses an NDEF reader session, which finds every NDEF-capable tag type. A text record uses the current language (\(Locale.current.identifier)).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Inspector history (\(nfc.history.count))") {
            if nfc.history.isEmpty {
                Text("Inspected tags appear here, newest first. The last \(NFCInspectorHistory.limit) stay on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(nfc.history) { tag in
                    Button { nfc.show(tag) } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(tag.technology).font(.headline)
                                Spacer()
                                Text(tag.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(tag.identifier).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Button("Clear History", role: .destructive, action: nfc.clearHistory)
            }
        }
    }
}

struct NFCCardEmulationRunView: View {
    @StateObject private var card = NFCCardEmulationService()

    var body: some View {
        Section("Eligibility") {
            ForEach(card.checks) { check in
                LabeledContent {
                    Text(check.value).font(.caption).multilineTextAlignment(.trailing)
                } label: {
                    Label(check.title, systemImage: check.passed == true ? "checkmark.circle.fill" : check.passed == false ? "xmark.octagon.fill" : "minus.circle")
                }
            }
            Button("Re-check Eligibility", systemImage: "arrow.clockwise") {
                Task { await card.refreshChecks() }
            }
        }
        .task { await card.refreshChecks() }
        Picker("Start emulation", selection: $card.startMode) {
            ForEach(NFCCardEmulationService.StartMode.allCases) { Text($0.rawValue).tag($0) }
        }
        LabeledContent("Demo AID") {
            Text(CardEmulationDemo.aidHex).font(.caption.monospaced())
        }
        HStack {
            Button(card.isRunning ? "Session running…" : "Start Card Session", systemImage: "wave.3.left", action: card.start)
                .buttonStyle(.borderedProminent)
                .disabled(!card.canStart || card.isRunning)
            if card.isRunning {
                Button("Stop", action: card.stop).buttonStyle(.bordered)
            }
        }
        .experimentSession(card)
        LabeledContent("Presentment intent", value: card.presentment)
        HStack {
            Button("Acquire Presentment Intent", action: card.acquirePresentmentIntent)
                .disabled(!card.canStart)
            Button("Release", action: card.releasePresentmentIntent)
        }
        .buttonStyle(.bordered)
        OutputView(text: card.output, isError: card.isError)
        Section("Session events (\(card.events.count))") {
            if card.events.isEmpty {
                Text("sessionStarted, readerDetected, each received APDU with the demo response, readerDeselected and sessionInvalidated appear here, newest first. The demo card only answers SELECT \(CardEmulationDemo.aidHex).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(card.events.enumerated()), id: \.offset) { _, event in
                    Text(event).font(.caption.monospaced())
                }
            }
        }
    }
}
private struct NFCInspectedTagView: View {
    let tag: NFCInspectedTag

    var body: some View {
        Section("\(tag.technology) tag · \(tag.date.formatted(date: .omitted, time: .standard))") {
            LabeledContent("Identifier") {
                Text(tag.identifier).font(.caption.monospaced())
            }
            ForEach(tag.fields) { field in
                LabeledContent(field.label) {
                    Text(field.value).font(.caption.monospaced()).multilineTextAlignment(.trailing)
                }
            }
            ForEach(tag.exchanges) { exchange in
                VStack(alignment: .leading, spacing: 4) {
                    Label(exchange.title, systemImage: "arrow.left.arrow.right").font(.subheadline.weight(.semibold))
                    Text("→ \(exchange.command)").font(.caption.monospaced())
                    if let error = exchange.error {
                        Text("✕ \(error)").font(.caption).foregroundStyle(.red)
                    } else {
                        Text("← \(exchange.response ?? "No data")").font(.caption.monospaced())
                        Text("SW \(exchange.statusWord ?? "—") · \(exchange.meaning ?? "")")
                            .font(.caption.monospaced())
                            .foregroundStyle(exchange.statusWord == "9000" ? .green : .orange)
                    }
                }
            }
            if !tag.ndefRecords.isEmpty {
                ForEach(Array(tag.ndefRecords.enumerated()), id: \.offset) { index, record in
                    LabeledContent("NDEF record \(index + 1)") {
                        Text(record).font(.caption).multilineTextAlignment(.trailing)
                    }
                }
            }
        }
    }
}
