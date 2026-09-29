import Foundation

nonisolated extension ImplementationGuides {
    static let connectivity: [String: ImplementationGuide] = [
        "core-bluetooth": ImplementationGuide(
            snippet: #"""
            import CoreBluetooth

            /// Finds a heart-rate peripheral, connects and subscribes to its notifying characteristics.
            @MainActor
            final class HeartRateScanner: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
                private let heartRateService = CBUUID(string: "180D")
                private var central: CBCentralManager!
                private var peripheral: CBPeripheral? // Keep a strong reference, or the connection is cancelled.

                override init() {
                    super.init()
                    central = CBCentralManager(delegate: self, queue: .main) // Callbacks arrive on the main queue.
                }

                nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
                    MainActor.assumeIsolated {
                        if central.state == .poweredOn { central.scanForPeripherals(withServices: [heartRateService]) }
                    }
                }

                nonisolated func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                                                advertisementData: [String: Any], rssi RSSI: NSNumber) {
                    MainActor.assumeIsolated {
                        central.stopScan()
                        self.peripheral = peripheral
                        peripheral.delegate = self
                        central.connect(peripheral)
                    }
                }

                nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
                    peripheral.discoverServices(nil)
                }

                nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
                    for service in peripheral.services ?? [] { peripheral.discoverCharacteristics(nil, for: service) }
                }

                nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
                    for characteristic in service.characteristics ?? [] where characteristic.properties.contains(.notify) {
                        peripheral.setNotifyValue(true, for: characteristic)
                    }
                }

                nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
                    print("\(characteristic.uuid): \(characteristic.value?.map { String(format: "%02x", $0) }.joined() ?? "-")")
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSBluetoothAlwaysUsageDescription", value: "Connects to your Bluetooth sensors."),
            ],
            notes: [
                "Only call CBCentralManager methods after the state is .poweredOn; earlier calls are ignored with an API misuse warning.",
                "Scanning with a nil service list is slow and does not work in the background: filter by service UUIDs.",
                "Peripheral identifiers are per app and per device; they are not the Bluetooth MAC address.",
            ]
        ),
        "bluetooth-peripheral": ImplementationGuide(
            snippet: #"""
            import CoreBluetooth

            /// Publishes one GATT service and advertises it, so a central (another device) can read and subscribe.
            @MainActor
            final class GATTServer: NSObject, CBPeripheralManagerDelegate {
                private let serviceID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
                private let characteristic = CBMutableCharacteristic(
                    type: CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"),
                    properties: [.read, .write, .notify], value: nil, permissions: [.readable, .writeable])
                private var manager: CBPeripheralManager!

                override init() {
                    super.init()
                    manager = CBPeripheralManager(delegate: self, queue: .main)
                }

                func notify(_ text: String) {
                    // Returns false when the transmit queue is full: resend in peripheralManagerIsReady(toUpdateSubscribers:).
                    _ = manager.updateValue(Data(text.utf8), for: characteristic, onSubscribedCentrals: nil)
                }

                nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
                    MainActor.assumeIsolated {
                        guard peripheral.state == .poweredOn else { return }
                        let service = CBMutableService(type: serviceID, primary: true)
                        service.characteristics = [characteristic]
                        peripheral.add(service)
                        peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceID],
                                                     CBAdvertisementDataLocalNameKey: "My Accessory"])
                    }
                }

                nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
                    request.value = Data("hello".utf8)
                    peripheral.respond(to: request, withResult: .success)
                }

                nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
                    for request in requests { print("Write: \(String(decoding: request.value ?? Data(), as: UTF8.self))") }
                    if let first = requests.first { peripheral.respond(to: first, withResult: .success) }
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSBluetoothAlwaysUsageDescription", value: "Lets other devices connect to this one over Bluetooth."),
            ],
            notes: [
                "Respond to a batch of write requests once, with the first request of the batch.",
                "iOS only advertises the local name and service UUIDs; manufacturer data is not allowed in the advertisement.",
                "In the background, service UUIDs move to an overflow area that only iOS centrals scanning for them can see.",
            ]
        ),
        "accessory-setup-kit": ImplementationGuide(
            snippet: #"""
            import AccessorySetupKit
            import CoreBluetooth
            import UIKit

            /// Lets the user pick one accessory in a system sheet instead of granting app-wide Bluetooth access.
            @MainActor
            final class AccessorySetup {
                private let session = ASAccessorySession()

                func start() {
                    session.activate(on: .main) { event in
                        switch event.eventType {
                        case .activated: print("Already authorized: \(event.accessory?.displayName ?? "none yet")")
                        case .accessoryAdded: print("Added \(event.accessory?.displayName ?? "")")
                        case .accessoryRemoved: print("Removed \(event.accessory?.displayName ?? "")")
                        default: break
                        }
                    }
                }

                func pickAccessory() async throws {
                    let descriptor = ASDiscoveryDescriptor()
                    descriptor.bluetoothServiceUUID = CBUUID(string: "180D")
                    let item = ASPickerDisplayItem(name: "Heart Rate Sensor",
                                                   productImage: UIImage(systemName: "heart.circle")!, descriptor: descriptor)
                    try await session.showPicker(for: [item])
                }

                /// The accessories this app may use; connect with CBCentralManager via their bluetoothIdentifier.
                var authorizedAccessories: [ASAccessory] { session.accessories }
            }
            """#,
            infoPlist: [
                .init(key: "NSAccessorySetupSupports", value: "<array><string>Bluetooth</string></array>"),
                .init(key: "NSAccessorySetupBluetoothServices", value: "<array><string>180D</string></array>"),
            ],
            notes: [
                "iOS 18+: every service UUID or name you discover must also be declared in the Info.plist, or the picker fails.",
                "After picking, CBCentralManager only sees the authorized accessories: use retrievePeripherals(withIdentifiers:) with bluetoothIdentifier.",
                "The product image should be a transparent, high-resolution picture of the real accessory.",
            ]
        ),
        "external-accessory": ImplementationGuide(
            snippet: #"""
            import ExternalAccessory

            /// Lists connected MFi accessories and opens a session with the first protocol they support.
            @MainActor
            final class MFiAccessories {
                private var session: EASession?

                func connected() -> [String] {
                    let manager = EAAccessoryManager.shared()
                    manager.registerForLocalNotifications() // Posts .EAAccessoryDidConnect / .EAAccessoryDidDisconnect.
                    return manager.connectedAccessories.map {
                        "\($0.name) · \($0.manufacturer) · \($0.modelNumber) · fw \($0.firmwareRevision) · \($0.protocolStrings)"
                    }
                }

                func open(_ accessory: EAAccessory) {
                    // The protocol must be listed in UISupportedExternalAccessoryProtocols.
                    guard let protocolString = accessory.protocolStrings.first,
                          let session = EASession(accessory: accessory, forProtocol: protocolString) else { return }
                    session.inputStream?.schedule(in: .main, forMode: .default)
                    session.outputStream?.schedule(in: .main, forMode: .default)
                    session.inputStream?.open()
                    session.outputStream?.open()
                    self.session = session
                }
            }
            """#,
            infoPlist: [
                .init(key: "UISupportedExternalAccessoryProtocols", value: "<array><string>com.example.accessory.protocol</string></array>"),
            ],
            notes: [
                "Only accessories built under Apple's MFi Program appear; plain BLE devices never show up here.",
                "App Review requires the accessory maker to register your app with Apple before an app declaring a protocol ships.",
                "Only one EASession per accessory and protocol can be open at a time.",
            ]
        ),
        "wireless-accessory-configuration": ImplementationGuide(
            snippet: #"""
            import ExternalAccessory
            import UIKit

            /// Finds an unconfigured MFi Wi-Fi accessory (e.g. an AirPlay speaker) and hands it the user's Wi-Fi.
            @MainActor
            final class WiFiAccessorySetup: NSObject, EAWiFiUnconfiguredAccessoryBrowserDelegate {
                private var browser: EAWiFiUnconfiguredAccessoryBrowser?
                weak var presenter: UIViewController?

                func start() {
                    let browser = EAWiFiUnconfiguredAccessoryBrowser(delegate: self, queue: .main)
                    browser.startSearchingForUnconfiguredAccessories(matching: nil)
                    self.browser = browser
                }

                nonisolated func accessoryBrowser(_ browser: EAWiFiUnconfiguredAccessoryBrowser,
                                                  didFindUnconfiguredAccessories accessories: Set<EAWiFiUnconfiguredAccessory>) {
                    MainActor.assumeIsolated {
                        guard let accessory = accessories.first, let presenter else { return }
                        browser.stopSearchingForUnconfiguredAccessories()
                        browser.configureAccessory(accessory, withConfigurationUIOn: presenter) // System sheet.
                    }
                }

                nonisolated func accessoryBrowser(_ browser: EAWiFiUnconfiguredAccessoryBrowser,
                                                  didFinishConfiguringAccessory accessory: EAWiFiUnconfiguredAccessory,
                                                  with status: EAWiFiUnconfiguredAccessoryConfigurationStatus) {
                    print("\(accessory.name): \(status == .success ? "configured" : "not configured")")
                }

                nonisolated func accessoryBrowser(_ browser: EAWiFiUnconfiguredAccessoryBrowser,
                                                  didUpdate state: EAWiFiUnconfiguredAccessoryBrowserState) {}
                nonisolated func accessoryBrowser(_ browser: EAWiFiUnconfiguredAccessoryBrowser,
                                                  didRemoveUnconfiguredAccessories accessories: Set<EAWiFiUnconfiguredAccessory>) {}
            }
            """#,
            entitlements: ["com.apple.external-accessory.wireless-configuration = true"],
            capabilities: ["Wireless Accessory Configuration"],
            notes: [
                "Only MFi Wi-Fi accessories in setup mode (WAC) are found; other Wi-Fi devices need NEHotspotConfiguration.",
                "The Wireless Accessory Configuration capability must be enabled for the App ID, or the browser finds nothing.",
            ]
        ),
        "bluetooth-midi": ImplementationGuide(
            snippet: #"""
            import CoreAudioKit
            import CoreMIDI
            import UIKit

            /// Receives MIDI from every source, including paired Bluetooth LE MIDI devices.
            final class MIDIListener {
                private var client = MIDIClientRef()
                private var port = MIDIPortRef()

                /// `onWord` runs on a real-time MIDI thread: keep it short and hop to the main actor for UI.
                init(onWord: @escaping @Sendable (UInt32) -> Void) {
                    MIDIClientCreateWithBlock("Listener" as CFString, &client, nil)
                    MIDIInputPortCreateWithProtocol(client, "Input" as CFString, ._1_0, &port) { eventList, _ in
                        for packet in eventList.unsafeSequence() {
                            onWord(packet.pointee.words.0) // A Universal MIDI Packet word, e.g. 0x2090_3C64 = note on.
                        }
                    }
                    for index in 0..<MIDIGetNumberOfSources() {
                        MIDIPortConnectSource(port, MIDIGetSource(index), nil)
                    }
                }
            }

            /// Apple's UI to find and pair Bluetooth LE MIDI devices.
            @MainActor
            func bluetoothMIDIPairingController() -> UIViewController {
                UINavigationController(rootViewController: CABTMIDICentralViewController())
            }
            """#,
            infoPlist: [
                .init(key: "NSBluetoothAlwaysUsageDescription", value: "Pairs Bluetooth MIDI keyboards and controllers."),
            ],
            notes: [
                "A newly paired device appears as a new source: listen for setup changes in the client's notify block and connect it.",
                "The receive block runs on a high-priority Core MIDI thread; never block it or touch UI there.",
                "Paired Bluetooth MIDI devices stay connected only while an app keeps them connected.",
            ]
        ),
        "multipeer-connectivity": ImplementationGuide(
            snippet: #"""
            import MultipeerConnectivity

            /// Advertises and browses the same service, connects automatically and exchanges text.
            final class NearbyMessenger: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
                private static let serviceType = "example-chat" // 1–15 characters: lowercase letters, digits, hyphens.
                private let peer = MCPeerID(displayName: "My iPhone")
                private let session: MCSession
                private let advertiser: MCNearbyServiceAdvertiser
                private let browser: MCNearbyServiceBrowser
                private let onMessage: @Sendable (String) -> Void

                init(onMessage: @escaping @Sendable (String) -> Void) {
                    session = MCSession(peer: peer, securityIdentity: nil, encryptionPreference: .required)
                    advertiser = MCNearbyServiceAdvertiser(peer: peer, discoveryInfo: nil, serviceType: Self.serviceType)
                    browser = MCNearbyServiceBrowser(peer: peer, serviceType: Self.serviceType)
                    self.onMessage = onMessage
                    super.init()
                    session.delegate = self
                    advertiser.delegate = self
                    browser.delegate = self
                    advertiser.startAdvertisingPeer()
                    browser.startBrowsingForPeers()
                }

                func send(_ text: String) throws {
                    try session.send(Data(text.utf8), toPeers: session.connectedPeers, with: .reliable)
                }

                // Delegate callbacks arrive on private MultipeerConnectivity queues.
                func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
                    if peer.displayName < peerID.displayName { browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10) }
                }
                func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
                    invitationHandler(true, session)
                }
                func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
                    onMessage(String(decoding: data, as: UTF8.self))
                }
                func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
                func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {}
                func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
                func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
                func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
            }
            """#,
            infoPlist: [
                .init(key: "NSLocalNetworkUsageDescription", value: "Finds your other devices nearby to exchange messages."),
                .init(key: "NSBonjourServices", value: "<array><string>_example-chat._tcp</string><string>_example-chat._udp</string></array>"),
            ],
            notes: [
                "Declare both _<service>._tcp and _<service>._udp in NSBonjourServices, or browsing fails with a -72008 error.",
                "Let only one side invite (e.g. compare display names), otherwise simultaneous invitations collide.",
                "Sessions end when the app is suspended; there is no background mode for MultipeerConnectivity.",
            ]
        ),
        "continuity": ImplementationGuide(
            snippet: #"""
            import WatchConnectivity

            /// Used in both the iPhone app and the watch app.
            final class WatchLink: NSObject, WCSessionDelegate {
                private let onMessage: @Sendable (String) -> Void

                init(onMessage: @escaping @Sendable (String) -> Void) {
                    self.onMessage = onMessage
                    super.init()
                    guard WCSession.isSupported() else { return }
                    WCSession.default.delegate = self
                    WCSession.default.activate()
                }

                func ping() {
                    let session = WCSession.default
                    guard session.activationState == .activated else { return }
                    if session.isReachable {
                        session.sendMessage(["text": "ping"], replyHandler: nil) { error in print(error) }
                    } else {
                        session.transferUserInfo(["text": "ping"]) // Queued and delivered in order, even to a closed app.
                    }
                }

                func publishState(_ value: String) throws {
                    try WCSession.default.updateApplicationContext(["latest": value]) // Only the newest value is kept.
                }

                // Delegate callbacks arrive on a background queue.
                func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
                func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
                    if let text = message["text"] as? String { onMessage(text) }
                }
                func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
                    if let text = userInfo["text"] as? String { onMessage(text) }
                }
                #if os(iOS)
                func sessionDidBecomeInactive(_ session: WCSession) {}
                func sessionDidDeactivate(_ session: WCSession) { session.activate() } // The user switched watches.
                #endif
            }
            """#,
            notes: [
                "Activate the session early (app launch) in both apps; messages sent before activation are lost.",
                "sendMessage needs the counterpart reachable (in the foreground on watchOS); use transferUserInfo or the application context otherwise.",
                "Payload dictionaries may only contain property-list types.",
            ]
        ),
        "ecosystem-continuity": ImplementationGuide(
            snippet: #"""
            import GroupActivities
            import SwiftUI

            /// Advertises what the user is reading for Handoff, and continues it on the other device.
            struct ArticleView: View {
                let articleID: String

                var body: some View {
                    Text(articleID)
                        .userActivity("com.example.app.article") { activity in
                            activity.title = "Reading \(articleID)"
                            activity.userInfo = ["id": articleID]
                            activity.isEligibleForHandoff = true
                        }
                }
            }

            struct RootView: View {
                @State private var openArticle: String?

                var body: some View {
                    Text(openArticle ?? "Nothing open")
                        .onContinueUserActivity("com.example.app.article") { activity in
                            openArticle = activity.userInfo?["id"] as? String
                        }
                }
            }

            /// A SharePlay activity; start it with `try await WatchTogether().activate()`.
            struct WatchTogether: GroupActivity {
                var metadata: GroupActivityMetadata {
                    var metadata = GroupActivityMetadata()
                    metadata.title = "Watch together"
                    metadata.type = .watchTogether
                    return metadata
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSUserActivityTypes", value: "<array><string>com.example.app.article</string></array>"),
            ],
            entitlements: [
                "com.apple.developer.group-session = true",
                "com.apple.developer.associated-domains = [applinks:example.com] (Universal Links, optional)",
            ],
            capabilities: ["Group Activities", "Associated Domains (only for Universal Links)"],
            notes: [
                "Handoff only works between devices signed in to the same Apple Account with Bluetooth and Wi-Fi on, for apps from the same team.",
                "Every activity type you advertise or continue must be listed in NSUserActivityTypes.",
                "Keep userInfo small: Handoff payloads are limited to a few kilobytes; transfer bulk data separately.",
            ]
        ),
        "nearby-interaction": ImplementationGuide(
            snippet: #"""
            import NearbyInteraction

            /// Ranges with another iPhone over Ultra Wideband once both sides exchanged discovery tokens.
            @MainActor
            final class UWBRanger: NSObject, NISessionDelegate {
                private let session = NISession()
                var onUpdate: ((_ distance: Float?, _ direction: SIMD3<Float>?) -> Void)?

                override init() {
                    super.init()
                    session.delegate = self
                }

                /// Send this to the other device over your own channel (e.g. MultipeerConnectivity).
                func localToken() throws -> Data? {
                    guard let token = session.discoveryToken else { return nil }
                    return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
                }

                func run(peerToken data: Data) throws {
                    guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else { return }
                    let configuration = NINearbyPeerConfiguration(peerToken: token)
                    configuration.isCameraAssistanceEnabled = NISession.deviceCapabilities.supportsCameraAssistance
                    session.run(configuration)
                }

                nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
                    guard let object = nearbyObjects.first else { return }
                    let distance = object.distance, direction = object.direction
                    Task { @MainActor in self.onUpdate?(distance, direction) }
                }

                nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
                    print("Session invalidated: \(error)") // Create a new NISession to start over.
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSNearbyInteractionUsageDescription", value: "Shows how far away and in which direction the other iPhone is."),
                .init(key: "NSCameraUsageDescription", value: "Improves direction finding with the camera."),
            ],
            notes: [
                "Check NISession.deviceCapabilities.supportsPreciseDistanceMeasurement first: UWB needs iPhone 11 or later.",
                "Direction is often nil without camera assistance (iOS 16+), which also requires the camera permission.",
                "Sessions pause when the app goes to the background and can't be reused after invalidation.",
            ]
        ),
        "spatial-link": ImplementationGuide(
            snippet: #"""
            import Network

            /// Advertises this device over Bonjour and reports the other devices doing the same.
            final class LinkDiscovery {
                private static let serviceType = "_example-link._tcp"
                private let queue = DispatchQueue(label: "link-discovery")
                private var listener: NWListener?
                private var browser: NWBrowser?

                func start(deviceName: String, onPeers: @escaping @Sendable ([String]) -> Void) throws {
                    let queue = self.queue
                    let listener = try NWListener(using: .tcp)
                    listener.service = NWListener.Service(name: deviceName, type: Self.serviceType)
                    listener.newConnectionHandler = { connection in
                        connection.start(queue: queue) // Exchange e.g. Nearby Interaction tokens over this connection.
                    }
                    listener.start(queue: queue)

                    let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: .tcp)
                    browser.browseResultsChangedHandler = { results, _ in
                        onPeers(results.compactMap { result in
                            if case let .service(name, _, _, _) = result.endpoint, name != deviceName { return name }
                            return nil
                        })
                    }
                    browser.start(queue: queue)
                    (self.listener, self.browser) = (listener, browser)
                }

                func stop() {
                    listener?.cancel()
                    browser?.cancel()
                }
            }
            """#,
            infoPlist: [
                .init(key: "NSLocalNetworkUsageDescription", value: "Finds your other devices on this network."),
                .init(key: "NSBonjourServices", value: "<array><string>_example-link._tcp</string><string>_example-link._udp</string></array>"),
                .init(key: "NSNearbyInteractionUsageDescription", value: "Measures the distance to your other devices."),
            ],
            notes: [
                "The first listener or browser triggers the local network prompt; if denied, the browser reports a waiting state with a DNS-SD error.",
                "Every Bonjour type you advertise or browse must be in NSBonjourServices.",
                "Bonjour tells you who is around; distance and direction need Nearby Interaction on top.",
            ]
        ),
    ]
}
