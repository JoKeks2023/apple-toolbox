import Foundation
import Combine
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import UIKit
#endif

enum LiveActivityRunLength: Int, CaseIterable, Identifiable {
    case oneMinute = 60, fiveMinutes = 300, fifteenMinutes = 900

    /// Seconds between two samples while the app updates the activity itself.
    static let sampleInterval = 15
    /// Without a new update the system marks the activity stale after this many seconds.
    static let staleAfter = 45

    var id: Int { rawValue }
    var title: String { rawValue < 120 ? "1 minute" : "\(rawValue / 60) minutes" }
    var totalSamples: Int { rawValue / Self.sampleInterval }
}

enum LiveActivityDismissalChoice: String, CaseIterable, Identifiable {
    case standard, immediate, afterOneMinute

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Default (stays up to 4 h)"
        case .immediate: "Immediately"
        case .afterOneMinute: "After 1 minute"
        }
    }

    #if canImport(ActivityKit) && os(iOS)
    func policy(endingAt date: Date) -> ActivityUIDismissalPolicy {
        switch self {
        case .standard: .default
        case .immediate: .immediate
        case .afterOneMinute: .after(date.addingTimeInterval(60))
        }
    }
    #endif
}

/// Real device values that each sample of the measurement run carries.
nonisolated enum LiveActivityReading {
    static func battery(level: Float, state: String) -> String {
        level < 0 ? "Battery level unavailable" : "Battery \(Int((level * 100).rounded())) % · \(state)"
    }

    static func thermal(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: "Thermal nominal"
        case .fair: "Thermal fair"
        case .serious: "Thermal serious"
        case .critical: "Thermal critical"
        @unknown default: "Thermal state \(state.rawValue)"
        }
    }
}

/// One Live Activity of this app as plain values.
nonisolated struct LiveActivitySummary: Identifiable, Equatable, Sendable {
    let id: String
    let state: String
    let detail: String
}

#if canImport(ActivityKit) && os(iOS)
nonisolated enum LiveActivityErrors {
    static func title(_ state: ActivityState) -> String {
        switch state {
        case .pending: "pending"
        case .active: "active"
        case .ended: "ended"
        case .dismissed: "dismissed"
        case .stale: "stale"
        @unknown default: "unknown"
        }
    }

    /// Why `Activity.request` refused, in terms of what the person or the developer can change.
    static func explain(_ error: any Error) -> String {
        guard let error = error as? ActivityAuthorizationError else { return "Activity.request failed: \(error.localizedDescription)" }
        let reason = switch error {
        case .denied: "Live Activities are turned off for Apple Toolbox (Settings › Apple Toolbox › Live Activities)."
        case .unsupported: "This device does not support Live Activities."
        case .visibility: "Live Activities can only be started while the app is in the foreground."
        case .attributesTooLarge: "Attributes and content state exceed ActivityKit's 4 KB limit."
        case .globalMaximumExceeded: "The device already shows the maximum number of Live Activities."
        case .targetMaximumExceeded: "Apple Toolbox already runs the maximum number of Live Activities; end one first."
        case .unentitled, .unsupportedTarget: "The system does not accept this app as a Live Activity target; the app's Info.plist must set NSSupportsLiveActivities."
        case .persistenceFailure: "The system could not persist the Live Activity."
        case .missingProcessIdentifier, .reconnectNotPermitted, .malformedActivityIdentifier: "The system rejected the request for this process."
        @unknown default: "ActivityKit reported an error this app does not know yet."
        }
        return "Activity.request failed (ActivityAuthorizationError.\(error)): \(reason)\n\(error.localizedDescription)"
    }
}

extension LiveActivitySummary {
    init(_ activity: Activity<ToolboxActivityAttributes>) {
        let state = activity.content.state
        self.init(id: activity.id, state: LiveActivityErrors.title(activity.activityState),
                  detail: "\(state.phase.title) · sample \(state.sample)/\(state.totalSamples) · started \(activity.attributes.startedAt.formatted(date: .omitted, time: .standard))")
    }
}
#endif

/// Starts, updates and ends a real Live Activity with ActivityKit. The app updates it itself while it runs
/// (push type nil); updates from a server would need ActivityKit push notifications.
@MainActor
final class LiveActivityExperimentService: ObservableObject {
    @Published var runLength = LiveActivityRunLength.oneMinute
    @Published var dismissal = LiveActivityDismissalChoice.standard
    @Published var autoUpdate = true {
        didSet { if currentID != nil { autoUpdate ? startSampling() : stopSampling() } }
    }

    @Published private(set) var areActivitiesEnabled: Bool?
    @Published private(set) var frequentPushesEnabled: Bool?
    @Published private(set) var activities: [LiveActivitySummary] = []
    @Published private(set) var currentID: String?
    @Published private(set) var sample = 0
    @Published private(set) var totalSamples = 0
    @Published private(set) var stateLog: [String] = []
    @Published private(set) var output = "Start a measurement run: it appears on the Lock Screen and in the Dynamic Island and is updated every \(LiveActivityRunLength.sampleInterval) s while the app runs."
    @Published private(set) var isError = false

    private var samplingTask: Task<Void, Never>?
    private var stateTask: Task<Void, Never>?

    var supportsLiveActivitiesKey: String {
        (Bundle.main.object(forInfoDictionaryKey: "NSSupportsLiveActivities") as? Bool).map { $0 ? "YES" : "NO" } ?? "missing"
    }

    var isSampling: Bool { samplingTask != nil }

    func refresh() {
        #if canImport(ActivityKit) && os(iOS)
        let info = ActivityAuthorizationInfo()
        areActivitiesEnabled = info.areActivitiesEnabled
        frequentPushesEnabled = info.frequentPushesEnabled
        activities = Activity<ToolboxActivityAttributes>.activities.map(LiveActivitySummary.init)
        #endif
    }

    func start() {
        #if canImport(ActivityKit) && os(iOS)
        guard currentID == nil else { return }
        let now = Date()
        let total = runLength.totalSamples
        let attributes = ToolboxActivityAttributes(runName: "Device measurement", symbolName: "gauge.with.dots.needle.33percent",
                                                   startedAt: now, plannedEnd: now.addingTimeInterval(TimeInterval(runLength.rawValue)))
        let content = ActivityContent(state: makeState(sample: 0, total: total, phase: .measuring),
                                      staleDate: now.addingTimeInterval(TimeInterval(LiveActivityRunLength.staleAfter)), relevanceScore: 50)
        do {
            let activity = try Activity.request(attributes: attributes, content: content, pushType: nil)
            currentID = activity.id
            sample = 0
            totalSamples = total
            stateLog = []
            observeState(of: activity)
            if autoUpdate { startSampling() }
            show("Activity.request succeeded: \(activity.id)\nPush type nil: only this app can update it, and only while it runs. \(total) samples over \(runLength.title).", isError: false)
        } catch {
            show(LiveActivityErrors.explain(error), isError: true)
        }
        refresh()
        #else
        show("ActivityKit is only available on iPhone.", isError: true)
        #endif
    }

    /// Takes one real sample and pushes it to the activity; `alert` lights up the screen and expands the Dynamic Island.
    func updateNow(alert: Bool) {
        Task { await takeSample(alert: alert) }
    }

    func end() {
        #if canImport(ActivityKit) && os(iOS)
        guard let id = currentID else { return }
        let final = makeState(sample: sample, total: totalSamples, phase: .finished)
        finishRun()
        let policy = dismissal.policy(endingAt: Date())
        let dismissalTitle = dismissal.title
        Task {
            guard let activity = Self.activity(withID: id) else {
                show("The activity \(id) no longer exists; it was ended or dismissed outside the app.", isError: false)
                refresh()
                return
            }
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: policy)
            show("Ended \(id) after \(final.sample) sample(s). Dismissal policy: \(dismissalTitle).", isError: false)
            refresh()
        }
        #endif
    }

    /// Ends every activity of this app, including ones left over from an earlier launch.
    func endAll() {
        #if canImport(ActivityKit) && os(iOS)
        finishRun()
        Task {
            let running = Activity<ToolboxActivityAttributes>.activities
            let count = running.count
            for activity in running {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            show("Ended \(count) activit\(count == 1 ? "y" : "ies") immediately.", isError: false)
            refresh()
        }
        #endif
    }

    private func takeSample(alert: Bool) async {
        #if canImport(ActivityKit) && os(iOS)
        guard let id = currentID else { return }
        guard let activity = Self.activity(withID: id) else {
            finishRun()
            show("The activity \(id) was ended or dismissed outside the app.", isError: false)
            refresh()
            return
        }
        sample += 1
        if sample >= totalSamples {
            let final = makeState(sample: totalSamples, total: totalSamples, phase: .finished)
            finishRun()
            await activity.end(ActivityContent(state: final, staleDate: nil), dismissalPolicy: dismissal.policy(endingAt: Date()))
            show("Run finished after \(totalSamples) samples; the activity was ended with its final reading.", isError: false)
        } else {
            let state = makeState(sample: sample, total: totalSamples, phase: .measuring)
            let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(TimeInterval(LiveActivityRunLength.staleAfter)), relevanceScore: 50)
            let configuration = alert ? AlertConfiguration(title: "Sample \(state.sample) of \(state.totalSamples)", body: "\(state.reading)", sound: .default) : nil
            await activity.update(content, alertConfiguration: configuration)
            show("Update \(state.sample)/\(state.totalSamples)\(alert ? " with alert" : ""): \(state.reading) · \(state.detail)", isError: false)
        }
        refresh()
        #endif
    }

    private func startSampling() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(LiveActivityRunLength.sampleInterval))
                guard !Task.isCancelled, let self else { return }
                await self.takeSample(alert: false)
            }
        }
    }

    private func stopSampling() {
        samplingTask?.cancel()
        samplingTask = nil
    }

    /// Ends the app's side of a run: no more samples and no battery monitoring (makeState turns it on).
    private func finishRun() {
        stopSampling()
        currentID = nil
        #if canImport(ActivityKit) && os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }

    #if canImport(ActivityKit) && os(iOS)
    /// Looked up outside the main actor so the non-Sendable activity stays in its own region and can be
    /// handed to ActivityKit's update and end calls.
    nonisolated private static func activity(withID id: String) -> Activity<ToolboxActivityAttributes>? {
        Activity<ToolboxActivityAttributes>.activities.first { $0.id == id }
    }

    private func observeState(of activity: Activity<ToolboxActivityAttributes>) {
        let updates = activity.activityStateUpdates
        stateTask?.cancel()
        stateTask = Task { [weak self] in
            for await state in updates {
                guard let self else { return }
                self.stateLog.insert("\(Date().formatted(date: .omitted, time: .standard))  \(LiveActivityErrors.title(state))", at: 0)
                if state == .dismissed || state == .ended {
                    self.refresh()
                    // The activity is over: stop observing it (a cancelled task was already replaced, so leave stateTask alone).
                    if !Task.isCancelled { self.stateTask = nil }
                    return
                }
            }
        }
    }

    private func makeState(sample: Int, total: Int, phase: ToolboxActivityAttributes.ContentState.Phase) -> ToolboxActivityAttributes.ContentState {
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let batteryState = switch device.batteryState {
        case .charging: "charging"
        case .full: "full"
        case .unplugged: "on battery"
        default: "state unknown"
        }
        let info = ProcessInfo.processInfo
        return ToolboxActivityAttributes.ContentState(
            phase: phase, sample: sample, totalSamples: total,
            reading: LiveActivityReading.battery(level: device.batteryLevel, state: batteryState),
            detail: "\(LiveActivityReading.thermal(info.thermalState)) · Low Power \(info.isLowPowerModeEnabled ? "on" : "off")",
            updatedAt: Date())
    }
    #endif

    var isActive: Bool { currentID != nil || samplingTask != nil || stateTask != nil }

    /// Leaving the experiment ends the run it started (the ended activity follows the chosen dismissal policy), stops
    /// observing its state and turns battery monitoring off.
    func stop() {
        end()
        finishRun()
        stateTask?.cancel()
        stateTask = nil
    }

    private func show(_ text: String, isError: Bool) {
        output = text
        self.isError = isError
    }
}

extension ExperimentAvailability {
    /// `areActivitiesEnabled` is false when the person turned Live Activities off for the app or the device lacks support.
    static func liveActivities() -> ExperimentStatus {
        #if canImport(ActivityKit) && os(iOS)
        ActivityAuthorizationInfo().areActivitiesEnabled ? .available : .permissionDenied
        #else
        .platformUnsupported
        #endif
    }
}
