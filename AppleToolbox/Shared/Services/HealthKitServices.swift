import Foundation
import Combine

#if canImport(HealthKit) && (os(iOS) || os(watchOS))
import HealthKit
#endif

// MARK: Choices and value types

/// Picker-driven sets of Health data types the reader asks for and reads together (spec §24).
nonisolated enum HealthReaderPreset: String, CaseIterable, Identifiable, Sendable {
    case activity, heart, sleep, workouts, respiratory, mobility, environmental

    var id: String { rawValue }
    var title: String {
        switch self {
        case .activity: "Activity"
        case .heart: "Heart"
        case .sleep: "Sleep"
        case .workouts: "Workouts"
        case .respiratory: "Respiratory"
        case .mobility: "Mobility"
        case .environmental: "Environment & audio exposure"
        }
    }
}

/// `HKUpdateFrequency` for background delivery.
nonisolated enum HealthDeliveryFrequency: String, CaseIterable, Identifiable, Sendable {
    case immediate, hourly, daily, weekly

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

nonisolated struct HealthTypeOption: Identifiable, Hashable, Sendable {
    /// The HealthKit type identifier, e.g. HKQuantityTypeIdentifierStepCount.
    let id: String
    let title: String
}

nonisolated struct HealthReaderRow: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let value: String
    let detail: String
}

nonisolated struct HealthReaderGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let rows: [HealthReaderRow]
    let note: String?
}

nonisolated struct HealthBoundaryRow: Identifiable, Equatable, Sendable {
    let title: String
    let value: String
    var id: String { title }
}

/// How a quantity is shown: HealthKit unit converted, scaled (fractions to percent) and labelled.
nonisolated struct HealthUnitDisplay: Equatable, Sendable {
    let label: String
    var scale = 1.0
    var fractionDigits = 0
}

nonisolated enum HealthReaderError: LocalizedError {
    case noResults

    var errorDescription: String? { "HealthKit returned neither results nor an error." }
}

// MARK: Pure formatting

nonisolated enum HealthReaderFormat {
    /// "HKQuantityTypeIdentifierHeartRateVariabilitySDNN" → "Heart Rate Variability SDNN".
    static func typeName(_ identifier: String) -> String {
        var name = identifier
        for prefix in ["HKQuantityTypeIdentifier", "HKCategoryTypeIdentifier", "HKCorrelationTypeIdentifier", "HKDataTypeIdentifier", "HKWorkoutTypeIdentifier"] where name.hasPrefix(prefix) {
            name.removeFirst(prefix.count)
            break
        }
        if name.isEmpty { return identifier == "HKWorkoutTypeIdentifier" ? "Workouts" : identifier }
        let characters = Array(name)
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let startsWord = character.isUppercase && previous.map { $0.isLowercase || $0.isNumber || (next?.isLowercase ?? false) } == true
            if startsWord, !current.isEmpty { words.append(current); current = "" }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        return words.joined(separator: " ")
    }

    /// `HKCategoryValueSleepAnalysis` raw values.
    static func sleepStageName(_ rawValue: Int) -> String {
        switch rawValue {
        case 0: "In bed"
        case 1: "Asleep (unspecified)"
        case 2: "Awake"
        case 3: "Core"
        case 4: "Deep"
        case 5: "REM"
        default: "Sleep value \(rawValue)"
        }
    }

    /// Adds up the seconds per sleep stage, in stage order. Overlapping samples from several sources add up too.
    static func sleepTotals(_ segments: [(stage: Int, seconds: TimeInterval)]) -> [(stage: Int, seconds: TimeInterval)] {
        var totals: [Int: TimeInterval] = [:]
        for segment in segments { totals[segment.stage, default: 0] += max(0, segment.seconds) }
        return totals.keys.sorted().map { ($0, totals[$0] ?? 0) }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let units: Set<Duration.UnitsFormatStyle.Unit> = seconds < 60 ? [.seconds] : [.hours, .minutes]
        return Duration.seconds(seconds.rounded()).formatted(.units(allowed: units, width: .abbreviated))
    }

    static func value(_ raw: Double, display: HealthUnitDisplay) -> String {
        let number = (raw * display.scale).formatted(.number.precision(.fractionLength(0...display.fractionDigits)))
        return display.label.isEmpty ? number : "\(number) \(display.label)"
    }

    /// `HKError.Code` raw values from HKDefines.h.
    static func errorName(_ code: Int) -> String {
        switch code {
        case 1: "errorHealthDataUnavailable"
        case 2: "errorHealthDataRestricted"
        case 3: "errorInvalidArgument"
        case 4: "errorAuthorizationDenied"
        case 5: "errorAuthorizationNotDetermined"
        case 6: "errorDatabaseInaccessible (device locked)"
        case 7: "errorUserCanceled"
        case 8: "errorAnotherWorkoutSessionStarted"
        case 9: "errorUserExitedWorkoutSession"
        case 10: "errorRequiredAuthorizationDenied"
        case 11: "errorNoData"
        case 12: "errorWorkoutActivityNotAllowed"
        case 13: "errorDataSizeExceeded"
        case 14: "errorBackgroundWorkoutSessionNotAllowed"
        case 15: "errorNotPermissibleForGuestUserMode"
        default: "unrecognized code"
        }
    }

    static func errorText(_ error: any Error) -> String {
        let error = error as NSError
        if error.domain == "com.apple.healthkit" {
            return "HKError \(error.code) (\(errorName(error.code))): \(error.localizedDescription)"
        }
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}

// MARK: HealthKit catalog

#if canImport(HealthKit) && (os(iOS) || os(watchOS))
nonisolated extension HealthReaderPreset {
    var quantityTypes: [HKQuantityTypeIdentifier] {
        switch self {
        case .activity: [.stepCount, .distanceWalkingRunning, .activeEnergyBurned, .basalEnergyBurned, .flightsClimbed, .appleExerciseTime, .appleStandTime]
        case .heart: [.heartRate, .restingHeartRate, .walkingHeartRateAverage, .heartRateVariabilitySDNN, .heartRateRecoveryOneMinute, .vo2Max]
        case .sleep: [.appleSleepingWristTemperature]
        case .workouts: [.activeEnergyBurned, .distanceWalkingRunning, .distanceCycling, .distanceSwimming, .heartRate]
        case .respiratory: [.respiratoryRate, .oxygenSaturation, .appleSleepingBreathingDisturbances]
        case .mobility: [.walkingSpeed, .walkingStepLength, .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage, .stairAscentSpeed, .stairDescentSpeed, .sixMinuteWalkTestDistance, .appleWalkingSteadiness]
        case .environmental: [.environmentalAudioExposure, .headphoneAudioExposure, .environmentalSoundReduction, .timeInDaylight, .uvExposure]
        }
    }

    var categoryTypes: [HKCategoryTypeIdentifier] {
        switch self {
        case .heart: [.highHeartRateEvent, .lowHeartRateEvent, .irregularHeartRhythmEvent]
        case .sleep: [.sleepAnalysis]
        case .environmental: [.environmentalAudioExposureEvent, .headphoneAudioExposureEvent]
        default: []
        }
    }

    /// The types the authorization request asks to read.
    var sampleTypes: [HKSampleType] {
        let workouts: [HKSampleType] = self == .workouts ? [HKWorkoutType.workoutType()] : []
        return workouts + categoryTypes.map { HKCategoryType($0) } + quantityTypes.map { HKQuantityType($0) }
    }
}

nonisolated extension HealthDeliveryFrequency {
    var updateFrequency: HKUpdateFrequency {
        switch self {
        case .immediate: .immediate
        case .hourly: .hourly
        case .daily: .daily
        case .weekly: .weekly
        }
    }
}

nonisolated enum HealthReaderCatalog {
    /// The unit a quantity is converted to, and how it is shown.
    static func unit(for identifier: HKQuantityTypeIdentifier) -> (unit: HKUnit, display: HealthUnitDisplay)? {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        let metersPerSecond = HKUnit.meter().unitDivided(by: .second())
        switch identifier {
        case .stepCount: return (.count(), HealthUnitDisplay(label: "steps"))
        case .flightsClimbed: return (.count(), HealthUnitDisplay(label: "floors"))
        case .uvExposure: return (.count(), HealthUnitDisplay(label: "UV index", fractionDigits: 1))
        case .appleSleepingBreathingDisturbances: return (.count(), HealthUnitDisplay(label: "disturbances", fractionDigits: 1))
        case .distanceWalkingRunning, .distanceCycling, .distanceSwimming:
            return (.meterUnit(with: .kilo), HealthUnitDisplay(label: "km", fractionDigits: 2))
        case .sixMinuteWalkTestDistance: return (.meter(), HealthUnitDisplay(label: "m"))
        case .activeEnergyBurned, .basalEnergyBurned: return (.kilocalorie(), HealthUnitDisplay(label: "kcal"))
        case .appleExerciseTime, .appleStandTime, .timeInDaylight: return (.minute(), HealthUnitDisplay(label: "min"))
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage, .heartRateRecoveryOneMinute: return (perMinute, HealthUnitDisplay(label: "bpm"))
        case .respiratoryRate: return (perMinute, HealthUnitDisplay(label: "breaths/min", fractionDigits: 1))
        case .heartRateVariabilitySDNN: return (.secondUnit(with: .milli), HealthUnitDisplay(label: "ms"))
        case .vo2Max:
            return (HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute())), HealthUnitDisplay(label: "ml/(kg·min)", fractionDigits: 1))
        case .oxygenSaturation, .walkingAsymmetryPercentage, .walkingDoubleSupportPercentage, .appleWalkingSteadiness:
            return (.percent(), HealthUnitDisplay(label: "%", scale: 100, fractionDigits: 1))
        case .walkingSpeed, .stairAscentSpeed, .stairDescentSpeed: return (metersPerSecond, HealthUnitDisplay(label: "m/s", fractionDigits: 2))
        case .walkingStepLength: return (.meterUnit(with: .centi), HealthUnitDisplay(label: "cm"))
        case .environmentalAudioExposure, .headphoneAudioExposure, .environmentalSoundReduction:
            return (.decibelAWeightedSoundPressureLevel(), HealthUnitDisplay(label: "dB"))
        case .appleSleepingWristTemperature: return (.degreeCelsius(), HealthUnitDisplay(label: "°C", fractionDigits: 2))
        default: return nil
        }
    }

    static func quantityText(_ quantity: HKQuantity, identifier: HKQuantityTypeIdentifier) -> String {
        guard let match = unit(for: identifier), quantity.is(compatibleWith: match.unit) else { return quantity.description }
        return HealthReaderFormat.value(quantity.doubleValue(for: match.unit), display: match.display)
    }

    static func activityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .functionalStrengthTraining: "Functional strength training"
        case .traditionalStrengthTraining: "Traditional strength training"
        case .highIntensityIntervalTraining: "High-intensity interval training"
        case .coreTraining: "Core training"
        case .mixedCardio: "Mixed cardio"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing: "Stair climbing"
        case .pilates: "Pilates"
        case .cardioDance: "Cardio dance"
        case .socialDance: "Social dance"
        case .cooldown: "Cooldown"
        case .mindAndBody: "Mind and body"
        case .soccer: "Soccer"
        case .tennis: "Tennis"
        case .basketball: "Basketball"
        case .swimBikeRun: "Multisport (swim, bike, run)"
        case .wheelchairWalkPace: "Wheelchair walk pace"
        case .wheelchairRunPace: "Wheelchair run pace"
        case .other: "Other"
        default: "Activity type \(type.rawValue)"
        }
    }

    /// Value names of the category types the reader shows.
    static func categoryValueName(_ value: Int, identifier: HKCategoryTypeIdentifier) -> String {
        switch identifier {
        case .sleepAnalysis: HealthReaderFormat.sleepStageName(value)
        case .environmentalAudioExposureEvent: value == HKCategoryValueEnvironmentalAudioExposureEvent.momentaryLimit.rawValue ? "Momentary limit" : "Event \(value)"
        case .headphoneAudioExposureEvent: value == HKCategoryValueHeadphoneAudioExposureEvent.sevenDayLimit.rawValue ? "7-day limit" : "Event \(value)"
        default: value == HKCategoryValue.notApplicable.rawValue ? "Event" : "Value \(value)"
        }
    }
}
#endif

// MARK: HealthKit Reader

/// HealthKit Reader (spec §24). HealthKit runs query handlers and completions on its own queues, so every handler is a
/// `@Sendable` closure that hands Sendable results back to the main actor. Read authorization is reported as
/// "requested", never "granted": HealthKit does not tell apps whether reading was allowed.
@MainActor
final class HealthKitReaderService: ObservableObject {
    @Published var preset: HealthReaderPreset = .activity {
        didSet {
            guard preset != oldValue else { return }
            groups = []
            if !isObserving { observedTypeID = typeOptions.first?.id ?? "" }
            checkRequestStatus()
        }
    }
    @Published var observedTypeID = ""
    @Published var frequency: HealthDeliveryFrequency = .hourly
    @Published private(set) var output: String
    @Published private(set) var isError = false
    @Published private(set) var requestStatus = "Not checked yet"
    @Published private(set) var isRequesting = false
    @Published private(set) var isReading = false
    @Published private(set) var groups: [HealthReaderGroup] = []
    @Published private(set) var isObserving = false
    @Published private(set) var observerState = "Not running"
    @Published private(set) var deliveryState = "Not enabled"
    @Published private(set) var newestObservedSample: String?

    /// com.apple.developer.healthkit.background-delivery in the embedded provisioning profile.
    let backgroundDeliveryEntitlement: String
    let healthRecordsRows: [HealthBoundaryRow]

    #if canImport(HealthKit) && (os(iOS) || os(watchOS))
    private let store = HKHealthStore()
    private var observerQuery: HKObserverQuery?
    private var deliveryType: HKSampleType?
    private var observerUpdates = 0
    #endif

    private static let emptyNote = "No samples. Either there is no data in this period or reading this type was not allowed; HealthKit does not tell apps which."

    init(initialOutput: String = "Pick a data set, request read access, then read recent samples.") {
        output = initialOutput
        backgroundDeliveryEntitlement = Self.entitlementState("com.apple.developer.healthkit.background-delivery")
        healthRecordsRows = Self.healthRecordsBoundary()
        observedTypeID = typeOptions.first?.id ?? ""
    }

    var typeOptions: [HealthTypeOption] {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        preset.sampleTypes.map { HealthTypeOption(id: $0.identifier, title: HealthReaderFormat.typeName($0.identifier)) }
        #else
        []
        #endif
    }

    private func report(_ text: String, isError: Bool = false) {
        output = text
        self.isError = isError
    }

    // MARK: Authorization

    func requestAuthorization() {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        guard HKHealthStore.isHealthDataAvailable() else { report("Health data is not available on this device.", isError: true); return }
        let types = Set<HKObjectType>(preset.sampleTypes)
        let count = types.count
        let title = preset.title
        isRequesting = true
        report("Asking to read \(count) \(title) type(s)…")
        store.requestAuthorization(toShare: [], read: types) { @Sendable [weak self] success, error in
            let failure = error.map(HealthReaderFormat.errorText)
            Task { @MainActor in self?.finishRequest(success: success, failure: failure, count: count, title: title) }
        }
        #else
        report("HealthKit is not available on this platform.", isError: true)
        #endif
    }

    private func finishRequest(success: Bool, failure: String?, count: Int, title: String) {
        isRequesting = false
        // Same semantics as before: "granted" records that the request completed, not what the person allowed.
        if success { PermissionProbe.remember(.granted, for: .healthKit) }
        PermissionCenter.shared.invalidate()
        if let failure {
            report("HealthKit authorization error: \(failure)", isError: true)
        } else if success {
            report("Read access requested for \(count) \(title) type(s). HealthKit never tells an app whether reading was allowed: types you declined return no samples, exactly like types without data.")
        } else {
            report("The authorization request did not complete.", isError: true)
        }
        checkRequestStatus()
    }

    /// Whether HealthKit would show its sheet for the current set; it never reveals the choices made in it.
    func checkRequestStatus() {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        guard HKHealthStore.isHealthDataAvailable() else { requestStatus = "Health data unavailable on this device"; return }
        store.getRequestStatusForAuthorization(toShare: [], read: Set<HKObjectType>(preset.sampleTypes)) { @Sendable [weak self] status, error in
            let failure = error.map(HealthReaderFormat.errorText)
            Task { @MainActor in self?.applyRequestStatus(status, failure: failure) }
        }
        #else
        requestStatus = "HealthKit is not available on this platform"
        #endif
    }

    #if canImport(HealthKit) && (os(iOS) || os(watchOS))
    private func applyRequestStatus(_ status: HKAuthorizationRequestStatus, failure: String?) {
        if let failure { requestStatus = "Error: \(failure)"; return }
        requestStatus = switch status {
        case .shouldRequest: "Not requested yet: the Health sheet appears on request"
        case .unnecessary: "Requested before: the choices stay private to the person"
        case .unknown: "Unknown"
        @unknown default: "Unknown (\(status.rawValue))"
        }
    }
    #endif

    // MARK: Reading

    func readRecent() {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        guard !isReading else { return }
        guard HKHealthStore.isHealthDataAvailable() else { report("Health data is not available on this device.", isError: true); return }
        let preset = self.preset
        isReading = true
        report("Reading \(preset.title)…")
        Task {
            var groups: [HealthReaderGroup] = []
            var failures: [String] = []
            let now = Date()
            func attempt(_ label: String, _ work: () async throws -> [HealthReaderGroup]) async {
                do { groups += try await work() } catch { failures.append("\(label): \(HealthReaderFormat.errorText(error))") }
            }
            switch preset {
            case .activity: await attempt("Daily steps") { [try await dailySteps(now: now)] }
            case .sleep: await attempt("Sleep analysis") { try await lastNight() }
            case .workouts: await attempt("Workouts") { [try await workouts()] }
            default: break
            }
            let categories = preset.categoryTypes.filter { $0 != .sleepAnalysis }
            for identifier in categories {
                await attempt(HealthReaderFormat.typeName(identifier.rawValue)) { [try await recentGroup(HKCategoryType(identifier), limit: 5, now: now)] }
            }
            // Workouts read these types only for their per-workout statistics.
            let quantities = preset == .workouts ? [] : preset.quantityTypes
            for identifier in quantities {
                await attempt(HealthReaderFormat.typeName(identifier.rawValue)) { [try await recentGroup(HKQuantityType(identifier), limit: identifier == .heartRate ? 10 : 5, now: now)] }
            }
            self.groups = groups
            isReading = false
            let rows = groups.reduce(0) { $0 + $1.rows.count }
            if failures.isEmpty {
                report("Read \(rows) row(s) in \(groups.count) group(s) for \(preset.title). Empty groups mean no data or no read access; HealthKit does not tell which.")
            } else {
                report("Read \(rows) row(s) with \(failures.count) error(s):\n" + failures.joined(separator: "\n"), isError: true)
            }
        }
        #else
        report("HealthKit is not available on this platform.", isError: true)
        #endif
    }

    #if canImport(HealthKit) && (os(iOS) || os(watchOS))
    /// HKSampleQuery wrapped in a continuation; the results handler runs on a HealthKit queue.
    private func samples(_ type: HKSampleType, predicate: NSPredicate?, limit: Int, ascending: Bool = false) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: ascending ? HKSampleSortIdentifierStartDate : HKSampleSortIdentifierEndDate, ascending: ascending)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [sort]) { @Sendable _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    /// Daily step totals for the last seven days with HKStatisticsCollectionQuery (cumulative sum, one-day buckets).
    private func dailySteps(now: Date) async throws -> HealthReaderGroup {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let collection: HKStatisticsCollection = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum,
                                                    anchorDate: today, intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { @Sendable _, collection, error in
                if let collection { continuation.resume(returning: collection) } else { continuation.resume(throwing: error ?? HealthReaderError.noResults) }
            }
            store.execute(query)
        }
        var total = 0.0
        let rows = (0..<7).reversed().compactMap { offset -> HealthReaderRow? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let steps = collection.statistics(for: day)?.sumQuantity()?.doubleValue(for: .count())
            total += steps ?? 0
            return HealthReaderRow(title: day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)),
                                   value: steps.map { HealthReaderFormat.value($0, display: HealthUnitDisplay(label: "steps")) } ?? "no data",
                                   detail: offset == 0 ? "today so far" : "")
        }
        return HealthReaderGroup(id: "daily-steps", title: "Daily steps · HKStatisticsCollectionQuery", rows: rows,
                                 note: total == 0 ? Self.emptyNote : "Sums merge every source (iPhone and Apple Watch) without double counting.")
    }

    /// The most recent samples of one type in the last 30 days.
    private func recentGroup(_ type: HKSampleType, limit: Int, now: Date) async throws -> HealthReaderGroup {
        let predicate = HKQuery.predicateForSamples(withStart: now.addingTimeInterval(-30 * 86_400), end: nil, options: [])
        let rows = try await samples(type, predicate: predicate, limit: limit).map(row)
        return HealthReaderGroup(id: type.identifier, title: HealthReaderFormat.typeName(type.identifier), rows: rows, note: rows.isEmpty ? Self.emptyNote : nil)
    }

    private func workouts() async throws -> HealthReaderGroup {
        let rows = try await samples(HKWorkoutType.workoutType(), predicate: nil, limit: 10).map(row)
        return HealthReaderGroup(id: "workouts", title: "Workouts (latest 10)", rows: rows, note: rows.isEmpty ? Self.emptyNote : nil)
    }

    /// The stages of the most recently recorded night: the 18 hours before the newest sleep sample ended.
    private func lastNight() async throws -> [HealthReaderGroup] {
        let type = HKCategoryType(.sleepAnalysis)
        guard let newest = try await samples(type, predicate: nil, limit: 1).first else {
            return [HealthReaderGroup(id: "sleep", title: "Sleep", rows: [], note: Self.emptyNote)]
        }
        let predicate = HKQuery.predicateForSamples(withStart: newest.endDate.addingTimeInterval(-18 * 3600), end: newest.endDate, options: [])
        let night = try await samples(type, predicate: predicate, limit: 500, ascending: true).compactMap { $0 as? HKCategorySample }
        let totals = HealthReaderFormat.sleepTotals(night.map { ($0.value, $0.endDate.timeIntervalSince($0.startDate)) }).map {
            HealthReaderRow(title: HealthReaderFormat.sleepStageName($0.stage), value: HealthReaderFormat.duration($0.seconds), detail: "")
        }
        return [
            HealthReaderGroup(id: "sleep-totals", title: "Sleep stages · night ending \(newest.endDate.formatted(date: .abbreviated, time: .shortened))", rows: totals,
                              note: "Totals add up every source; if iPhone and Apple Watch both recorded the night, overlapping time counts twice."),
            HealthReaderGroup(id: "sleep-samples", title: "Sleep samples (\(night.count))", rows: night.map(row), note: nil),
        ]
    }

    private func row(_ sample: HKSample) -> HealthReaderRow {
        let source = sample.sourceRevision.source.name
        let time = timeRange(sample)
        switch sample {
        case let workout as HKWorkout:
            var parts = [HealthReaderFormat.duration(workout.duration)]
            if let energy = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                parts.append(HealthReaderCatalog.quantityText(energy, identifier: .activeEnergyBurned))
            }
            let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
            for identifier in distanceTypes {
                guard let distance = workout.statistics(for: HKQuantityType(identifier))?.sumQuantity() else { continue }
                parts.append(HealthReaderCatalog.quantityText(distance, identifier: identifier))
                break
            }
            if let heartRate = workout.statistics(for: HKQuantityType(.heartRate))?.averageQuantity() {
                parts.append("avg " + HealthReaderCatalog.quantityText(heartRate, identifier: .heartRate))
            }
            return HealthReaderRow(title: HealthReaderCatalog.activityName(workout.workoutActivityType), value: parts.joined(separator: " · "), detail: "\(time) · \(source)")
        case let quantity as HKQuantitySample:
            let identifier = HKQuantityTypeIdentifier(rawValue: quantity.quantityType.identifier)
            let count = quantity.count > 1 ? " · \(quantity.count) values" : ""
            return HealthReaderRow(title: time, value: HealthReaderCatalog.quantityText(quantity.quantity, identifier: identifier), detail: source + count)
        case let category as HKCategorySample:
            let identifier = HKCategoryTypeIdentifier(rawValue: category.categoryType.identifier)
            let seconds = category.endDate.timeIntervalSince(category.startDate)
            var detail = [time, source]
            if let threshold = category.metadata?[HKMetadataKeyHeartRateEventThreshold] as? HKQuantity {
                detail.append("threshold " + HealthReaderCatalog.quantityText(threshold, identifier: .heartRate))
            }
            if let level = category.metadata?[HKMetadataKeyAudioExposureLevel] as? HKQuantity {
                detail.append("level " + HealthReaderCatalog.quantityText(level, identifier: .environmentalAudioExposure))
            }
            let value = HealthReaderCatalog.categoryValueName(category.value, identifier: identifier)
            return HealthReaderRow(title: value, value: seconds > 0 ? HealthReaderFormat.duration(seconds) : "", detail: detail.joined(separator: " · "))
        default:
            return HealthReaderRow(title: time, value: HealthReaderFormat.typeName(sample.sampleType.identifier), detail: source)
        }
    }

    private func timeRange(_ sample: HKSample) -> String {
        let start = sample.startDate.formatted(date: .abbreviated, time: .shortened)
        guard sample.endDate.timeIntervalSince(sample.startDate) >= 60 else { return start }
        return "\(start)–\(sample.endDate.formatted(date: .omitted, time: .shortened))"
    }
    #endif

    // MARK: Observer query and background delivery

    /// Starts an HKObserverQuery for the chosen type and enables background delivery for it.
    func startObserving() {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        guard !isObserving, let type = preset.sampleTypes.first(where: { $0.identifier == observedTypeID }) else { return }
        guard HKHealthStore.isHealthDataAvailable() else { report("Health data is not available on this device.", isError: true); return }
        let name = HealthReaderFormat.typeName(type.identifier)
        let query = HKObserverQuery(sampleType: type, predicate: nil) { @Sendable [weak self] _, completionHandler, error in
            // HealthKit waits for this call before it delivers the next update (and backs off if it never comes).
            completionHandler()
            let failure = error.map(HealthReaderFormat.errorText)
            Task { @MainActor in self?.observerFired(failure: failure) }
        }
        store.execute(query)
        observerQuery = query
        deliveryType = type
        observerUpdates = 0
        newestObservedSample = nil
        isObserving = true
        observerState = "Running for \(name) since \(Date().formatted(date: .omitted, time: .standard))"
        deliveryState = "Enabling (\(frequency.title))…"
        let frequency = frequency
        store.enableBackgroundDelivery(for: type, frequency: frequency.updateFrequency) { @Sendable [weak self] success, error in
            let failure = error.map(HealthReaderFormat.errorText)
            Task { @MainActor in self?.finishEnablingDelivery(success: success, failure: failure, frequency: frequency) }
        }
        report("Observer query started for \(name). Add or change \(name) data in the Health app to see updates arrive.")
        #else
        report("HealthKit is not available on this platform.", isError: true)
        #endif
    }

    private func finishEnablingDelivery(success: Bool, failure: String?, frequency: HealthDeliveryFrequency) {
        guard isObserving else { return }
        if let failure {
            deliveryState = "Failed: \(failure)"
            report("Background delivery was refused: \(failure)\nIt needs the com.apple.developer.healthkit.background-delivery entitlement (\(backgroundDeliveryEntitlement.lowercased())).", isError: true)
        } else {
            deliveryState = success ? "Enabled · \(frequency.title) (cumulative types such as steps deliver at most hourly)" : "Not enabled"
        }
    }

    private func observerFired(failure: String?) {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        guard isObserving, let type = deliveryType else { return }
        if let failure { observerState = "Observer error: \(failure)"; return }
        observerUpdates += 1
        observerState = "\(observerUpdates) update(s) · last \(Date().formatted(date: .omitted, time: .standard))"
        Task {
            guard let newest = try? await samples(type, predicate: nil, limit: 1).first else {
                newestObservedSample = "None readable (no data or no read access)"
                return
            }
            let summary = row(newest)
            newestObservedSample = [summary.title, summary.value].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        #endif
    }

    /// Stops the observer query and disables background delivery for its type again.
    func stopObserving() {
        #if canImport(HealthKit) && (os(iOS) || os(watchOS))
        if let observerQuery { store.stop(observerQuery) }
        if let deliveryType {
            store.disableBackgroundDelivery(for: deliveryType) { @Sendable [weak self] success, error in
                let failure = error.map(HealthReaderFormat.errorText)
                Task { @MainActor in
                    guard let self, !self.isObserving else { return }
                    self.deliveryState = failure.map { "Disabling failed: \($0)" } ?? (success ? "Disabled again" : "Not disabled")
                }
            }
        }
        observerQuery = nil
        deliveryType = nil
        isObserving = false
        observerState = "Stopped after \(observerUpdates) update(s)"
        #endif
    }

    // MARK: Boundaries

    private static func entitlementState(_ key: String, requiring value: String? = nil) -> String {
        switch ProvisioningInspector.load() {
        case .found(let profile):
            guard let rendered = profile.entitlements[key] else { return "Not provisioned" }
            if let value, !rendered.contains(value) { return "Not provisioned (\(rendered))" }
            return "Provisioned (\(rendered))"
        case .missing(let reason), .unreadable(let reason):
            return "Unknown: \(reason)"
        }
    }

    /// Clinical records need `health-records` in com.apple.developer.healthkit.access and
    /// NSHealthClinicalHealthRecordsShareUsageDescription; this build has neither, so no request is sent.
    private static func healthRecordsBoundary() -> [HealthBoundaryRow] {
        #if canImport(HealthKit) && os(iOS)
        let support = HKHealthStore().supportsHealthRecords() ? "Supported on this device" : "Not supported on this device or in this region"
        #elseif canImport(HealthKit) && os(watchOS)
        let support = "Not on watchOS (supportsHealthRecords() is iOS-only)"
        #else
        let support = "HealthKit is not available on this platform"
        #endif
        let usage = Bundle.main.object(forInfoDictionaryKey: "NSHealthClinicalHealthRecordsShareUsageDescription") == nil ? "Not declared" : "Declared"
        return [
            HealthBoundaryRow(title: "Health Records support", value: support),
            HealthBoundaryRow(title: "health-records access", value: entitlementState("com.apple.developer.healthkit.access", requiring: "health-records")),
            HealthBoundaryRow(title: "Clinical usage description", value: usage),
            HealthBoundaryRow(title: "Clinical request", value: "Not sent by Apple Toolbox"),
        ]
    }
}

#if !os(watchOS)
/// A running observer query (and the background delivery it enabled) is the live session.
extension HealthKitReaderService: StoppableExperiment {
    var isActive: Bool { isObserving }
    func stop() { stopObserving() }
}
#endif
