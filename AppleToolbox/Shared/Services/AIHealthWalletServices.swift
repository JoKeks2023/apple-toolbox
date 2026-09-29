import Foundation

#if canImport(HealthKit) && !os(macOS) && !os(tvOS)
import HealthKit
#endif

struct HealthExperimentService {
    static func statusText() -> String {
        #if canImport(HealthKit) && !os(macOS) && !os(tvOS)
        return HKHealthStore.isHealthDataAvailable() ? "HealthKit is available. Reading health data requires explicit user authorization and HealthKit entitlement." : "HealthKit is not available on this device."
        #else
        return "HealthKit is not available on this platform."
        #endif
    }
}
