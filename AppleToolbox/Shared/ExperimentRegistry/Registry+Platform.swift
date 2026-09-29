import Foundation

extension ExperimentRegistry {
    static let platform: [ExperimentDescriptor] = [
        ExperimentDescriptor(id: "metal", name: "Metal", category: .platform,
            description: "Inspect the system Metal GPU (architecture, GPU families, unified memory, recommended working set, ray tracing, threadgroup limits, argument buffer tier), then compile a compute kernel from source at runtime that doubles an array on the GPU and verify every value.",
            frameworks: ["Metal"], supportedPlatforms: [.iOS, .iPadOS, .macOS, .tvOS], hardwareRequirements: ["Metal GPU"],
            osRequirements: ["iOS 8+ · macOS 10.11+ · tvOS 9+", "GPU families: iOS 13+ · macOS 10.15+ · tvOS 13+", "Metal 4 family: iOS 26+ · macOS 26+ · tvOS 26+"],
            permissions: [], capabilities: [], entitlements: [], documentationURL: URL(string: "https://developer.apple.com/documentation/metal")!, evaluate: ExperimentAvailability.metal,
            useCase: ExperimentUseCase(id: "metal-compute", title: "Run your own code on the GPU", summary: "See what the GPU reports about itself, then prove it runs code: a kernel is compiled from source on this device and doubles 4,096 floats.", interaction: "Read the GPU facts and families, then run the compute check and compare the verified values and GPU time."),
            explanations: [
                .hardwareUnsupported: ExperimentExplanation(reason: "MTLCreateSystemDefaultDevice() returned nil, so this device exposes no Metal GPU to apps.", required: "A Metal GPU (every supported iPhone, iPad, Apple TV and Mac has one)",
                    nextStep: "Run the experiment on the device itself; some virtual machines and remote sessions expose no Metal device."),
                .platformUnsupported: ExperimentExplanation(reason: "watchOS has no Metal framework; apps draw only through SwiftUI and SpriteKit there.", required: "iOS, iPadOS, macOS or tvOS",
                    nextStep: "Open Apple Toolbox on an iPhone, iPad, Mac or Apple TV."),
            ]),
        ExperimentDescriptor(id: "mac-hardware", name: "Mac Hardware", category: .platform,
            description: "List Core Audio devices with transport, channels and sample rates, cameras including Continuity Camera, mounted volumes with capacity, APFS, encryption and case sensitivity, and connected displays with resolution, refresh rate and EDR headroom. Public APIs only, no IOKit.",
            frameworks: ["CoreAudio", "AVFoundation", "Foundation", "AppKit", "CoreGraphics"], supportedPlatforms: [.macOS], hardwareRequirements: [],
            osRequirements: ["macOS 10.15+", "External and Continuity cameras: macOS 14+"], permissions: [], capabilities: ["App Sandbox: device and volume metadata only, no recording"], entitlements: [],
            documentationURL: URL(string: "https://developer.apple.com/documentation/coreaudio")!, evaluate: ExperimentAvailability.macHardware,
            useCase: ExperimentUseCase(id: "mac-hardware-inventory", title: "Inventory the Mac's hardware", summary: "See every audio device, camera, drive and display the system reports, with the formats and capabilities apps can rely on.", interaction: "Read the lists, then turn on Watch for Changes and plug in headphones, a drive or a display."),
            explanations: [
                .platformUnsupported: ExperimentExplanation(reason: "The Core Audio hardware layer (AudioObject), NSScreen and mounted-volume enumeration only exist on macOS. iOS and iPadOS expose audio routes through AVAudioSession and screens through UIScreen instead.", required: "macOS",
                    nextStep: "Open Apple Toolbox on a Mac, or use Audio Input and the Capability Explorer here."),
            ]),
    ]
}
