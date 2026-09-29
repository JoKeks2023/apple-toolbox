import Foundation

nonisolated extension ImplementationGuides {
    static let sensors: [String: ImplementationGuide] = [
        "core-motion": ImplementationGuide(
            snippet: #"""
            import CoreMotion

            /// Streams device attitude at 60 Hz on a background queue.
            final class MotionReader {
                private let manager = CMMotionManager() // one instance per app
                private let pedometer = CMPedometer() // keep it alive until the query returns
                private let queue = OperationQueue()

                func start(onAttitude: @escaping @Sendable (_ roll: Double, _ pitch: Double, _ yaw: Double) -> Void) {
                    guard manager.isDeviceMotionAvailable else { return }
                    manager.deviceMotionUpdateInterval = 1.0 / 60.0
                    manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: queue) { motion, error in
                        guard let attitude = motion?.attitude else { return }
                        onAttitude(attitude.roll, attitude.pitch, attitude.yaw)
                    }
                }

                func stop() { manager.stopDeviceMotionUpdates() }

                /// Pedometer and altimeter require Motion & Fitness permission (prompted on first use).
                func logStepsToday() {
                    guard CMPedometer.isStepCountingAvailable() else { return }
                    pedometer.queryPedometerData(from: Calendar.current.startOfDay(for: .now), to: .now) { data, _ in
                        print("Steps today:", data?.numberOfSteps ?? 0)
                    }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSMotionUsageDescription", value: "Counts your steps and floors climbed."),
            ],
            notes: [
                "Create only one CMMotionManager; several instances degrade the update rate.",
                "Raw accelerometer/gyro/device motion need no permission; CMPedometer and CMAltimeter prompt for Motion & Fitness.",
                "Don't deliver high-rate updates to OperationQueue.main — process on a background queue and throttle UI updates.",
            ]
        ),
    ]
}
