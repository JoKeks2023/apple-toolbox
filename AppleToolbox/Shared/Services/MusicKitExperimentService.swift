import Foundation
import Combine
#if canImport(MusicKit)
import MusicKit
#endif

enum MusicItemKind: String, CaseIterable, Identifiable {
    case songs = "Songs", albums = "Albums", artists = "Artists", playlists = "Playlists"
    var id: String { rawValue }
}

enum MusicSource: String, CaseIterable, Identifiable {
    case catalog = "Apple Music catalog", library = "My library"
    var id: String { rawValue }
}

/// One search or library result, or a track of an expanded album or playlist.
struct MusicResultRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let detail: String?
    let artworkURL: URL?
    let isFromLibrary: Bool
    #if canImport(MusicKit)
    let item: MusicPlayable?
    #endif

    var isPlayable: Bool {
        #if canImport(MusicKit)
        item != nil
        #else
        false
        #endif
    }

    var hasTracks: Bool {
        #if canImport(MusicKit)
        switch item {
        case .album?, .playlist?: true
        default: false
        }
        #else
        false
        #endif
    }
}

struct MusicQueueRow: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let isCurrent: Bool
}

#if canImport(MusicKit)
/// The MusicKit items this experiment can hand to ApplicationMusicPlayer; artists are not playable.
enum MusicPlayable {
    case song(Song), album(Album), playlist(Playlist), track(Track)
}
#endif

/// MusicKit authorization, account state, catalog search, library requests and ApplicationMusicPlayer playback.
@MainActor
final class MusicExperimentService: ObservableObject {
    @Published var source = MusicSource.catalog
    @Published var kind = MusicItemKind.songs
    @Published var term = ""

    @Published private(set) var output = "Request MusicKit authorization, then search the catalog or read your library."
    @Published private(set) var isError = false
    @Published private(set) var authorization = "Not determined"
    @Published private(set) var isAuthorized = false
    @Published private(set) var storefront: String?
    @Published private(set) var canPlayCatalogContent: Bool?
    @Published private(set) var canBecomeSubscriber: Bool?
    @Published private(set) var hasCloudLibraryEnabled: Bool?
    @Published private(set) var isLoading = false
    @Published private(set) var results: [MusicResultRow] = []
    @Published private(set) var tracks: [String: [MusicResultRow]] = [:]
    @Published private(set) var isPlayerActive = false
    @Published private(set) var playbackStatus = "Stopped"
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackTime: TimeInterval = 0
    @Published private(set) var queue: [MusicQueueRow] = []
    @Published private(set) var queueCount = 0

    private var playerCancellables: Set<AnyCancellable> = []

    init() {
        #if canImport(MusicKit)
        updateAuthorization(MusicAuthorization.currentStatus)
        if isAuthorized { refreshAccount() }
        #else
        authorization = "Unavailable"
        output = "MusicKit is not available on this platform."
        isError = true
        #endif
    }

    // MARK: Authorization and account

    func requestAuthorization() {
        #if canImport(MusicKit)
        Task {
            let status = await MusicAuthorization.request()
            PermissionCenter.shared.invalidate()
            updateAuthorization(status)
            output = switch status {
            case .authorized: "MusicKit authorized. Loading subscription and storefront…"
            case .denied: "Apple Music access denied. Allow Apple Toolbox in Settings › Privacy & Security › Media & Apple Music."
            case .restricted: "Apple Music access is restricted on this device (Screen Time or device management)."
            case .notDetermined: "MusicKit authorization remains undetermined."
            @unknown default: "MusicKit returned an unknown authorization state."
            }
            isError = status != .authorized
            if status == .authorized { refreshAccount() }
        }
        #endif
    }

    /// Reads MusicSubscription and the storefront; both need the MusicKit App Service for the developer token.
    func refreshAccount() {
        #if canImport(MusicKit)
        Task {
            do {
                let subscription = try await MusicSubscription.current
                canPlayCatalogContent = subscription.canPlayCatalogContent
                canBecomeSubscriber = subscription.canBecomeSubscriber
                hasCloudLibraryEnabled = subscription.hasCloudLibraryEnabled
            } catch {
                report(error, context: "MusicSubscription.current")
                return
            }
            do {
                storefront = try await MusicDataRequest.currentCountryCode
                isError = false
                output = "Account ready · storefront \(storefront ?? "?") · catalog playback \(canPlayCatalogContent == true ? "allowed" : "not allowed (no active Apple Music subscription)")."
            } catch {
                report(error, context: "MusicDataRequest.currentCountryCode")
            }
        }
        #endif
    }

    #if canImport(MusicKit)
    private func updateAuthorization(_ status: MusicAuthorization.Status) {
        isAuthorized = status == .authorized
        authorization = switch status {
        case .authorized: "Authorized"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not determined"
        @unknown default: "Unknown"
        }
    }
    #endif

    // MARK: Catalog and library

    func load() {
        #if canImport(MusicKit)
        guard isAuthorized else { isError = true; output = "Request MusicKit authorization first."; return }
        let query = term.trimmingCharacters(in: .whitespacesAndNewlines)
        if source == .catalog, query.isEmpty { isError = true; output = "Enter a search term for the catalog."; return }
        let (source, kind) = (self.source, self.kind)
        isLoading = true
        tracks = [:]
        Task {
            defer { isLoading = false }
            do {
                results = source == .catalog ? try await Self.searchCatalog(query, kind: kind) : try await Self.readLibrary(kind: kind, filter: query)
                isError = false
                let request = source == .catalog ? "MusicCatalogSearchRequest in storefront \(storefront ?? "?")" : "MusicLibraryRequest<\(kind.rawValue.dropLast())>"
                output = results.isEmpty ? "\(request) returned no \(kind.rawValue.lowercased())." : "\(request) returned \(results.count) \(kind.rawValue.lowercased())."
            } catch {
                results = []
                report(error, context: source == .catalog ? "MusicCatalogSearchRequest" : "MusicLibraryRequest")
            }
        }
        #endif
    }

    /// Loads the tracks of an album or playlist with `with([.tracks])`.
    func toggleTracks(for row: MusicResultRow) {
        #if canImport(MusicKit)
        if tracks[row.id] != nil { tracks[row.id] = nil; return }
        Task {
            do {
                let collection: MusicItemCollection<Track>? = switch row.item {
                case .album(let album)?: try await album.with([.tracks]).tracks
                case .playlist(let playlist)?: try await playlist.with([.tracks]).tracks
                default: nil
                }
                tracks[row.id] = (collection ?? []).map { MusicResultRow(track: $0, library: row.isFromLibrary) }
            } catch {
                report(error, context: "\(row.title) · with([.tracks])")
            }
        }
        #endif
    }

    #if canImport(MusicKit)
    private static func searchCatalog(_ term: String, kind: MusicItemKind) async throws -> [MusicResultRow] {
        let type: any MusicCatalogSearchable.Type = switch kind {
        case .songs: Song.self
        case .albums: Album.self
        case .artists: Artist.self
        case .playlists: Playlist.self
        }
        var request = MusicCatalogSearchRequest(term: term, types: [type])
        request.limit = 25
        let response = try await request.response()
        return switch kind {
        case .songs: response.songs.map { MusicResultRow(song: $0, library: false) }
        case .albums: response.albums.map { MusicResultRow(album: $0, library: false) }
        case .artists: response.artists.map { MusicResultRow(artist: $0, library: false) }
        case .playlists: response.playlists.map { MusicResultRow(playlist: $0, library: false) }
        }
    }

    private static func readLibrary(kind: MusicItemKind, filter: String) async throws -> [MusicResultRow] {
        switch kind {
        case .songs:
            var request = MusicLibraryRequest<Song>()
            request.limit = 25
            if !filter.isEmpty { request.filter(text: filter) }
            return try await request.response().items.map { MusicResultRow(song: $0, library: true) }
        case .albums:
            var request = MusicLibraryRequest<Album>()
            request.limit = 25
            if !filter.isEmpty { request.filter(text: filter) }
            return try await request.response().items.map { MusicResultRow(album: $0, library: true) }
        case .artists:
            var request = MusicLibraryRequest<Artist>()
            request.limit = 25
            if !filter.isEmpty { request.filter(text: filter) }
            return try await request.response().items.map { MusicResultRow(artist: $0, library: true) }
        case .playlists:
            var request = MusicLibraryRequest<Playlist>()
            request.limit = 25
            if !filter.isEmpty { request.filter(text: filter) }
            return try await request.response().items.map { MusicResultRow(playlist: $0, library: true) }
        }
    }
    #endif

    // MARK: ApplicationMusicPlayer

    func play(_ row: MusicResultRow) {
        #if canImport(MusicKit) && !os(watchOS)
        guard let item = row.item else { return }
        // MusicKit's player types are not annotated for Swift concurrency. They are only used from main-actor tasks,
        // as in Apple's MusicKit samples; nonisolated(unsafe) lets their async methods be awaited from here.
        nonisolated(unsafe) let player = ApplicationMusicPlayer.shared
        player.queue = switch item {
        case .song(let song): [song]
        case .album(let album): [album]
        case .playlist(let playlist): [playlist]
        case .track(let track): [track]
        }
        observePlayer()
        isPlayerActive = true
        perform("play \(row.title)", catalog: !row.isFromLibrary) { try await player.play() }
        #else
        reportPlayerUnavailable()
        #endif
    }

    func enqueue(_ row: MusicResultRow) {
        #if canImport(MusicKit) && !os(watchOS)
        guard let item = row.item else { return }
        nonisolated(unsafe) let queue = ApplicationMusicPlayer.shared.queue // See play(_:).
        observePlayer()
        perform("queue \(row.title)", catalog: !row.isFromLibrary) {
            switch item {
            case .song(let song): try await queue.insert(song, position: .tail)
            case .album(let album): try await queue.insert(album, position: .tail)
            case .playlist(let playlist): try await queue.insert(playlist, position: .tail)
            case .track(let track): try await queue.insert(track, position: .tail)
            }
        }
        #else
        reportPlayerUnavailable()
        #endif
    }

    func togglePlayPause() {
        #if canImport(MusicKit) && !os(watchOS)
        nonisolated(unsafe) let player = ApplicationMusicPlayer.shared // See play(_:).
        if player.state.playbackStatus == .playing {
            player.pause()
            refreshPlayer()
        } else {
            isPlayerActive = true
            perform("resume", catalog: false) { try await player.play() }
        }
        #endif
    }

    func skip(forward: Bool) {
        #if canImport(MusicKit) && !os(watchOS)
        nonisolated(unsafe) let player = ApplicationMusicPlayer.shared // See play(_:).
        perform(forward ? "skip to next entry" : "skip to previous entry", catalog: false) {
            if forward { try await player.skipToNextEntry() } else { try await player.skipToPreviousEntry() }
        }
        #endif
    }

    /// Stops ApplicationMusicPlayer so music does not keep playing after the experiment is left.
    func stop() {
        #if canImport(MusicKit) && !os(watchOS)
        ApplicationMusicPlayer.shared.stop()
        #endif
        playerCancellables.removeAll()
        isPlayerActive = false
        refreshPlayer()
    }

    #if canImport(MusicKit) && !os(watchOS)
    private func perform(_ action: String, catalog: Bool, _ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
                isError = false
                output = "ApplicationMusicPlayer: \(action) succeeded."
            } catch {
                var context = "ApplicationMusicPlayer · \(action)"
                if catalog, canPlayCatalogContent == false {
                    context += "\nThis Apple Account has no active Apple Music subscription (canPlayCatalogContent is false), so catalog items cannot be played in full. Downloaded or purchased library items can still play."
                }
                report(error, context: context)
            }
            refreshPlayer()
        }
    }

    private func observePlayer() {
        guard playerCancellables.isEmpty else { return }
        ApplicationMusicPlayer.shared.state.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshPlayer() }
            .store(in: &playerCancellables)
        // The queue object is replaced for every new playback, so time and queue are polled once a second.
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in self?.refreshPlayer() }
            .store(in: &playerCancellables)
    }
    #endif

    #if !canImport(MusicKit) || os(watchOS)
    /// watchOS offers MusicKit's catalog and library requests but no ApplicationMusicPlayer.
    private func reportPlayerUnavailable() {
        isError = true
        output = "ApplicationMusicPlayer is unavailable on watchOS, so this app cannot play Apple Music items on Apple Watch. Catalog search and library requests work; play from the Music app or on iPhone."
    }
    #endif

    private func refreshPlayer() {
        #if canImport(MusicKit) && !os(watchOS)
        let player = ApplicationMusicPlayer.shared
        let status = player.state.playbackStatus
        isPlaying = status == .playing
        playbackStatus = switch status {
        case .playing: "Playing"
        case .paused: "Paused"
        case .stopped: "Stopped"
        case .interrupted: "Interrupted"
        case .seekingForward: "Seeking forward"
        case .seekingBackward: "Seeking backward"
        @unknown default: "Unknown"
        }
        playbackTime = player.playbackTime
        let current = player.queue.currentEntry?.id
        let entries = player.queue.entries
        queueCount = entries.count
        queue = entries.prefix(25).map { MusicQueueRow(id: $0.id, title: $0.title, subtitle: $0.subtitle, isCurrent: $0.id == current) }
        #endif
    }

    // MARK: Errors

    private func report(_ error: Error, context: String) {
        isError = true
        output = "\(context) failed.\n" + Self.describe(error)
    }

    static func describe(_ error: Error) -> String {
        #if canImport(MusicKit)
        if let tokenError = error as? MusicTokenRequestError {
            let hint = switch tokenError {
            case .developerTokenRequestFailed: "MusicKit could not get a developer token. Enable the MusicKit App Service for this App ID in Certificates, Identifiers & Profiles, then reinstall with a fresh provisioning profile."
            case .userNotSignedIn: "No Apple Account is signed in for Media & Purchases on this device."
            case .permissionDenied: "Apple Music access is denied for Apple Toolbox."
            case .privacyAcknowledgementRequired: "Open the Music app once and accept Apple Music's privacy notice."
            case .userTokenRevoked: "The Apple Music user token was revoked. Sign in to Apple Music again."
            case .userTokenRequestFailed: "The user token request failed (account, storefront or network)."
            case .unknown: "MusicKit reported an unknown token error."
            @unknown default: "MusicKit reported a token error this app does not know yet."
            }
            return "MusicTokenRequestError.\(tokenError.rawValue): \(error.localizedDescription)\n\(hint)"
        }
        if let dataError = error as? MusicDataRequest.Error {
            return "Apple Music API error · HTTP \(dataError.status) · code \(dataError.code)\n\(dataError.title): \(dataError.detailText)"
        }
        if let subscriptionError = error as? MusicSubscription.Error {
            return "MusicSubscription.Error.\(subscriptionError.rawValue): \(error.localizedDescription)"
        }
        #endif
        let nsError = error as NSError
        return "\(error.localizedDescription)\nDomain: \(nsError.domain) · Code: \(nsError.code)"
    }
}

#if canImport(MusicKit)
private extension MusicResultRow {
    static func artwork(_ artwork: Artwork?) -> URL? { artwork?.url(width: 120, height: 120) }

    static func minutes(_ duration: TimeInterval?) -> String? {
        guard let duration, duration.isFinite else { return nil }
        let seconds = Int(duration.rounded())
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    init(song: Song, library: Bool) {
        self.init(id: song.id.rawValue, title: song.title, subtitle: song.artistName,
                  detail: [song.albumTitle, Self.minutes(song.duration)].compactMap { $0 }.joined(separator: " · "),
                  artworkURL: Self.artwork(song.artwork), isFromLibrary: library, item: .song(song))
    }

    init(album: Album, library: Bool) {
        self.init(id: album.id.rawValue, title: album.title, subtitle: album.artistName,
                  detail: ["\(album.trackCount) tracks", album.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }].compactMap { $0 }.joined(separator: " · "),
                  artworkURL: Self.artwork(album.artwork), isFromLibrary: library, item: .album(album))
    }

    init(artist: Artist, library: Bool) {
        self.init(id: artist.id.rawValue, title: artist.name, subtitle: "Artist · not playable",
                  detail: artist.genreNames?.joined(separator: ", "),
                  artworkURL: Self.artwork(artist.artwork), isFromLibrary: library, item: nil)
    }

    init(playlist: Playlist, library: Bool) {
        self.init(id: playlist.id.rawValue, title: playlist.name, subtitle: playlist.curatorName ?? "Playlist",
                  detail: playlist.shortDescription,
                  artworkURL: Self.artwork(playlist.artwork), isFromLibrary: library, item: .playlist(playlist))
    }

    init(track: Track, library: Bool) {
        self.init(id: track.id.rawValue, title: track.title, subtitle: track.artistName,
                  detail: Self.minutes(track.duration), artworkURL: nil, isFromLibrary: library, item: .track(track))
    }
}
#endif
