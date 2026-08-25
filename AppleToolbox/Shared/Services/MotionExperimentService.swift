import Foundation
import Combine
#if canImport(CoreMotion)
import CoreMotion
#endif

@MainActor
final class MotionExperimentService: ObservableObject {
    @Published private(set) var output = "Ready to start motion updates."
    @Published private(set) var isRunning = false
    @Published private(set) var status: ExperimentStatus = .available
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
            self.output = "User acceleration: x \(a.x.formatted(.number.precision(.fractionLength(3)))) · y \(a.y.formatted(.number.precision(.fractionLength(3)))) · z \(a.z.formatted(.number.precision(.fractionLength(3))))\nRotation rate: x \(r.x.formatted(.number.precision(.fractionLength(3)))) · y \(r.y.formatted(.number.precision(.fractionLength(3)))) · z \(r.z.formatted(.number.precision(.fractionLength(3))))\nGravity: x \(motion.gravity.x.formatted(.number.precision(.fractionLength(3)))) · y \(motion.gravity.y.formatted(.number.precision(.fractionLength(3)))) · z \(motion.gravity.z.formatted(.number.precision(.fractionLength(3))))"
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
