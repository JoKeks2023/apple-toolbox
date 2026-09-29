import SwiftUI

struct ShazamKitRunView: View {
    @StateObject private var shazam = ShazamExperimentService()

    var body: some View {
        Group {
            if shazam.isListening {
                Button("Stop Listening", systemImage: "stop.circle", action: shazam.stop)
            } else {
                Button("Start Listening", systemImage: "shazam.logo", action: shazam.start)
            }
        }
        .buttonStyle(.borderedProminent)
        .experimentSession(shazam)
        if shazam.isListening {
            ProgressView("Listening through the microphone…")
        }
        ForEach(shazam.matches) { ShazamMatchView(item: $0) }
        OutputView(text: shazam.output, isError: [.unavailable, .permissionDenied, .hardwareUnsupported, .platformUnsupported].contains(shazam.status))
        ShazamCustomCatalogSection(shazam: shazam)
    }
}

/// SHSignatureGenerator from the microphone → SHCustomCatalog with metadata → SHSession(catalog:).
private struct ShazamCustomCatalogSection: View {
    @ObservedObject var shazam: ShazamExperimentService

    var body: some View {
        Section("Custom catalog · SHCustomCatalog") {
            TextField("Reference title", text: $shazam.referenceTitle)
            TextField("Reference artist (optional)", text: $shazam.referenceArtist)
            Picker("Capture length", selection: $shazam.captureLength) {
                ForEach(ShazamCaptureLength.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .disabled(shazam.isCapturing)
            if let mode = shazam.captureMode {
                ProgressView(mode == .reference ? "Recording reference signature…" : "Recording query signature…", value: shazam.captureProgress)
                Button("Cancel", systemImage: "xmark.circle", role: .cancel, action: shazam.cancelCapture)
            } else {
                HStack {
                    Button("Record Reference", systemImage: "waveform.badge.plus", action: shazam.recordReference)
                        .buttonStyle(.borderedProminent)
                    Button("Match Against Catalog", systemImage: "waveform.badge.magnifyingglass", action: shazam.recordQuery)
                        .buttonStyle(.bordered)
                        .disabled(shazam.catalogEntries.isEmpty)
                }
                .disabled(shazam.isListening)
            }
            ForEach(shazam.catalogEntries) { entry in
                LabeledContent(entry.title) {
                    Text([entry.artist, entry.duration.formatted(.number.precision(.fractionLength(1))) + " s"].compactMap { $0 }.joined(separator: " · "))
                }
            }
            #if !os(tvOS)
            if let url = shazam.catalogFileURL {
                ShareLink(item: url) { Label("Share .shazamcatalog", systemImage: "square.and.arrow.up") }
            }
            #endif
            ForEach(shazam.catalogMatches) { ShazamMatchView(item: $0) }
            OutputView(text: shazam.catalogOutput, isError: shazam.catalogIsError)
        }
    }
}

private struct ShazamMatchView: View {
    let item: ShazamMatchedItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                if let artworkURL = item.artworkURL {
                    AsyncImage(url: artworkURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title).font(.headline)
                    if let artist = item.artist { Text(artist).font(.subheadline) }
                    if let subtitle = item.subtitle, subtitle != item.artist { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
                    if !item.genres.isEmpty { Text(item.genres.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                }
            }
            LabeledContent("Match offset", value: item.matchOffset.formatted(.number.precision(.fractionLength(1))) + " s")
            LabeledContent("Confidence", value: item.confidence.formatted(.percent.precision(.fractionLength(0))))
            if let isrc = item.isrc { LabeledContent("ISRC", value: isrc) }
            if item.explicitContent { LabeledContent("Content", value: "Explicit") }
            if let appleMusicURL = item.appleMusicURL {
                Link(destination: appleMusicURL) { Label("Open in Apple Music", systemImage: "music.note") }
            }
            if let webURL = item.webURL {
                Link(destination: webURL) { Label("Open on Shazam", systemImage: "safari") }
            }
            if let artworkURL = item.artworkURL {
                Link(destination: artworkURL) { Label("Open Artwork", systemImage: "photo") }
            }
        }
        .padding(.vertical, 4)
    }
}
