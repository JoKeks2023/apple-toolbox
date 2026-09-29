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
