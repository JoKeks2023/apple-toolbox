import Foundation
#if os(macOS) && canImport(CoreWLAN)
import CoreWLAN
#endif

/// One access point seen by a Wi-Fi scan at a survey point.
nonisolated struct WiFiAccessPointSample: Codable, Equatable, Sendable {
    /// `nil` when macOS hides it (no location authorization).
    var ssid: String?
    var bssid: String?
    var rssi: Int
    var noise: Int
    var channel: Int
    var band: String

    /// Signal-to-noise ratio in dB.
    var snr: Int { rssi - noise }
}

/// A Wi-Fi fingerprint: the access points and their RSSI at one spot (spec §15).
nonisolated enum WiFiFingerprint {
    /// Strongest first; ties by BSSID so the order is stable.
    static func sorted(_ samples: [WiFiAccessPointSample]) -> [WiFiAccessPointSample] {
        samples.sorted { lhs, rhs in
            lhs.rssi != rhs.rssi ? lhs.rssi > rhs.rssi : (lhs.bssid ?? "") < (rhs.bssid ?? "")
        }
    }

    /// Short summary for a survey point, e.g. "12 APs · strongest −48 dBm (Office)".
    static func summary(_ samples: [WiFiAccessPointSample]) -> String {
        guard let strongest = sorted(samples).first else { return "No access points" }
        let name = strongest.ssid ?? strongest.bssid ?? "hidden"
        return "\(samples.count) AP(s) · strongest \(strongest.rssi) dBm (\(name))"
    }

    /// Whether names were withheld: macOS returns nil SSID/BSSID without location authorization.
    static func identifiersHidden(_ samples: [WiFiAccessPointSample]) -> Bool {
        !samples.isEmpty && samples.allSatisfy { $0.ssid == nil && $0.bssid == nil }
    }

    static var isScanSupported: Bool {
        #if os(macOS) && canImport(CoreWLAN)
        true
        #else
        false
        #endif
    }

    /// Scans with CoreWLAN (`CWInterface.scanForNetworks(withName:)`, macOS only). Blocking for a few seconds,
    /// so it runs off the main actor. iOS has no public scan API.
    static func scan() async throws -> [WiFiAccessPointSample] {
        #if os(macOS) && canImport(CoreWLAN)
        try await Task.detached(priority: .userInitiated) {
            guard let interface = CWWiFiClient.shared().interface() else {
                throw WiFiScanError(message: "CWWiFiClient has no Wi-Fi interface on this Mac.")
            }
            let networks = try interface.scanForNetworks(withName: nil)
            return sorted(networks.map { network in
                WiFiAccessPointSample(ssid: network.ssid, bssid: network.bssid, rssi: network.rssiValue, noise: network.noiseMeasurement,
                                      channel: network.wlanChannel?.channelNumber ?? 0, band: bandName(network.wlanChannel?.channelBand))
            })
        }.value
        #else
        throw WiFiScanError(message: "iOS and iPadOS offer apps no API to scan for Wi-Fi access points.")
        #endif
    }

    #if os(macOS) && canImport(CoreWLAN)
    private static func bandName(_ band: CWChannelBand?) -> String {
        switch band {
        case .band2GHz?: "2.4 GHz"
        case .band5GHz?: "5 GHz"
        case .band6GHz?: "6 GHz"
        default: "Unknown"
        }
    }
    #endif
}

nonisolated struct WiFiScanError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}
