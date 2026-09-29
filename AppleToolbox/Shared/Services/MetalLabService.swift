import Foundation
import Combine
#if canImport(Metal)
import Metal
#endif

extension ExperimentAvailability {
    /// Metal needs a GPU that the system exposes to apps; watchOS has no Metal at all.
    static func metal() -> ExperimentStatus {
        #if canImport(Metal)
        MetalLabService.hasSystemDevice ? .available : .hardwareUnsupported
        #else
        .platformUnsupported
        #endif
    }
}

struct PlatformFact: Identifiable, Equatable {
    let title: String
    let value: String
    var id: String { title }
}

/// The compute check: a kernel compiled from source at runtime that doubles every element of an array.
nonisolated enum MetalComputeCheck {
    static let functionName = "double_values"
    static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    kernel void double_values(device const float *input [[buffer(0)]],
                              device float *output [[buffer(1)]],
                              constant uint &count [[buffer(2)]],
                              uint index [[thread_position_in_grid]]) {
        if (index >= count) { return; }
        output[index] = input[index] * 2.0f;
    }
    """

    /// Deterministic input with fractions and negative values, so a wrong kernel cannot pass by accident.
    static func input(count: Int) -> [Float] {
        (0..<count).map { Float($0) * 0.5 - 100 }
    }

    /// Indices whose output is not exactly twice the input (doubling a float is exact).
    static func mismatches(input: [Float], output: [Float]) -> [Int] {
        guard input.count == output.count else { return Array(0..<max(input.count, output.count)) }
        return input.indices.filter { output[$0] != input[$0] * 2 }
    }

    /// Threadgroups needed to cover `count` threads with `width` threads per group.
    static func threadgroups(count: Int, width: Int) -> Int {
        guard count > 0, width > 0 else { return 0 }
        return (count + width - 1) / width
    }

    static func milliseconds(_ seconds: Double) -> String {
        (seconds * 1000).formatted(.number.precision(.fractionLength(3))) + " ms"
    }
}

#if canImport(Metal)
/// Reads the system default Metal device and runs a small compute kernel on it.
@MainActor
final class MetalLabService: ObservableObject {
    /// Cached so the registry's live status does not create a device on every evaluation.
    static let hasSystemDevice = MTLCreateSystemDefaultDevice() != nil

    @Published private(set) var facts: [PlatformFact] = []
    @Published private(set) var families: [String] = []
    @Published private(set) var otherDevices: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var output: String
    @Published private(set) var isError = false

    private let device: (any MTLDevice)?

    init() {
        device = MTLCreateSystemDefaultDevice()
        output = device == nil
            ? "MTLCreateSystemDefaultDevice() returned nil: this device exposes no Metal GPU to apps."
            : "Ready. Run the compute check to compile a kernel from source and execute it on the GPU."
        isError = device == nil
        read()
    }

    var hasDevice: Bool { device != nil }

    func read() {
        guard let device else { return }
        facts = Self.facts(of: device)
        families = Self.families(of: device)
        #if os(macOS)
        otherDevices = MTLCopyAllDevices().filter { $0.registryID != device.registryID }.map(\.name)
        #endif
    }

    func runComputeCheck() {
        guard let device, !isRunning else { return }
        isRunning = true
        isError = false
        output = "Compiling the kernel from source…"
        Task {
            await compute(on: device)
            isRunning = false
        }
    }

    private func compute(on device: any MTLDevice) async {
        let count = 4096
        let input = MetalComputeCheck.input(count: count)
        let clock = ContinuousClock()
        do {
            let compileStart = clock.now
            let library = try await device.makeLibrary(source: MetalComputeCheck.kernelSource, options: nil)
            let compileTime = clock.now - compileStart
            guard let function = library.makeFunction(name: MetalComputeCheck.functionName) else {
                return fail("The compiled library has no function named \(MetalComputeCheck.functionName).")
            }
            let pipeline = try await device.makeComputePipelineState(function: function)
            let length = count * MemoryLayout<Float>.stride
            guard let queue = device.makeCommandQueue(),
                  let inputBuffer = input.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: length, options: .storageModeShared) }),
                  let outputBuffer = device.makeBuffer(length: length, options: .storageModeShared),
                  let commandBuffer = queue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder()
            else { return fail("Metal could not create the command queue, buffers or encoder.") }

            var elementCount = UInt32(count)
            let width = min(pipeline.maxTotalThreadsPerThreadgroup, count)
            let groups = MetalComputeCheck.threadgroups(count: count, width: width)
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(inputBuffer, offset: 0, index: 0)
            encoder.setBuffer(outputBuffer, offset: 0, index: 1)
            encoder.setBytes(&elementCount, length: MemoryLayout<UInt32>.stride, index: 2)
            encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: width, height: 1, depth: 1))
            encoder.endEncoding()

            output = "Running \(groups) threadgroup(s) of \(width) threads on \(device.name)…"
            let status = await withCheckedContinuation { (continuation: CheckedContinuation<MTLCommandBufferStatus, Never>) in
                commandBuffer.addCompletedHandler { @Sendable buffer in continuation.resume(returning: buffer.status) }
                commandBuffer.commit()
            }
            guard status == .completed else {
                return fail("The command buffer ended with status \(status.rawValue): \(commandBuffer.error.map { "\($0)" } ?? "no error reported").")
            }
            let pointer = outputBuffer.contents().bindMemory(to: Float.self, capacity: count)
            let results = Array(UnsafeBufferPointer(start: pointer, count: count))
            let mismatches = MetalComputeCheck.mismatches(input: input, output: results)
            let gpuTime = commandBuffer.gpuEndTime - commandBuffer.gpuStartTime
            isError = !mismatches.isEmpty
            output = """
            \(mismatches.isEmpty ? "Verified" : "Mismatch"): \(count - mismatches.count) of \(count) values are exactly doubled.
            Kernel: \(MetalComputeCheck.functionName), compiled from source in \(compileTime.formatted(.units(allowed: [.milliseconds], fractionalPart: .show(length: 1)))).
            Pipeline: \(pipeline.maxTotalThreadsPerThreadgroup) max threads per threadgroup, SIMD width \(pipeline.threadExecutionWidth).
            Dispatch: \(groups) × \(width) threads · GPU time \(MetalComputeCheck.milliseconds(gpuTime)).
            Sample: \(input[1]) → \(results[1]), \(input[count - 1]) → \(results[count - 1])
            """ + (mismatches.isEmpty ? "" : "\nFirst wrong index: \(mismatches[0]) (\(input[mismatches[0]]) → \(results[mismatches[0]]))")
        } catch {
            fail("Metal reported an error: \(error.localizedDescription)")
        }
    }

    private func fail(_ message: String) {
        isError = true
        output = message
    }

    private static func facts(of device: any MTLDevice) -> [PlatformFact] {
        let threads = device.maxThreadsPerThreadgroup
        var facts = [
            PlatformFact(title: "GPU", value: device.name),
            PlatformFact(title: "Architecture", value: device.architecture.name),
            PlatformFact(title: "Registry ID", value: "0x" + String(device.registryID, radix: 16)),
            PlatformFact(title: "Unified memory", value: device.hasUnifiedMemory ? "Yes (CPU and GPU share memory)" : "No (dedicated GPU memory)"),
            PlatformFact(title: "Recommended working set", value: bytes(device.recommendedMaxWorkingSetSize)),
            PlatformFact(title: "Currently allocated", value: bytes(UInt64(device.currentAllocatedSize))),
            PlatformFact(title: "Max buffer length", value: bytes(UInt64(device.maxBufferLength))),
            PlatformFact(title: "Max threads per threadgroup", value: "\(threads.width) × \(threads.height) × \(threads.depth)"),
            PlatformFact(title: "Threadgroup memory", value: bytes(UInt64(device.maxThreadgroupMemoryLength))),
            PlatformFact(title: "Argument buffers", value: argumentBuffersTier(device.argumentBuffersSupport)),
            PlatformFact(title: "Ray tracing", value: yesNo(device.supportsRaytracing)),
            PlatformFact(title: "Function pointers", value: yesNo(device.supportsFunctionPointers)),
            PlatformFact(title: "Dynamic libraries", value: yesNo(device.supportsDynamicLibraries)),
            PlatformFact(title: "32-bit float filtering", value: yesNo(device.supports32BitFloatFiltering)),
            PlatformFact(title: "BC texture compression", value: yesNo(device.supportsBCTextureCompression)),
        ]
        if let counters = device.counterSets, !counters.isEmpty {
            facts.append(PlatformFact(title: "GPU counter sets", value: counters.map(\.name).joined(separator: ", ")))
        }
        return facts
    }

    private static func families(of device: any MTLDevice) -> [String] {
        var known: [(MTLGPUFamily, String)] = [
            (.apple1, "Apple 1"), (.apple2, "Apple 2"), (.apple3, "Apple 3"), (.apple4, "Apple 4"), (.apple5, "Apple 5"),
            (.apple6, "Apple 6"), (.apple7, "Apple 7"), (.apple8, "Apple 8"), (.apple9, "Apple 9"), (.apple10, "Apple 10"),
            (.apple11, "Apple 11"), (.metal3, "Metal 3"),
        ]
        // MTLGPUFamilyMetal4 (5002) by raw value: the Simulator SDKs don't declare the case.
        if let metal4 = MTLGPUFamily(rawValue: 5002) { known.append((metal4, "Metal 4")) }
        return known.filter { device.supportsFamily($0.0) }.map(\.1)
    }

    private static func argumentBuffersTier(_ tier: MTLArgumentBuffersTier) -> String {
        switch tier {
        case .tier1: "Tier 1"
        case .tier2: "Tier 2"
        @unknown default: "Tier \(tier.rawValue + 1)"
        }
    }

    private static func yesNo(_ value: Bool) -> String { value ? "Supported" : "Not supported" }

    private static func bytes(_ value: UInt64) -> String {
        Int64(clamping: value).formatted(.byteCount(style: .memory))
    }
}
#endif
