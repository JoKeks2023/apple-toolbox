import Foundation

nonisolated extension ImplementationGuides {
    static let home: [String: ImplementationGuide] = [
        "homekit-discovery": ImplementationGuide(
            snippet: #"""
            import HomeKit

            /// Loads the user's homes and lists their accessories.
            @MainActor
            final class HomeStore: NSObject, @preconcurrency HMHomeManagerDelegate {
                private let manager = HMHomeManager()
                private(set) var homes: [HMHome] = []

                override init() {
                    super.init()
                    manager.delegate = self // triggers the permission prompt and the initial load
                }

                func homeManagerDidUpdateHomes(_ manager: HMHomeManager) {
                    homes = manager.homes
                    for home in homes {
                        for accessory in home.accessories {
                            print(home.name, accessory.name, accessory.room?.name ?? "-", accessory.isReachable)
                        }
                    }
                }

                func homeManager(_ manager: HMHomeManager, didUpdate status: HMHomeManagerAuthorizationStatus) {
                    if !status.contains(.authorized) { print("HomeKit access denied") }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSHomeKitUsageDescription", value: "Lists and controls the accessories in your home."),
            ],
            entitlements: ["com.apple.developer.homekit = true"],
            capabilities: ["HomeKit"],
            notes: [
                "homes is empty until homeManagerDidUpdateHomes fires — do not read it right after creating the manager.",
                "Keep one HMHomeManager for the app's lifetime; each new instance reloads the home database.",
                "HomeKit is iOS/iPadOS/watchOS/tvOS; on macOS it is only available to Mac Catalyst apps.",
            ]
        ),
        "matter-status": ImplementationGuide(
            snippet: #"""
            import HomeKit
            import MatterSupport

            /// Adds a Matter (or HomeKit) accessory through the system setup flow.
            @MainActor
            func addMatterAccessory() async {
                guard MatterAddDeviceRequest.isSupported else {
                    print("Matter setup is not supported on this device")
                    return
                }
                let setupManager = HMAccessorySetupManager()
                do {
                    let result = try await setupManager.performAccessorySetup(using: HMAccessorySetupRequest())
                    print("Added accessories:", result.accessoryUniqueIdentifiers, "to home", result.homeUniqueIdentifier)
                } catch {
                    print("Setup cancelled or failed: \(error)")
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSHomeKitUsageDescription", value: "Adds new accessories to your home."),
            ],
            entitlements: ["com.apple.developer.homekit = true"],
            capabilities: ["HomeKit"],
            notes: [
                "The system sheet scans the QR/setup code and handles commissioning; your app never sees the setup payload unless you pass one.",
                "To commission into your own ecosystem instead of Apple Home, use MatterAddDeviceRequest with a MatterSupport extension.",
                "Matter over Thread needs a Thread border router (HomePod mini, Apple TV 4K) in the home.",
            ]
        ),
        "homekit-accessory-browser": ImplementationGuide(
            snippet: #"""
            import HomeKit

            /// Reads and writes an accessory's characteristics (e.g. a light's power state).
            @MainActor
            enum AccessoryControl {
                static func powerCharacteristic(of accessory: HMAccessory) -> HMCharacteristic? {
                    accessory.services
                        .flatMap(\.characteristics)
                        .first { $0.characteristicType == HMCharacteristicTypePowerState }
                }

                static func toggle(_ accessory: HMAccessory) async throws {
                    guard let power = powerCharacteristic(of: accessory),
                          power.properties.contains(HMCharacteristicPropertyWritable) else { return }
                    try await power.readValue()
                    let isOn = power.value as? Bool ?? false
                    try await power.writeValue(!isOn)
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSHomeKitUsageDescription", value: "Shows and controls your accessories."),
            ],
            entitlements: ["com.apple.developer.homekit = true"],
            capabilities: ["HomeKit"],
            notes: [
                "Unreachable accessories fail reads and writes; check accessory.isReachable and show it in the UI.",
                "For live updates call enableNotification(true) on the characteristic and implement HMAccessoryDelegate.",
                "HMAccessoryBrowser for unpaired accessories is legacy; new apps add accessories via HMAccessorySetupManager.",
            ]
        ),
    ]
}
