import Foundation

enum CapabilityExplorerService {
    static func report() -> String {
        let device = DeviceCapabilities.current
        return "Platform: \(CurrentPlatform.value.rawValue)\nBiometrics: \(device.biometricType)\nSecure Enclave: \(device.secureEnclave ? "Available" : "Unavailable")\nMotion sensors: \(device.motion ? "Available" : "Unavailable")\nLocation API: \(device.location ? "Available" : "Unavailable")\n\nEntitlements are not inferred from API presence. Each experiment lists the exact capability or entitlement boundary; missing protected access is reported as a status instead of being bypassed."
    }
}
