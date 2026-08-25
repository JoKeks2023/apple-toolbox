import Foundation
#if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
import LocalAuthentication
#endif
#if canImport(CoreMotion)
import CoreMotion
#endif
#if canImport(CryptoKit)
import CryptoKit
#endif

struct DeviceCapabilities {
    let secureEnclave: Bool
    let biometricType: String
    let motion: Bool
    let location: Bool

    static var current: DeviceCapabilities {
        #if canImport(LocalAuthentication) && !os(watchOS) && !os(tvOS)
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let biometric: String
        switch context.biometryType {
        case .faceID: biometric = "Face ID"
        case .touchID: biometric = "Touch ID"
        default: biometric = canEvaluate ? "Biometrics" : "Not available"
        }
        #else
        let biometric = "Not available"
        #endif

        #if canImport(CryptoKit)
        let enclave = SecureEnclave.isAvailable
        #else
        let enclave = false
        #endif

        #if os(iOS) || os(watchOS)
        let motionAvailable = CMMotionManager().isDeviceMotionAvailable || CMMotionManager().isAccelerometerAvailable
        #else
        let motionAvailable = false
        #endif

        return DeviceCapabilities(secureEnclave: enclave, biometricType: biometric,
                                  motion: motionAvailable, location: true)
    }
}
