import Foundation
import Combine
#if canImport(CoreMotion)
import CoreMotion
#endif

struct MotionVector: Equatable {
    var x: Double = 0
    var y: Double = 0
    var z: Double = 0

    var formattedValues: String {
        [x, y, z].map { $0.formatted(.number.precision(.fractionLength(3))) }.joined(separator: "  ·  ")
    }
}

struct MotionFeature: Identifiable {
    let title: String
    let isAvailable: Bool
    let detail: String
    var id: String { title }
}

struct PedometerReading: Equatable {
    var steps = "—"
    var distance = "—"
    var floors = "—"
    var cadence = "—"
    var pace = "—"
    var today = "—"
}

struct AltitudeReading: Equatable {
    var relative = "—"
    var pressure = "—"
    var absolute = "—"
    var absoluteAccuracy = "—"
}

@MainActor
final class MotionExperimentService: ObservableObject {
    @Published private(set) var output = "Ready to start motion updates."
    @Published private(set) var isRunning = false
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var userAcceleration = MotionVector()
    @Published private(set) var rotationRate = MotionVector()
    @Published private(set) var gravity = MotionVector()
    /// Roll, pitch and yaw in degrees.
    @Published private(set) var attitude = MotionVector()
    /// Magnetic field in microtesla.
    @Published private(set) var magneticField = MotionVector()
    @Published private(set) var magneticSource = "Not started"
    @Published private(set) var magneticAccuracy = "—"
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isPedometerRunning = false
    @Published private(set) var pedometerReading = PedometerReading()
    @Published private(set) var isAltimeterRunning = false
    @Published private(set) var altitudeReading = AltitudeReading()
    #if os(iOS) || os(watchOS)
    private let manager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private var permissionRefreshed = false
    #endif

    init() {
        #if os(iOS) || os(watchOS)
        status = manager.isDeviceMotionAvailable ? .available : .hardwareUnsupported
        #else
        status = .platformUnsupported
        #endif
    }

    /// What this device offers, read without starting any sensor or prompting.
    var features: [MotionFeature] {
        #if os(iOS) || os(watchOS)
        let frame = Self.magneticFrame()
        let access = PermissionProbe.motionActivity()
        let permission = switch access {
        case .granted: "Granted"
        case .notDetermined, .unknown: "Asked when the pedometer or altimeter starts"
        case .denied: "Denied"
        case .restricted: "Restricted"
        }
        return [
            Self.feature("Device motion", manager.isDeviceMotionAvailable),
            MotionFeature(title: "Magnetic reference frame", isAvailable: frame != nil, detail: frame.map(Self.frameName) ?? "None · no magnetometer fusion"),
            Self.feature("Magnetometer", manager.isMagnetometerAvailable),
            Self.feature("Step counting", CMPedometer.isStepCountingAvailable()),
            Self.feature("Distance", CMPedometer.isDistanceAvailable()),
            Self.feature("Floor counting", CMPedometer.isFloorCountingAvailable()),
            Self.feature("Cadence", CMPedometer.isCadenceAvailable()),
            Self.feature("Pace", CMPedometer.isPaceAvailable()),
            Self.feature("Relative altitude (barometer)", CMAltimeter.isRelativeAltitudeAvailable()),
            Self.feature("Absolute altitude", CMAltimeter.isAbsoluteAltitudeAvailable()),
            MotionFeature(title: "Motion & Fitness access", isAvailable: access == .granted, detail: permission),
        ]
        #else
        return [MotionFeature(title: "Core Motion sensors", isAvailable: false, detail: "Not available on this platform")]
        #endif
    }

    // MARK: Device motion, attitude and magnetic field

    func startMotion() {
        #if os(iOS) || os(watchOS)
        let frame = Self.magneticFrame()
        let rawMagnetometer = frame == nil && manager.isMagnetometerAvailable
        guard manager.isDeviceMotionAvailable || rawMagnetometer else {
            output = "Device Motion is not available on this device or in the Simulator."
            return
        }
        isRunning = true
        output = "Waiting for the first motion sample…"
        if manager.isDeviceMotionAvailable {
            manager.deviceMotionUpdateInterval = 0.1
            manager.startDeviceMotionUpdates(using: frame ?? .xArbitraryZVertical, to: .main) { [weak self] motion, error in
                guard let self else { return }
                if let error { self.output = "Motion error: \(Self.describe(error))"; return }
                guard let motion else { return }
                let a = motion.userAcceleration
                let r = motion.rotationRate
                self.userAcceleration = MotionVector(x: a.x, y: a.y, z: a.z)
                self.rotationRate = MotionVector(x: r.x, y: r.y, z: r.z)
                self.gravity = MotionVector(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z)
                self.attitude = MotionVector(x: Self.degrees(motion.attitude.roll), y: Self.degrees(motion.attitude.pitch), z: Self.degrees(motion.attitude.yaw))
                if frame != nil {
                    let field = motion.magneticField
                    self.magneticField = MotionVector(x: field.field.x, y: field.field.y, z: field.field.z)
                    self.magneticAccuracy = Self.calibrationName(field.accuracy)
                }
                self.lastUpdated = Date()
                self.output = "Live device motion is updating."
            }
        }
        if let frame {
            magneticSource = "Device motion · calibrated (\(Self.frameName(frame)))"
        } else if rawMagnetometer {
            magneticSource = "Raw magnetometer · uncalibrated, includes device bias"
            magneticAccuracy = "Not calibrated"
            manager.magnetometerUpdateInterval = 0.1
            manager.startMagnetometerUpdates(to: .main) { [weak self] data, error in
                guard let self else { return }
                if let error { self.output = "Magnetometer error: \(Self.describe(error))"; return }
                guard let field = data?.magneticField else { return }
                self.magneticField = MotionVector(x: field.x, y: field.y, z: field.z)
                self.lastUpdated = Date()
            }
        } else {
            magneticSource = "No magnetometer on this device"
        }
        #else
        output = "Core Motion is not available on this platform."
        #endif
    }

    func stopMotion() {
        #if os(iOS) || os(watchOS)
        manager.stopDeviceMotionUpdates()
        manager.stopMagnetometerUpdates()
        #endif
        isRunning = false
    }

    /// Stops every running stream (device motion, magnetometer, pedometer, altimeter).
    func stop() {
        stopMotion()
        stopPedometer()
        stopAltimeter()
    }

    // MARK: Pedometer

    func startPedometer() {
        #if os(iOS) || os(watchOS)
        guard CMPedometer.isStepCountingAvailable() else {
            output = "Step counting is not available on this device or in the Simulator."
            return
        }
        guard ![.denied, .restricted].contains(PermissionProbe.motionActivity()) else {
            output = "Motion & Fitness access is denied. Allow it in Settings › Privacy & Security › Motion & Fitness."
            return
        }
        isPedometerRunning = true
        pedometerReading = PedometerReading()
        output = "Pedometer started. Walk a few steps; updates arrive every few seconds."
        let now = Date()
        pedometer.queryPedometerData(from: Calendar.current.startOfDay(for: now), to: now) { @Sendable [weak self] data, error in
            let steps = data?.numberOfSteps.intValue
            let message = error.map(MotionExperimentService.describe)
            Task { @MainActor in self?.applyToday(steps: steps, error: message) }
        }
        pedometer.startUpdates(from: now) { @Sendable [weak self] data, error in
            let snapshot = data.map(PedometerSnapshot.init)
            let message = error.map(MotionExperimentService.describe)
            Task { @MainActor in self?.apply(snapshot, error: message) }
        }
        #else
        output = "CMPedometer is not available on this platform."
        #endif
    }

    func stopPedometer() {
        guard isPedometerRunning else { return }
        #if os(iOS) || os(watchOS)
        pedometer.stopUpdates()
        #endif
        isPedometerRunning = false
    }

    // MARK: Altimeter

    func startAltimeter() {
        #if os(iOS) || os(watchOS)
        guard CMAltimeter.isRelativeAltitudeAvailable() else {
            output = "This device has no barometer, so relative altitude is not available."
            return
        }
        guard ![.denied, .restricted].contains(PermissionProbe.motionActivity()) else {
            output = "Motion & Fitness access is denied. Allow it in Settings › Privacy & Security › Motion & Fitness."
            return
        }
        isAltimeterRunning = true
        let absoluteAvailable = CMAltimeter.isAbsoluteAltitudeAvailable()
        altitudeReading = AltitudeReading(absolute: absoluteAvailable ? "Waiting…" : "Not available on this device")
        output = "Altimeter started. Relative altitude starts at 0 m; move up or down a floor."
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            guard let self else { return }
            self.refreshPermissionOnce()
            if let error { self.output = "Altimeter error: \(Self.describe(error))"; self.stopAltimeter(); return }
            guard let data else { return }
            self.altitudeReading.relative = Self.number(data.relativeAltitude.doubleValue, digits: 2) + " m"
            self.altitudeReading.pressure = Self.number(data.pressure.doubleValue, digits: 3) + " kPa"
        }
        if absoluteAvailable {
            altimeter.startAbsoluteAltitudeUpdates(to: .main) { [weak self] data, error in
                guard let self else { return }
                if let error { self.altitudeReading.absolute = "Error: \(Self.describe(error))"; return }
                guard let data else { return }
                self.altitudeReading.absolute = Self.number(data.altitude) + " m"
                self.altitudeReading.absoluteAccuracy = "±" + Self.number(data.accuracy) + " m · precision " + Self.number(data.precision) + " m"
            }
        }
        #else
        output = "CMAltimeter is not available on this platform."
        #endif
    }

    func stopAltimeter() {
        guard isAltimeterRunning else { return }
        #if os(iOS) || os(watchOS)
        altimeter.stopRelativeAltitudeUpdates()
        altimeter.stopAbsoluteAltitudeUpdates()
        #endif
        isAltimeterRunning = false
    }

    // MARK: Helpers

    #if os(iOS) || os(watchOS)
    private func applyToday(steps: Int?, error: String?) {
        pedometerReading.today = steps.map { "\($0) steps" } ?? error.map { "Unavailable · \($0)" } ?? "—"
    }

    /// The first sensor callback reveals the Motion & Fitness decision; refresh the status badge once.
    private func refreshPermissionOnce() {
        guard !permissionRefreshed else { return }
        permissionRefreshed = true
        PermissionCenter.shared.invalidate()
    }

    private func apply(_ snapshot: PedometerSnapshot?, error: String?) {
        refreshPermissionOnce()
        if let error {
            output = "Pedometer error: \(error)"
            stopPedometer()
            return
        }
        guard let snapshot, isPedometerRunning else { return }
        pedometerReading.steps = "\(snapshot.steps)"
        pedometerReading.distance = Self.value(snapshot.distance, available: CMPedometer.isDistanceAvailable()) { Self.number($0) + " m" }
        pedometerReading.floors = Self.value(snapshot.floorsAscended, available: CMPedometer.isFloorCountingAvailable()) { "\($0) up · \(snapshot.floorsDescended ?? 0) down" }
        pedometerReading.cadence = Self.value(snapshot.cadence, available: CMPedometer.isCadenceAvailable()) { Self.number($0 * 60, digits: 0) + " steps/min" }
        pedometerReading.pace = Self.value(snapshot.pace, available: CMPedometer.isPaceAvailable()) { Self.number($0 * 1_000 / 60) + " min/km" }
        output = "Pedometer updated at \(Date().formatted(date: .omitted, time: .standard))."
    }

    /// Reference frames that fuse the magnetometer, so device motion also reports a calibrated field.
    private static func magneticFrame() -> CMAttitudeReferenceFrame? {
        let frames = CMMotionManager.availableAttitudeReferenceFrames()
        if frames.contains(.xMagneticNorthZVertical) { return .xMagneticNorthZVertical }
        if frames.contains(.xArbitraryCorrectedZVertical) { return .xArbitraryCorrectedZVertical }
        return nil
    }

    private static func frameName(_ frame: CMAttitudeReferenceFrame) -> String {
        frame == .xMagneticNorthZVertical ? "magnetic north, Z vertical" : "arbitrary X, magnetometer-corrected"
    }

    private static func calibrationName(_ accuracy: CMMagneticFieldCalibrationAccuracy) -> String {
        switch accuracy {
        case .uncalibrated: "Uncalibrated · move the device in a figure eight"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        @unknown default: "Unknown"
        }
    }

    nonisolated static func describe(_ error: Error) -> String {
        let code = (error as NSError).code
        if code == Int(CMErrorMotionActivityNotAuthorized.rawValue) || code == Int(CMErrorNotAuthorized.rawValue) {
            return "Motion & Fitness access is denied (Settings › Privacy & Security › Motion & Fitness)."
        }
        if code == Int(CMErrorMotionActivityNotAvailable.rawValue) || code == Int(CMErrorNotAvailable.rawValue) {
            return "This sensor is not available on this device."
        }
        return error.localizedDescription
    }
    #endif

    private static func feature(_ title: String, _ available: Bool) -> MotionFeature {
        MotionFeature(title: title, isAvailable: available, detail: available ? "Available" : "Not on this device")
    }

    private static func value<T>(_ value: T?, available: Bool, format: (T) -> String) -> String {
        guard available else { return "Not available on this device" }
        return value.map(format) ?? "No data yet"
    }

    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

    private static func number(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }
}

#if os(iOS) || os(watchOS)
/// Sendable copy of `CMPedometerData`, which arrives on a background queue.
private nonisolated struct PedometerSnapshot: Sendable {
    let steps: Int
    let distance: Double?
    let floorsAscended: Int?
    let floorsDescended: Int?
    /// Steps per second.
    let cadence: Double?
    /// Seconds per meter.
    let pace: Double?

    init(_ data: CMPedometerData) {
        steps = data.numberOfSteps.intValue
        distance = data.distance?.doubleValue
        floorsAscended = data.floorsAscended?.intValue
        floorsDescended = data.floorsDescended?.intValue
        cadence = data.currentCadence?.doubleValue
        pace = data.currentPace?.doubleValue
    }
}
#endif

extension ExperimentAvailability {
    /// Device motion needs no permission; pedometer and altimeter are blocked when Motion & Fitness is denied.
    static func coreMotion() -> ExperimentStatus {
        #if os(iOS) || os(watchOS)
        guard DeviceCapabilities.current.motion else { return .hardwareUnsupported }
        switch PermissionProbe.motionActivity() {
        case .denied, .restricted: return .permissionDenied
        default: return .available
        }
        #else
        return .platformUnsupported
        #endif
    }
}
