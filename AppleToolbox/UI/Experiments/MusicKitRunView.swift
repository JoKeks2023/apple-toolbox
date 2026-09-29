import SwiftUI
#if canImport(MusicKit)
import MusicKit
#endif

extension MusicExperimentService: StoppableExperiment {
    var isActive: Bool { isPlayerActive }
}

struct MusicKitRunView: View {
    @StateObject private var music = MusicExperimentService()

    var body: some View {
        LabeledContent("Authorization", value: music.authorization)
            .experimentSession(music)
        if music.isAuthorized {
            Button("Refresh Account", systemImage: "arrow.clockwise", action: music.refreshAccount)
        } else {
            Button("Request MusicKit Authorization", systemImage: "music.note", action: music.requestAuthorization)
                .buttonStyle(.borderedProminent)
        }
        OutputView(text: music.output, isError: music.isError)
        MusicAccountSection(music: music)
        MusicSearchSection(music: music)
        MusicPlayerSection(music: music)
    }
}

private struct MusicAccountSection: View {
    @ObservedObject var music: MusicExperimentService
    @State private var isShowingOffer = false

    var body: some View {
        Section("Account · MusicSubscription") {
            LabeledContent("Storefront", value: music.storefront?.uppercased() ?? "—")
            LabeledContent("Catalog playback", value: Self.text(music.canPlayCatalogContent, yes: "Allowed", no: "Not allowed"))
            LabeledContent("Can subscribe", value: Self.text(music.canBecomeSubscriber, yes: "Yes", no: "No"))
            LabeledContent("Sync Library", value: Self.text(music.hasCloudLibraryEnabled, yes: "On", no: "Off"))
            #if os(iOS) || os(macOS)
            if music.canBecomeSubscriber == true {
                Button("Show Apple Music Offer", systemImage: "music.note.list") { isShowingOffer = true }
                    .musicSubscriptionOffer(isPresented: $isShowingOffer)
            }
            #endif
            Text("Catalog search and account state need the MusicKit App Service for this App ID. Full catalog playback needs an active Apple Music subscription.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private static func text(_ value: Bool?, yes: String, no: String) -> String {
        value.map { $0 ? yes : no } ?? "—"
    }
}

private struct MusicSearchSection: View {
    @ObservedObject var music: MusicExperimentService

    var body: some View {
        Section(music.source == .catalog ? "Catalog · MusicCatalogSearchRequest" : "Library · MusicLibraryRequest") {
            Picker("Source", selection: $music.source) {
                ForEach(MusicSource.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Type", selection: $music.kind) {
                ForEach(MusicItemKind.allCases) { Text($0.rawValue).tag($0) }
            }
            TextField(music.source == .catalog ? "Search term" : "Filter (optional)", text: $music.term)
                .onSubmit(music.load)
            HStack {
                Button(music.source == .catalog ? "Search Catalog" : "Load Library", systemImage: "magnifyingglass", action: music.load)
                    .buttonStyle(.borderedProminent)
                    .disabled(!music.isAuthorized || music.isLoading)
                if music.isLoading { ProgressView() }
            }
            ForEach(music.results) { row in
                MusicResultRowView(row: row, music: music, showsTracks: music.tracks[row.id] != nil)
                ForEach(music.tracks[row.id] ?? []) { track in
                    MusicResultRowView(row: track, music: music, showsTracks: false)
                        .padding(.leading, 24)
                }
            }
        }
    }
}

private struct MusicResultRowView: View {
    let row: MusicResultRow
    @ObservedObject var music: MusicExperimentService
    let showsTracks: Bool

    var body: some View {
        HStack(spacing: 12) {
            if let artworkURL = row.artworkURL {
                AsyncImage(url: artworkURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.secondary.opacity(0.15)
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).lineLimit(1)
                Text(row.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let detail = row.detail, !detail.isEmpty {
                    Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if row.hasTracks {
                Button(showsTracks ? "Hide Tracks" : "Show Tracks", systemImage: showsTracks ? "chevron.up" : "list.bullet") { music.toggleTracks(for: row) }
                    .labelStyle(.iconOnly)
            }
            if row.isPlayable {
                Button("Play", systemImage: "play.fill") { music.play(row) }
                    .labelStyle(.iconOnly)
                Button("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward") { music.enqueue(row) }
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.borderless)
    }
}

private struct MusicPlayerSection: View {
    @ObservedObject var music: MusicExperimentService

    var body: some View {
        Section("Player · ApplicationMusicPlayer") {
            LabeledContent("State", value: music.playbackStatus)
            LabeledContent("Position") {
                Text(Duration.seconds(music.playbackTime).formatted(.time(pattern: .minuteSecond)))
                    .font(.body.monospacedDigit())
            }
            HStack {
                Button("Previous", systemImage: "backward.fill") { music.skip(forward: false) }
                Button(music.isPlaying ? "Pause" : "Play", systemImage: music.isPlaying ? "pause.fill" : "play.fill", action: music.togglePlayPause)
                Button("Next", systemImage: "forward.fill") { music.skip(forward: true) }
                Button("Stop", systemImage: "stop.fill", action: music.stop)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .disabled(music.queueCount == 0)
            if music.queue.isEmpty {
                Text("The queue is empty. Play or queue a song, album, playlist or track above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Queue · \(music.queueCount) entr\(music.queueCount == 1 ? "y" : "ies")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(music.queue) { entry in
                    HStack {
                        Image(systemName: entry.isCurrent ? "speaker.wave.2.fill" : "music.note")
                            .foregroundStyle(entry.isCurrent ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title).fontWeight(entry.isCurrent ? .semibold : .regular).lineLimit(1)
                            if let subtitle = entry.subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        }
                    }
                }
            }
        }
    }
}
