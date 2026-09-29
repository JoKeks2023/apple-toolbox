import Foundation
import Accelerate
import Synchronization
#if canImport(AVFAudio)
import AVFAudio
import CoreAudioTypes
#endif

/// Waveforms the Audio Analyzer tone generator renders.
nonisolated enum ToneWaveform: Int, CaseIterable, Identifiable, Sendable {
    case sine, square, sawtooth, whiteNoise

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sine: "Sine"
        case .square: "Square (PolyBLEP)"
        case .sawtooth: "Sawtooth (PolyBLEP)"
        case .whiteNoise: "White noise"
        }
    }
}

/// Maps a 0…1 slider position to 20 Hz…20 kHz on a logarithmic scale, like the frequency axis of an analyzer.
nonisolated enum ToneFrequencyScale {
    static let minimum = 20.0
    static let maximum = 20_000.0

    static func frequency(forPosition position: Double) -> Double {
        minimum * pow(maximum / minimum, min(max(position, 0), 1))
    }

    static func position(forFrequency frequency: Double) -> Double {
        log(min(max(frequency, minimum), maximum) / minimum) / log(maximum / minimum)
    }

    static func label(_ frequency: Double) -> String {
        frequency >= 1_000
            ? (frequency / 1_000).formatted(.number.precision(.fractionLength(2))) + " kHz"
            : frequency.formatted(.number.precision(.fractionLength(1))) + " Hz"
    }
}

/// Tone settings written by the main actor and read by the real-time render thread.
/// Lock-free atomics keep the render callback free of locks and allocations.
nonisolated final class ToneParameters: Sendable {
    private let waveformValue: Atomic<Int>
    private let frequencyBits: Atomic<UInt64>
    private let amplitudeBits: Atomic<UInt64>

    init(waveform: ToneWaveform = .sine, frequency: Double = 440, amplitude: Double = 0.2) {
        waveformValue = Atomic(waveform.rawValue)
        frequencyBits = Atomic(frequency.bitPattern)
        amplitudeBits = Atomic(amplitude.bitPattern)
    }

    var waveform: ToneWaveform {
        get { ToneWaveform(rawValue: waveformValue.load(ordering: .relaxed)) ?? .sine }
        set { waveformValue.store(newValue.rawValue, ordering: .relaxed) }
    }

    var frequency: Double {
        get { Double(bitPattern: frequencyBits.load(ordering: .relaxed)) }
        set { frequencyBits.store(newValue.bitPattern, ordering: .relaxed) }
    }

    /// Linear peak amplitude, 0…1 (1 = 0 dBFS).
    var amplitude: Double {
        get { Double(bitPattern: amplitudeBits.load(ordering: .relaxed)) }
        set { amplitudeBits.store(min(max(newValue, 0), 1).bitPattern, ordering: .relaxed) }
    }
}

/// Renders the tone. Only one thread (the render thread, or a test) calls `render`,
/// so the phase, amplitude ramp and noise state need no synchronization.
nonisolated final class ToneOscillator: @unchecked Sendable {
    let parameters: ToneParameters
    let sampleRate: Double
    private var phase = 0.0
    private var amplitude = 0.0
    private var noiseState: UInt64 = 0x9E37_79B9_7F4A_7C15

    init(parameters: ToneParameters, sampleRate: Double) {
        self.parameters = parameters
        self.sampleRate = sampleRate
    }

    /// Fills `count` mono samples. The amplitude ramps linearly to the current target within the block,
    /// so volume changes do not click; frequency changes keep the phase continuous.
    func render(into samples: UnsafeMutablePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let waveform = parameters.waveform
        let increment = min(max(parameters.frequency, 0), sampleRate / 2) / sampleRate
        let target = parameters.amplitude
        let step = (target - amplitude) / Double(count)
        for index in 0..<count {
            amplitude += step
            let value: Double = switch waveform {
            case .sine: sin(2 * .pi * phase)
            case .square: (phase < 0.5 ? 1 : -1) + Self.polyBLEP(phase, increment) - Self.polyBLEP((phase + 0.5).truncatingRemainder(dividingBy: 1), increment)
            case .sawtooth: 2 * phase - 1 - Self.polyBLEP(phase, increment)
            case .whiteNoise: nextNoise()
            }
            samples[index] = Float(value * amplitude)
            phase += increment
            if phase >= 1 { phase -= 1 }
        }
        amplitude = target
    }

    /// Convenience for tests and offline use.
    func render(count: Int) -> [Float] {
        [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            if let base = buffer.baseAddress { render(into: base, count: count) }
            initialized = count
        }
    }

    /// Polynomial band-limited step: smooths the discontinuity of square and sawtooth waves to reduce aliasing.
    static func polyBLEP(_ phase: Double, _ increment: Double) -> Double {
        guard increment > 0 else { return 0 }
        if phase < increment {
            let x = phase / increment
            return x + x - x * x - 1
        }
        if phase > 1 - increment {
            let x = (phase - 1) / increment
            return x * x + x + x + 1
        }
        return 0
    }

    /// xorshift64* mapped to -1…1: deterministic and real-time safe (no system calls).
    private func nextNoise() -> Double {
        noiseState ^= noiseState >> 12
        noiseState ^= noiseState << 25
        noiseState ^= noiseState >> 27
        let value = noiseState &* 0x2545_F491_4F6C_DD1D
        return Double(value >> 11) / Double(UInt64(1) << 53) * 2 - 1
    }
}

#if canImport(AVFAudio)
nonisolated enum ToneRenderBlock {
    /// Built outside the main actor: the block runs on the real-time audio thread and only touches the oscillator.
    /// The first buffer is rendered, further (non-interleaved) channels get a copy.
    static func make(for oscillator: ToneOscillator) -> AVAudioSourceNodeRenderBlock {
        { @Sendable isSilence, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let first = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            let count = Int(frameCount)
            oscillator.render(into: first, count: count)
            for index in buffers.indices.dropFirst() {
                buffers[index].mData?.copyMemory(from: first, byteCount: count * MemoryLayout<Float>.size)
            }
            isSilence.pointee = false
            return noErr
        }
    }
}
#endif

/// One display band of the spectrum: the loudest FFT bin between two frequencies.
nonisolated struct SpectrumBand: Identifiable, Equatable, Sendable {
    let id: Int
    let lowerFrequency: Double
    let upperFrequency: Double
    /// dBFS (0 = full-scale sine).
    let level: Float

    var centerFrequency: Double { (lowerFrequency * upperFrequency).squareRoot() }
}

nonisolated struct SpectrumPeak: Equatable, Sendable {
    let frequency: Double
    let level: Float
}

nonisolated enum SpectrumMath {
    /// Floor of the dB scale; bins below it are clamped.
    static let floorDecibels: Float = -140

    static func binWidth(sampleRate: Double, fftSize: Int) -> Double { sampleRate / Double(fftSize) }

    /// Loudest bin at or above `minimumFrequency`, refined by parabolic interpolation over the neighbouring dB values.
    /// Returns nil when nothing rises above `threshold`.
    static func dominantPeak(in decibels: [Float], sampleRate: Double, fftSize: Int, minimumFrequency: Double = 20, threshold: Float = -100) -> SpectrumPeak? {
        let width = binWidth(sampleRate: sampleRate, fftSize: fftSize)
        let first = max(1, Int((minimumFrequency / width).rounded(.up)))
        guard first < decibels.count else { return nil }
        var best = first
        for bin in first..<decibels.count where decibels[bin] > decibels[best] { best = bin }
        guard decibels[best] > threshold else { return nil }
        guard best > 0, best < decibels.count - 1 else { return SpectrumPeak(frequency: Double(best) * width, level: decibels[best]) }
        let left = Double(decibels[best - 1]), center = Double(decibels[best]), right = Double(decibels[best + 1])
        let denominator = left - 2 * center + right
        let offset = denominator == 0 ? 0 : min(max(0.5 * (left - right) / denominator, -0.5), 0.5)
        let level = center - 0.25 * (left - right) * offset
        return SpectrumPeak(frequency: (Double(best) + offset) * width, level: Float(level))
    }

    /// Groups FFT bins (index = bin, value = dBFS) into logarithmically spaced bands for display.
    /// Bands narrower than one bin take the bin nearest to their center, so low frequencies stay continuous.
    static func logBands(from decibels: [Float], sampleRate: Double, fftSize: Int, count: Int, minimumFrequency: Double = 20) -> [SpectrumBand] {
        let nyquist = sampleRate / 2
        guard count > 0, !decibels.isEmpty, minimumFrequency > 0, minimumFrequency < nyquist else { return [] }
        let width = binWidth(sampleRate: sampleRate, fftSize: fftSize)
        let ratio = nyquist / minimumFrequency
        let lastBin = decibels.count - 1
        return (0..<count).map { index in
            let lower = minimumFrequency * pow(ratio, Double(index) / Double(count))
            let upper = minimumFrequency * pow(ratio, Double(index + 1) / Double(count))
            let firstBin = min(Int((lower / width).rounded(.up)), lastBin)
            let endBin = min(Int((upper / width).rounded(.down)), lastBin)
            let level: Float
            if firstBin <= endBin {
                level = decibels[firstBin...endBin].max() ?? floorDecibels
            } else {
                level = decibels[min(Int(((lower * upper).squareRoot() / width).rounded()), lastBin)]
            }
            return SpectrumBand(id: index, lowerFrequency: lower, upperFrequency: upper, level: level)
        }
    }

    /// Linear amplitude to dBFS; silence maps to the floor.
    static func decibels(fromAmplitude amplitude: Double) -> Double {
        amplitude > 0 ? max(20 * log10(amplitude), Double(floorDecibels)) : Double(floorDecibels)
    }
}

/// Hann-windowed real FFT (vDSP) over the most recent `size` samples, scaled so a full-scale sine reads 0 dBFS.
/// Not thread-safe: one instance belongs to one tap (or test) at a time.
nonisolated final class SpectrumAnalyzer: @unchecked Sendable {
    let size: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let window: [Float]
    private let coherentGain: Float
    private var history: [Float]
    private var filled = 0
    private var windowed: [Float]
    private var real: [Float]
    private var imaginary: [Float]
    private var magnitudes: [Float]

    init?(size: Int = 4_096) {
        guard size >= 16, size & (size - 1) == 0 else { return nil }
        let log2n = vDSP_Length(size.trailingZeroBitCount)
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return nil }
        self.size = size
        self.log2n = log2n
        self.setup = setup
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        coherentGain = vDSP.sum(window) / Float(size)
        history = [Float](repeating: 0, count: size)
        windowed = [Float](repeating: 0, count: size)
        real = [Float](repeating: 0, count: size / 2)
        imaginary = [Float](repeating: 0, count: size / 2)
        magnitudes = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// Appends new samples to the sliding window and returns the dBFS spectrum (bins 0..<size/2),
    /// or nil until `size` samples have arrived.
    func process(_ samples: UnsafeBufferPointer<Float>) -> [Float]? {
        append(samples)
        guard filled >= size else { return nil }
        return history.withUnsafeBufferPointer(spectrum(of:))
    }

    /// dBFS spectrum of exactly `size` samples.
    func spectrum(of samples: UnsafeBufferPointer<Float>) -> [Float] {
        precondition(samples.count == size, "SpectrumAnalyzer expects \(size) samples")
        let half = size / 2
        vDSP.multiply(samples, window, result: &windowed)
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                var split = DSPSplitComplex(realp: realBuffer.baseAddress!, imagp: imaginaryBuffer.baseAddress!)
                windowed.withUnsafeBufferPointer { input in
                    input.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(kFFTDirection_Forward))
                // zrip packs the Nyquist bin into imagp[0]; clear it so bin 0 is DC only.
                split.imagp[0] = 0
                magnitudes.withUnsafeMutableBufferPointer { vDSP_zvabs(&split, 1, $0.baseAddress!, 1, vDSP_Length(half)) }
            }
        }
        // zrip returns twice the DFT; a sine of amplitude A peaks at A·N/2·coherentGain in the DFT.
        var amplitudes = vDSP.multiply(1 / (Float(size) * coherentGain), magnitudes)
        amplitudes[0] *= 0.5 // DC has no mirrored negative-frequency half.
        let clamped = vDSP.threshold(amplitudes, to: pow(10, SpectrumMath.floorDecibels / 20), with: .clampToThreshold)
        return vDSP.amplitudeToDecibels(clamped, zeroReference: 1)
    }

    private func append(_ samples: UnsafeBufferPointer<Float>) {
        guard let source = samples.baseAddress, !samples.isEmpty else { return }
        history.withUnsafeMutableBufferPointer { buffer in
            guard let destination = buffer.baseAddress else { return }
            if samples.count >= size {
                destination.update(from: source + (samples.count - size), count: size)
            } else {
                let keep = size - samples.count
                memmove(destination, destination + samples.count, keep * MemoryLayout<Float>.stride)
                (destination + keep).update(from: source, count: samples.count)
            }
        }
        filled = min(size, filled + samples.count)
    }
}

/// One analysis result of the microphone tap, sent to the main actor.
nonisolated struct AudioAnalysisFrame: Sendable {
    let rms: Float
    let peak: Float
    let bands: [SpectrumBand]
    let dominant: SpectrumPeak?
}

#if canImport(AVFAudio)
nonisolated enum MicrophoneAnalysisTap {
    /// Built outside the main actor: AVAudioEngine calls the tap on its own thread. The block only touches the
    /// analyzer (owned by this tap) and hands a Sendable frame to `deliver`.
    static func make(analyzer: SpectrumAnalyzer, sampleRate: Double, bandCount: Int, deliver: @escaping @Sendable (AudioAnalysisFrame) -> Void) -> AVAudioNodeTapBlock {
        { @Sendable buffer, _ in
            guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
            let samples = UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))
            let rms = vDSP.rootMeanSquare(samples)
            let peak = vDSP.maximumMagnitude(samples)
            var bands: [SpectrumBand] = []
            var dominant: SpectrumPeak?
            if let spectrum = analyzer.process(samples) {
                bands = SpectrumMath.logBands(from: spectrum, sampleRate: sampleRate, fftSize: analyzer.size, count: bandCount)
                dominant = SpectrumMath.dominantPeak(in: spectrum, sampleRate: sampleRate, fftSize: analyzer.size)
            }
            deliver(AudioAnalysisFrame(rms: rms, peak: peak, bands: bands, dominant: dominant))
        }
    }
}
#endif
