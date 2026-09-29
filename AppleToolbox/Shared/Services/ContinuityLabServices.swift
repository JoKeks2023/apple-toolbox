import Foundation
import Combine
#if canImport(AppIntents) && !os(watchOS)
import AppIntents
#endif
#if canImport(GroupActivities) && (os(iOS) || os(macOS))
import GroupActivities
import CoreTransferable
#endif

// MARK: - Handoff

/// The `NSUserActivity` each open experiment advertises for Handoff. Handoff only offers activity types the
/// receiving app declares in `NSUserActivityTypes`, and only between apps signed by the same team.
nonisolated enum ExperimentHandoff {
    /// Info.plist declares it as `$(BUNDLE_ID_PREFIX).AppleToolbox.experiment`.
    static let activityType = "\(ToolboxIdentifiers.base).experiment"
    static let experimentIDKey = "experimentID"
    static let infoPlistKey = "NSUserActivityTypes"

    static func userInfo(for experimentID: String) -> [String: String] { [experimentIDKey: experimentID] }

    static func experimentID(from userInfo: [AnyHashable: Any]?) -> String? {
        guard let id = userInfo?[experimentIDKey] as? String, !id.isEmpty else { return nil }
        return id
    }

    static func isDeclared(in infoDictionary: [String: Any]?) -> Bool {
        (infoDictionary?[infoPlistKey] as? [String])?.contains(activityType) == true
    }
}

extension ExperimentHandoff {
    /// Fills the activity SwiftUI advertises while an experiment is on screen.
    @MainActor static func configure(_ activity: NSUserActivity, for experiment: ExperimentDescriptor) {
        activity.title = experiment.name
        activity.userInfo = userInfo(for: experiment.id)
        activity.requiredUserInfoKeys = [experimentIDKey]
        activity.targetContentIdentifier = experiment.id
        activity.isEligibleForHandoff = true
        #if os(iOS) || os(macOS)
        // Spotlight already indexes the experiment as an IndexedEntity; a searchable activity would duplicate it.
        activity.isEligibleForSearch = false
        #endif
        #if canImport(AppIntents) && !os(watchOS)
        // Tells Siri and Apple Intelligence which entity is on screen.
        activity.appEntityIdentifier = EntityIdentifier(for: ExperimentEntity(experiment))
        #endif
    }

    /// Opens the experiment a Handoff from another device carries.
    @MainActor static func continueActivity(_ activity: NSUserActivity) {
        guard let id = experimentID(from: activity.userInfo), let experiment = ExperimentRegistry.descriptor(for: id) else {
            ToolboxActivityLog.shared.record(.handoff, "Handoff without a known experiment", "userInfo: \(activity.userInfo.map { "\($0)" } ?? "nil")")
            return
        }
        ToolboxNavigator.shared.request = .experiment(experiment.id)
        ToolboxActivityLog.shared.record(.handoff, "Continued \(experiment.name) from another device", activity.activityType)
    }
}

// MARK: - Sharing an experiment summary

enum ExperimentShareSummary {
    /// Plain-text summary for ShareLink and AirDrop: what the experiment is, its live status here, and where the documentation is.
    static func text(for experiment: ExperimentDescriptor, status: ExperimentStatus, platform: SupportedPlatform) -> String {
        var lines = [
            "Apple Toolbox · \(experiment.name) (\(experiment.category.rawValue))",
            "Status on \(platform.rawValue): \(status.title)",
            "",
            experiment.description,
            "",
            "Frameworks: \(experiment.frameworks.joined(separator: ", "))",
            "Platforms: \(experiment.supportedPlatforms.map(\.rawValue).joined(separator: " · "))",
        ]
        if !experiment.hardwareRequirements.isEmpty { lines.append("Hardware: \(experiment.hardwareRequirements.joined(separator: ", "))") }
        if !experiment.permissions.isEmpty { lines.append("Permissions: \(experiment.permissions.joined(separator: ", "))") }
        if !experiment.entitlements.isEmpty { lines.append("Entitlements: \(experiment.entitlements.joined(separator: ", "))") }
        lines.append("Documentation: \(experiment.documentationURL.absoluteString)")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Universal Links

/// One `applinks:` entry of the Associated Domains entitlement.
nonisolated struct AppLinkDomain: Equatable, Sendable {
    let host: String
    /// Alternate mode from a `?mode=` suffix (developer, managed or developer+managed).
    let mode: String?
}

nonisolated enum AASASource: String, CaseIterable, Identifiable, Sendable {
    case appleCDN = "Apple CDN"
    case domain = "Domain"

    var id: String { rawValue }
}

nonisolated enum UniversalLinks {
    static let entitlementKey = "com.apple.developer.associated-domains"

    /// The `applinks:` entries of a rendered entitlement value (entries separated by commas).
    static func appLinkDomains(fromEntitlementValue value: String) -> [AppLinkDomain] {
        value.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("applinks:") }
            .compactMap { entry in
                let parts = entry.dropFirst("applinks:".count).split(separator: "?", maxSplits: 1)
                guard let host = parts.first, !host.isEmpty else { return nil }
                let mode = parts.count > 1 ? parts[1].split(separator: "=", maxSplits: 1).last.map(String.init) : nil
                return AppLinkDomain(host: String(host), mode: mode)
            }
    }

    /// The host of a typed domain without scheme, `applinks:` prefix, port or path; nil if it is no plausible host name.
    static func normalizedHost(_ input: String) -> String? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("applinks:") { text.removeFirst("applinks:".count) }
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        text = String(text.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != ":" })
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        guard text.contains("."), !text.hasPrefix("."), !text.hasSuffix("."), !text.contains(".."),
              text.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return text
    }

    /// Where the file is read from: devices fetch it through Apple's CDN, which caches the domain's `/.well-known` file.
    static func url(for host: String, source: AASASource) -> URL? {
        switch source {
        case .appleCDN: URL(string: "https://app-site-association.cdn-apple.com/a/v1/\(host)")
        case .domain: URL(string: "https://\(host)/.well-known/apple-app-site-association")
        }
    }

    /// Readable result of one fetch, and whether the file links this app (nil when it could not be decided).
    static func report(requestedURL: URL, finalURL: URL?, statusCode: Int?, contentType: String?, data: Data, appID: String?) -> (text: String, linksThisApp: Bool?) {
        var lines = ["GET \(requestedURL.absoluteString)", "HTTP \(statusCode.map(String.init) ?? "?") · \(data.count) bytes · \(contentType ?? "no Content-Type")"]
        if let finalURL, finalURL != requestedURL {
            lines.append("Redirected to \(finalURL.absoluteString). Apple's CDN does not follow redirects, so the file must be served at this exact URL.")
        }
        guard statusCode == 200 else {
            lines.append(statusCode == 404 ? "No apple-app-site-association file: Universal Links cannot open the app for this domain." : "The request did not return the file.")
            return (lines.joined(separator: "\n"), statusCode == 404 ? false : nil)
        }
        let document: AASADocument
        do {
            document = try AASADocument.parse(data)
        } catch {
            lines.append("Not a valid apple-app-site-association JSON document: \(error.localizedDescription)")
            return (lines.joined(separator: "\n"), false)
        }
        if document.appLinkDetails.isEmpty {
            lines.append("The file has no applinks details, so it enables no Universal Links.")
        }
        for detail in document.appLinkDetails {
            lines.append("applinks · \(detail.appIDs.joined(separator: ", "))")
            lines.append(contentsOf: detail.patterns.prefix(8).map { "  \($0)" })
            if detail.patterns.count > 8 { lines.append("  … \(detail.patterns.count - 8) more") }
        }
        if !document.webCredentialApps.isEmpty { lines.append("webcredentials · \(document.webCredentialApps.joined(separator: ", "))") }
        if !document.activityContinuationApps.isEmpty { lines.append("activitycontinuation · \(document.activityContinuationApps.joined(separator: ", "))") }
        guard let appID else {
            lines.append("This app's App ID is unknown (no embedded profile or signed entitlements to read it from), so the match cannot be checked.")
            return (lines.joined(separator: "\n"), nil)
        }
        let linked = document.linksApp(appID)
        lines.append(linked ? "The file lists this app (\(appID)) for applinks." : "The file does not list this app (\(appID)) for applinks.")
        return (lines.joined(separator: "\n"), linked)
    }
}

/// The parts of an apple-app-site-association file that decide Universal Links, shared web credentials and Handoff to the web.
nonisolated struct AASADocument: Equatable, Sendable {
    struct AppLinkDetail: Equatable, Sendable {
        let appIDs: [String]
        /// `components` (or legacy `paths`) rendered one pattern per line; excluded patterns start with "NOT".
        let patterns: [String]
    }

    enum ParseError: LocalizedError {
        case notAnObject

        var errorDescription: String? { "The top level is not a JSON object." }
    }

    let appLinkDetails: [AppLinkDetail]
    let webCredentialApps: [String]
    let activityContinuationApps: [String]

    func linksApp(_ appID: String) -> Bool {
        appLinkDetails.contains { $0.appIDs.contains(appID) }
    }

    static func parse(_ data: Data) throws -> AASADocument {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ParseError.notAnObject }
        let details = ((root["applinks"] as? [String: Any])?["details"] as? [[String: Any]] ?? []).map { detail in
            let appIDs = detail["appIDs"] as? [String] ?? (detail["appID"] as? String).map { [$0] } ?? []
            let components = (detail["components"] as? [[String: Any]] ?? []).map(render)
            let paths = detail["paths"] as? [String] ?? []
            return AppLinkDetail(appIDs: appIDs, patterns: components + paths)
        }
        func apps(_ key: String) -> [String] { (root[key] as? [String: Any])?["apps"] as? [String] ?? [] }
        return AASADocument(appLinkDetails: details, webCredentialApps: apps("webcredentials"), activityContinuationApps: apps("activitycontinuation"))
    }

    private static func render(_ component: [String: Any]) -> String {
        var pattern = component["/"] as? String ?? "*"
        if component["?"] != nil { pattern += " ?query" }
        if let fragment = component["#"] as? String { pattern += " #\(fragment)" }
        return (component["exclude"] as? Bool == true ? "NOT " : "") + pattern
    }
}

/// Associated Domains state and the apple-app-site-association check of the Continuity run view.
@MainActor
final class UniversalLinksService: ObservableObject {
    @Published private(set) var state: ProvisioningState = .unknown("Not read yet.")
    @Published private(set) var domains: [AppLinkDomain] = []
    @Published private(set) var isWildcardOnly = false
    @Published private(set) var appID: String?
    @Published private(set) var output = "Enter a domain to fetch its apple-app-site-association file."
    @Published private(set) var isError = false
    @Published private(set) var isChecking = false
    @Published var host = ""
    @Published var source: AASASource = .appleCDN

    func refresh() {
        state = IdentityEntitlements.state(ofCapability: "associated-domains")
        var value: String? = switch state {
        case .provisioned(let value), .declared(let value): value
        default: nil
        }
        if value == "*", let signed = SignedEntitlements.value(for: UniversalLinks.entitlementKey) { value = signed }
        isWildcardOnly = value == "*"
        domains = UniversalLinks.appLinkDomains(fromEntitlementValue: value ?? "")
        appID = Self.currentAppID()
        if host.isEmpty, let first = domains.first { host = first.host }
    }

    var entitlementSummary: String {
        if !domains.isEmpty {
            let entries = domains.map { domain in domain.mode.map { "\(domain.host) (mode \($0))" } ?? domain.host }
            return "applinks for \(entries.joined(separator: ", ")) (\(state.title.lowercased()))."
        }
        if isWildcardOnly {
            return "The embedded profile allows any associated domain (*); the concrete applinks entries exist only in the code signature, which this platform does not let apps read."
        }
        if state.isPresent {
            return "Associated Domains is present, but without an applinks: entry, so no domain can open Apple Toolbox with a Universal Link."
        }
        return IdentityEntitlements.summary(of: state, key: UniversalLinks.entitlementKey) + " Without an applinks: entry no Universal Link opens Apple Toolbox."
    }

    func check() {
        guard let host = UniversalLinks.normalizedHost(host), let url = UniversalLinks.url(for: host, source: source) else {
            output = "Enter a host name such as example.com."
            isError = true
            return
        }
        isChecking = true
        output = "Fetching \(url.absoluteString)…"
        isError = false
        let appID = appID
        Task {
            do {
                let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                let (data, response) = try await URLSession.shared.data(for: request)
                let http = response as? HTTPURLResponse
                let result = UniversalLinks.report(requestedURL: url, finalURL: response.url, statusCode: http?.statusCode,
                                                   contentType: http?.value(forHTTPHeaderField: "Content-Type"), data: data, appID: appID)
                output = result.text
                isError = result.linksThisApp != true
            } catch {
                output = "GET \(url.absoluteString) failed: \(error.localizedDescription)"
                isError = true
            }
            isChecking = false
        }
    }

    /// "<Team ID>.<bundle ID>" from the embedded profile, or from the signed entitlements where they are readable.
    private static func currentAppID() -> String? {
        let keys = ["application-identifier", "com.apple.application-identifier"]
        let profile = ProvisioningInspector.load().profile
        for key in keys {
            if let value = profile?.entitlements[key] ?? SignedEntitlements.value(for: key) { return value }
        }
        return nil
    }
}

// MARK: - SharePlay

#if canImport(GroupActivities) && (os(iOS) || os(macOS))
/// "Explore together": everyone in the FaceTime call or Messages conversation follows the experiment a participant opens.
nonisolated struct ExploreTogetherActivity: GroupActivity, Sendable {
    static let activityIdentifier = "\(ToolboxIdentifiers.base).explore-together"

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Explore Apple Toolbox"
        metadata.subtitle = "Everyone follows the experiment a participant opens."
        metadata.type = .exploreTogether
        return metadata
    }
}

/// Lets ShareLink offer the activity, which starts SharePlay even when no FaceTime call is active yet.
nonisolated extension ExploreTogetherActivity: Transferable {}

/// The message participants exchange: the experiment someone opened.
nonisolated struct ExperimentSelectionMessage: Codable, Equatable, Sendable {
    let experimentID: String
    let platform: String
}

/// Owns the app's SharePlay session. It lives for the whole app, not one run view, so participants keep following
/// each other while they browse; leaving the Continuity experiment does not end it.
@MainActor
final class SharePlayCoordinator: ObservableObject {
    enum SessionState: Equatable {
        case idle, waiting, joined
        case invalidated(String)

        var title: String {
            switch self {
            case .idle: "No session"
            case .waiting: "Waiting"
            case .joined: "Joined"
            case .invalidated: "Ended"
            }
        }
    }

    static let shared = SharePlayCoordinator()

    @Published private(set) var state: SessionState = .idle
    @Published private(set) var participantCount = 0
    @Published private(set) var sharedExperimentID: String?
    @Published private(set) var isActivating = false
    @Published private(set) var output = "Start Explore Together during a FaceTime call, or share it to start one."
    @Published private(set) var isError = false

    private var session: GroupSession<ExploreTogetherActivity>?
    private var messenger: GroupSessionMessenger?
    private var sessionTasks: [Task<Void, Never>] = []
    private var knownParticipants: Set<Participant> = []
    private var isObservingSessions = false

    var localParticipantID: String? { session.map { String($0.localParticipant.id.uuidString.prefix(8)) } }

    /// Receives every session of the activity, including ones another participant started. Runs while the root view exists.
    func observeSessions() async {
        guard !isObservingSessions else { return }
        isObservingSessions = true
        defer { isObservingSessions = false }
        for await session in ExploreTogetherActivity.sessions() {
            configure(session)
        }
    }

    func startExploring() {
        isActivating = true
        Task {
            let activity = ExploreTogetherActivity()
            switch await activity.prepareForActivation() {
            case .activationPreferred:
                do {
                    let started = try await activity.activate()
                    output = started
                        ? "activate() returned true: SharePlay creates the session and delivers it to every participant's app."
                        : "activate() returned false: no session was created, for example because the activity moved to an Apple TV."
                    isError = !started
                } catch {
                    output = "activate() failed: \(Self.describe(error))"
                    isError = true
                }
            case .activationDisabled:
                output = "prepareForActivation() returned .activationDisabled: there is no FaceTime call or Messages conversation to share into, or the person chose not to use SharePlay."
                isError = true
            case .cancelled:
                output = "prepareForActivation() returned .cancelled: the system prompt was dismissed."
                isError = true
            @unknown default:
                output = "prepareForActivation() returned an unknown result."
                isError = true
            }
            isActivating = false
        }
    }

    /// Shares the experiment that just opened on this device, unless it already is the group's selection.
    func experimentOpened(_ experimentID: String) {
        guard state == .joined, sharedExperimentID != experimentID else { return }
        send(experimentID)
    }

    func send(_ experimentID: String) {
        guard state == .joined, let messenger else {
            output = "Join a SharePlay session first."
            isError = true
            return
        }
        sharedExperimentID = experimentID
        let name = ExperimentRegistry.descriptor(for: experimentID)?.name ?? experimentID
        let message = ExperimentSelectionMessage(experimentID: experimentID, platform: CurrentPlatform.value.rawValue)
        Task {
            do {
                try await messenger.send(message)
                ToolboxActivityLog.shared.record(.sharePlay, "Shared \(name) with the group", "GroupSessionMessenger.send(_:) to all participants")
            } catch {
                ToolboxActivityLog.shared.record(.sharePlay, "Could not share \(name)", Self.describe(error))
            }
        }
    }

    func leave() {
        session?.leave()
        ToolboxActivityLog.shared.record(.sharePlay, "Left the session", "GroupSession.leave(): the others continue without this device.")
    }

    func endForEveryone() {
        session?.end()
        ToolboxActivityLog.shared.record(.sharePlay, "Ended the session for everyone", "GroupSession.end()")
    }

    private func configure(_ session: GroupSession<ExploreTogetherActivity>) {
        tearDown()
        self.session = session
        let messenger = GroupSessionMessenger(session: session)
        self.messenger = messenger
        state = .waiting
        sessionTasks = [
            Task { [weak self] in
                for await state in session.$state.values { self?.apply(state) }
            },
            Task { [weak self] in
                for await participants in session.$activeParticipants.values { self?.participantsChanged(participants) }
            },
            Task { [weak self] in
                for await (message, context) in messenger.messages(of: ExperimentSelectionMessage.self) {
                    self?.receive(message, from: context.source)
                }
            },
        ]
        session.join()
        ToolboxActivityLog.shared.record(.sharePlay, "Joined a SharePlay session",
                                         session.isLocallyInitiated ? "Started on this device." : "Started by another participant.")
    }

    private func apply(_ newState: GroupSession<ExploreTogetherActivity>.State) {
        switch newState {
        case .waiting:
            state = .waiting
        case .joined:
            state = .joined
        case .invalidated(let reason):
            state = .invalidated(Self.describe(reason))
            ToolboxActivityLog.shared.record(.sharePlay, "Session ended", Self.describe(reason))
            sharedExperimentID = nil
            tearDown()
        @unknown default:
            break
        }
    }

    /// Updates the count and brings late joiners to the group's current experiment.
    private func participantsChanged(_ participants: Set<Participant>) {
        participantCount = participants.count
        guard let session, let messenger else { return }
        let newcomers = participants.subtracting(knownParticipants).subtracting([session.localParticipant])
        knownParticipants = participants
        guard let experimentID = sharedExperimentID, !newcomers.isEmpty else { return }
        let message = ExperimentSelectionMessage(experimentID: experimentID, platform: CurrentPlatform.value.rawValue)
        Task {
            for newcomer in newcomers {
                try? await messenger.send(message, to: .only(newcomer))
            }
        }
    }

    private func receive(_ message: ExperimentSelectionMessage, from participant: Participant) {
        let source = "\(message.platform) · participant \(participant.id.uuidString.prefix(8))"
        guard let experiment = ExperimentRegistry.descriptor(for: message.experimentID) else {
            ToolboxActivityLog.shared.record(.sharePlay, "Unknown experiment “\(message.experimentID)”", "\(source); this version of Apple Toolbox does not have it.")
            return
        }
        sharedExperimentID = experiment.id
        ToolboxNavigator.shared.request = .experiment(experiment.id)
        ToolboxActivityLog.shared.record(.sharePlay, "Followed \(experiment.name)", source)
    }

    private func tearDown() {
        sessionTasks.forEach { $0.cancel() }
        sessionTasks = []
        messenger = nil
        session = nil
        knownParticipants = []
        participantCount = 0
    }

    static func describe(_ error: Error) -> String {
        let error = error as NSError
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
#endif
