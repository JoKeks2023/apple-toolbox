import Foundation

struct DeviceCapabilities {
    let secureEnclave: Bool
    let biometricType: String
    let motion: Bool
    /// Whether Core Location exists on this platform. Whether Location Services are switched on is only
    /// read by `DeviceScanner`, off the main thread, because that call can block.
    let location: Bool

    static var current: DeviceCapabilities {
        DeviceCapabilities(secureEnclave: DeviceProbes.hasSecureEnclave, biometricType: DeviceProbes.biometry().name ?? "Not available",
                           motion: DeviceProbes.hasMotionSensors, location: DeviceProbes.hasCoreLocation)
    }
}
