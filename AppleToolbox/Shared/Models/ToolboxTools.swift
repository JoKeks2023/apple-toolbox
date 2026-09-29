import Foundation

/// Experiments promoted into everyday utilities (spec §40, "Real Utility Mode").
struct ToolboxTool: Identifiable {
    /// The experiment that implements the tool.
    let id: String
    let title: String
    let symbolName: String
    /// The original experiment the tool grew out of.
    let promotedFrom: String
    let summary: String

    var experiment: ExperimentDescriptor? { ExperimentRegistry.descriptor(for: id) }
}

enum ToolboxTools {
    static let all: [ToolboxTool] = [
        ToolboxTool(id: "capability-explorer", title: "Device Scanner", symbolName: "cpu", promotedFrom: "List a few device facts",
                    summary: "What this device can do: hardware, sensors, cameras, radios and Apple features."),
        ToolboxTool(id: "nfc-inspector", title: "NFC Inspector", symbolName: "wave.3.right.circle", promotedFrom: "Read NFC tag",
                    summary: "Identify ISO 7816, ISO 15693, FeliCa and MIFARE tags, send APDUs, read and write NDEF."),
        ToolboxTool(id: "network-path", title: "Network Inspector", symbolName: "network", promotedFrom: "Show current connection",
                    summary: "Path, interfaces, TCP/UDP/TLS connections, an echo listener and Bonjour browsing."),
        ToolboxTool(id: "location-dashboard", title: "Location Dashboard", symbolName: "location.viewfinder", promotedFrom: "Show coordinates",
                    summary: "Record a track with speed, altitude and accuracy charts and export it as GPX or GeoJSON."),
        ToolboxTool(id: "audio-input", title: "Audio Analyzer", symbolName: "waveform.badge.magnifyingglass", promotedFrom: "Play sine wave",
                    summary: "Tone generator, effects, routes and latency, and a live spectrum of the microphone."),
        ToolboxTool(id: "homekit-discovery", title: "Home Inspector", symbolName: "house.and.flag", promotedFrom: "Discover accessories",
                    summary: "Browse accessories and characteristics, write values, run scenes and list automations."),
        ToolboxTool(id: "indoor-survey", title: "Indoor Survey", symbolName: "map", promotedFrom: "Survey experiment",
                    summary: "Record survey points and paths on an IMDF level with an accuracy heatmap and GeoJSON export."),
        ToolboxTool(id: "cryptokit", title: "Crypto Lab", symbolName: "key.horizontal", promotedFrom: "Generate key",
                    summary: "Hash, encrypt, agree on keys, sign, HPKE and key import/export with round-trip checks."),
    ]
}
