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

@MainActor
final class MotionExperimentService: ObservableObject {
    @Published private(set) var output = "Ready to start motion updates."
    @Published private(set) var isRunning = false
    @Published private(set) var status: ExperimentStatus = .available
    @Published private(set) var userAcceleration = MotionVector()
    @Published private(set) var rotationRate = MotionVector()
    @Published private(set) var gravity = MotionVector()
    @Published private(set) var lastUpdated: Date?
    #if os(iOS) || os(watchOS)
    private let manager = CMMotionManager()
    #endif

    init() {
        #if os(iOS) || os(watchOS)
        status = manager.isDeviceMotionAvailable ? .available : .hardwareUnsupported
        #else
        status = .platformUnsupported
        #endif
    }

    func start() {
        #if os(iOS) || os(watchOS)
        guard manager.isDeviceMotionAvailable else {
            output = "Device Motion is not available on this platform or simulator."
            return
        }
        manager.deviceMotionUpdateInterval = 0.1
        isRunning = true
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self else { return }
            if let error { self.output = "Motion error: \(error.localizedDescription)"; return }
            guard let motion else { return }
            let a = motion.userAcceleration
            let r = motion.rotationRate
            self.userAcceleration = MotionVector(x: a.x, y: a.y, z: a.z)
            self.rotationRate = MotionVector(x: r.x, y: r.y, z: r.z)
            self.gravity = MotionVector(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z)
            self.lastUpdated = Date()
            self.output = "Live device motion is updating."
        }
        #else
        output = "Core Motion is not available on this platform."
        #endif
    }

    func stop() {
        #if os(iOS) || os(watchOS)
        manager.stopDeviceMotionUpdates()
        #endif
        isRunning = false
    }
}
