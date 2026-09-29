import Foundation

nonisolated extension ImplementationGuides {
    static let developer: [String: ImplementationGuide] = [
        "capability-explorer": ImplementationGuide(
            snippet: #"""
            import AVFoundation
            import CoreLocation
            import CoreMotion
            import FoundationModels
            import LocalAuthentication
            import NearbyInteraction

            /// Reports what this device supports, without triggering any permission prompt.
            func capabilityReport() -> [String: Bool] {
                let context = LAContext()
                _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) // Fills biometryType.
                return [
                    "Barometer": CMAltimeter.isRelativeAltitudeAvailable(),
                    "Motion activity": CMMotionActivityManager.isActivityAvailable(),
                    "Compass": CLLocationManager.headingAvailable(),
                    "Face ID": context.biometryType == .faceID,
                    "Touch ID": context.biometryType == .touchID,
                    "Ultra Wideband": NISession.deviceCapabilities.supportsPreciseDistanceMeasurement,
                    "LiDAR": AVCaptureDevice.default(.builtInLiDARDepthCamera, for: .video, position: .back) != nil,
                    "Apple Intelligence model": SystemLanguageModel.default.isAvailable,
                ]
            }
            """#,
            notes: [
                "Prefer capability checks over device-model lists: they stay correct on new hardware.",
                "Availability is not permission: a sensor can exist while the user has denied access to it.",
                "SystemLanguageModel.default.availability also tells you why the model is unavailable (not enabled, not ready, unsupported).",
            ]
        ),
        "developer-tools": ImplementationGuide(
            snippet: #"""
            import Foundation
            import StoreKit

            /// Where this build runs: use it to gate debug menus and test data, not features.
            struct BuildContext: Sendable {
                let isSimulator: Bool
                let isDebugBuild: Bool
                let isiOSAppOnMac: Bool
                let storeEnvironment: String? // "Xcode", "Sandbox" (TestFlight) or "Production".

                static func current() async -> BuildContext {
                    #if targetEnvironment(simulator)
                    let simulator = true
                    #else
                    let simulator = false
                    #endif
                    #if DEBUG
                    let debug = true
                    #else
                    let debug = false
                    #endif
                    let environment = try? await AppTransaction.shared.payloadValue.environment.rawValue
                    return BuildContext(isSimulator: simulator, isDebugBuild: debug,
                                        isiOSAppOnMac: ProcessInfo.processInfo.isiOSAppOnMac, storeEnvironment: environment)
                }
            }
            """#,
            notes: [
                "DEBUG is a compiler flag set by the Debug configuration, not a runtime check: TestFlight builds are Release.",
                "AppTransaction.shared can prompt for an Apple Account sign-in in rare cases; call it off the launch path.",
            ]
        ),
        "diagnostics": ImplementationGuide(
            snippet: #"""
            import MetricKit
            import OSLog

            let logger = Logger(subsystem: "com.example.app", category: "sync")
            let signposter = OSSignposter(logger: logger)

            /// Logs to the unified log (Console) and marks an interval for Instruments' Points of Interest.
            func sync(items: Int) async {
                let state = signposter.beginInterval("sync")
                defer { signposter.endInterval("sync", state) }
                logger.info("Syncing \(items, privacy: .public) items")
            }

            /// This process's own log entries from the last five minutes.
            func recentLogMessages() throws -> [String] {
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let start = store.position(date: .now.addingTimeInterval(-300))
                return try store.getEntries(at: start).compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
            }

            /// Receives daily metrics and crash, hang and disk-write diagnostics.
            final class MetricsReceiver: NSObject, MXMetricManagerSubscriber {
                override init() {
                    super.init()
                    MXMetricManager.shared.add(self)
                }

                func didReceive(_ payloads: [MXMetricPayload]) {
                    for payload in payloads { print(String(decoding: payload.jsonRepresentation(), as: UTF8.self)) }
                }

                func didReceive(_ payloads: [MXDiagnosticPayload]) {
                    for payload in payloads { print("Crashes: \(payload.crashDiagnostics?.count ?? 0)") }
                }
            }
            """#,
            notes: [
                "Interpolated values are <private> in logs unless marked privacy: .public; never make personal data public.",
                "MetricKit delivers at most once a day (diagnostics immediately on iOS 15+); nothing arrives in the Simulator.",
                "OSLogStore on iOS only reads the current process's entries.",
            ]
        ),
    ]
}
