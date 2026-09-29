import Testing
import Foundation
@testable import AppleToolbox

struct ToneOscillatorTests {

    private let sampleRate = 48_000.0

    /// Renders after a warm-up block, because the amplitude ramps up from silence in the first block.
    private func rendered(_ waveform: ToneWaveform, frequency: Double, amplitude: Double = 0.5, count: Int = 4_096) -> [Float] {
        let oscillator = ToneOscillator(parameters: ToneParameters(waveform: waveform, frequency: frequency, amplitude: amplitude), sampleRate: sampleRate)
        _ = oscillator.render(count: 64)
        return oscillator.render(count: count)
    }

    private func rms(_ samples: [Float]) -> Float {
        (samples.map { $0 * $0 }.reduce(0, +) / Float(samples.count)).squareRoot()
    }

    @Test func sineHasRequestedPeakAndRMS() {
        let samples = rendered(.sine, frequency: 750)
        #expect(abs((samples.map(abs).max() ?? 0) - 0.5) < 0.001)
        #expect(abs(rms(samples) - 0.5 / Float(2).squareRoot()) < 0.002)
    }

    @Test func firstBlockRampsUpFromSilence() {
        let oscillator = ToneOscillator(parameters: ToneParameters(waveform: .sine, frequency: 1_000, amplitude: 1), sampleRate: sampleRate)
        let first = oscillator.render(count: 480)
        let second = oscillator.render(count: 480)
        #expect((first.prefix(48).map(abs).max() ?? 1) < 0.11)
        #expect(abs((second.map(abs).max() ?? 0) - 1) < 0.01)
    }

    @Test func squareAndSawtoothStayBoundedAndCentered() {
        for waveform in [ToneWaveform.square, .sawtooth] {
            let samples = rendered(waveform, frequency: 1_000, count: 48_000)
            #expect(samples.allSatisfy { abs($0) <= 0.5 + 1e-4 }, "\(waveform)")
            #expect(abs(samples.reduce(0, +) / Float(samples.count)) < 0.01, "\(waveform)")
        }
    }

    @Test func squareSitsAtFullAmplitudeAwayFromEdges() {
        let samples = rendered(.square, frequency: 100, count: 480)
        // 100 Hz at 48 kHz: 480 samples per period, PolyBLEP only touches the sample next to each edge.
        let flat = samples.filter { abs(abs($0) - 0.5) < 1e-6 }
        #expect(flat.count >= 470)
    }

    @Test func whiteNoiseIsBoundedAndCentered() {
        let samples = rendered(.whiteNoise, frequency: 440, amplitude: 1, count: 48_000)
        #expect(samples.allSatisfy { abs($0) <= 1 })
        #expect(abs(samples.reduce(0, +) / Float(samples.count)) < 0.02)
        #expect(abs(rms(samples) - 1 / Float(3).squareRoot()) < 0.02)
    }

    @Test func frequencyAboveNyquistIsClamped() {
        // Clamped to 24 kHz, a sine is sampled at 0 and π only.
        let samples = rendered(.sine, frequency: 30_000, amplitude: 1, count: 256)
        #expect(samples.allSatisfy { abs($0) < 1e-3 })
    }

    @Test func polyBLEPOnlyActsNearTheDiscontinuity() {
        #expect(ToneOscillator.polyBLEP(0.5, 0.01) == 0)
        #expect(ToneOscillator.polyBLEP(0, 0.01) == -1)
        #expect(abs(ToneOscillator.polyBLEP(0.999_999, 0.01) - 1) < 1e-3)
        #expect(ToneOscillator.polyBLEP(0.3, 0) == 0)
    }

    @Test func parametersClampAmplitudeAndRoundTrip() {
        let parameters = ToneParameters()
        parameters.amplitude = 2
        #expect(parameters.amplitude == 1)
        parameters.amplitude = -1
        #expect(parameters.amplitude == 0)
        parameters.frequency = 1_234.5
        #expect(parameters.frequency == 1_234.5)
        parameters.waveform = .sawtooth
        #expect(parameters.waveform == .sawtooth)
    }

    @Test func frequencyScaleIsLogarithmicAndRoundTrips() {
        #expect(ToneFrequencyScale.frequency(forPosition: 0) == 20)
        #expect(abs(ToneFrequencyScale.frequency(forPosition: 1) - 20_000) < 1e-6)
        #expect(abs(ToneFrequencyScale.frequency(forPosition: 1.0 / 3) - 200) < 1e-6)
        for position in stride(from: 0.0, through: 1.0, by: 0.125) {
            #expect(abs(ToneFrequencyScale.position(forFrequency: ToneFrequencyScale.frequency(forPosition: position)) - position) < 1e-9)
        }
        #expect(ToneFrequencyScale.position(forFrequency: 5) == 0)
    }
}

struct SpectrumAnalyzerTests {

    private let sampleRate = 48_000.0
    private let size = 4_096

    private func sine(frequency: Double, amplitude: Float, count: Int) -> [Float] {
        (0..<count).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / sampleRate)) }
    }

    private func loudestBin(_ spectrum: [Float]) -> Int? {
        spectrum.indices.max { spectrum[$0] < spectrum[$1] }
    }

    @Test func requiresAPowerOfTwoSize() {
        #expect(SpectrumAnalyzer(size: 1_000) == nil)
        #expect(SpectrumAnalyzer(size: 8) == nil)
        #expect(SpectrumAnalyzer(size: 1_024)?.size == 1_024)
    }

    @Test func binCenteredSineReadsItsAmplitudeInDBFS() throws {
        let analyzer = try #require(SpectrumAnalyzer(size: size))
        let frequency = 64 * sampleRate / Double(size) // 750 Hz, exactly bin 64
        let spectrum = sine(frequency: frequency, amplitude: 0.5, count: size).withUnsafeBufferPointer(analyzer.spectrum(of:))
        #expect(spectrum.count == size / 2)
        #expect(loudestBin(spectrum) == 64)
        #expect(abs(spectrum[64] - 20 * log10(0.5)) < 0.05)
        #expect(spectrum[300] < -80) // Hann sidelobes fall off fast
    }

    @Test func fullScaleSineIsZeroDBFS() throws {
        let analyzer = try #require(SpectrumAnalyzer(size: size))
        let spectrum = sine(frequency: 128 * sampleRate / Double(size), amplitude: 1, count: size).withUnsafeBufferPointer(analyzer.spectrum(of:))
        #expect(abs(spectrum[128]) < 0.05)
    }

    @Test func dcOffsetIsNotDoubled() throws {
        let analyzer = try #require(SpectrumAnalyzer(size: size))
        let spectrum = [Float](repeating: 0.5, count: size).withUnsafeBufferPointer(analyzer.spectrum(of:))
        #expect(abs(spectrum[0] - 20 * log10(0.5)) < 0.05)
    }

    @Test func dominantPeakInterpolatesBetweenBins() throws {
        let analyzer = try #require(SpectrumAnalyzer(size: size))
        let spectrum = sine(frequency: 1_000, amplitude: 0.25, count: size).withUnsafeBufferPointer(analyzer.spectrum(of:))
        let peak = try #require(SpectrumMath.dominantPeak(in: spectrum, sampleRate: sampleRate, fftSize: size))
        #expect(abs(peak.frequency - 1_000) < 2) // bin width is 11.7 Hz
        #expect(abs(Double(peak.level) - 20 * log10(0.25)) < 1)
    }

    @Test func silenceSitsOnTheFloorWithoutPeak() throws {
        let analyzer = try #require(SpectrumAnalyzer(size: size))
        let spectrum = [Float](repeating: 0, count: size).withUnsafeBufferPointer(analyzer.spectrum(of:))
        #expect(spectrum.allSatisfy { $0 <= SpectrumMath.floorDecibels + 0.01 })
        #expect(SpectrumMath.dominantPeak(in: spectrum, sampleRate: sampleRate, fftSize: size) == nil)
    }

    @Test func processWaitsForAFullWindowAndThenSlides() throws {
        let analyzer = try #require(SpectrumAnalyzer(size: 1_024))
        let signal = sine(frequency: 3_000, amplitude: 0.5, count: 2_048) // 3 kHz = bin 64 of a 1024-point FFT
        var results: [[Float]?] = []
        for start in stride(from: 0, to: signal.count, by: 512) {
            results.append(signal[start..<start + 512].withUnsafeBufferPointer(analyzer.process))
        }
        #expect(results[0] == nil)
        #expect(results[1] != nil)
        let last = try #require(results.last ?? nil)
        #expect(loudestBin(last) == 64)
    }

    @Test func processUsesTheNewestSamplesOfALargeBuffer() throws {
        let analyzer = try #require(SpectrumAnalyzer(size: 1_024))
        let signal = [Float](repeating: 0, count: 3_000) + sine(frequency: 3_000, amplitude: 0.5, count: 1_024)
        let spectrum = try #require(signal.withUnsafeBufferPointer(analyzer.process))
        #expect(loudestBin(spectrum) == 64)
    }

    @Test func logBandsCoverTheRangeAndKeepMaxima() {
        var decibels = [Float](repeating: -120, count: size / 2)
        decibels[2] = -20 // 23.4 Hz: narrower than one bin at the low end
        decibels[85] = -10 // 996 Hz
        let bands = SpectrumMath.logBands(from: decibels, sampleRate: sampleRate, fftSize: size, count: 48)
        #expect(bands.count == 48)
        #expect(abs(bands[0].lowerFrequency - 20) < 1e-9)
        #expect(abs(bands[47].upperFrequency - 24_000) < 1e-6)
        #expect(zip(bands, bands.dropFirst()).allSatisfy { abs($0.upperFrequency - $1.lowerFrequency) < 1e-6 })
        #expect(bands[0].level == -20)
        let loud = bands.filter { $0.level == -10 }
        #expect(!loud.isEmpty)
        #expect(loud.allSatisfy { $0.lowerFrequency <= 996.1 && $0.upperFrequency >= 996 })
    }

    @Test func decibelConversionHasAFloor() {
        #expect(SpectrumMath.decibels(fromAmplitude: 1) == 0)
        #expect(abs(SpectrumMath.decibels(fromAmplitude: 0.1) + 20) < 1e-9)
        #expect(SpectrumMath.decibels(fromAmplitude: 0) == Double(SpectrumMath.floorDecibels))
    }
}

struct AudioEffectPresetTests {

    @Test func equalizerPresetsFitTheUnit() {
        for setting in EqualizerSetting.allCases { #expect(setting.bands.count <= EqualizerSetting.bandCount, "\(setting)") }
        #expect(EqualizerSetting.flat.bands.isEmpty)
        #expect(EqualizerSetting.telephone.bands == [EQBandSpec(kind: .highPass, frequency: 300), EQBandSpec(kind: .lowPass, frequency: 3_400)])
    }

    @Test func delayPresetsStayInAVAudioUnitDelayRanges() {
        for setting in DelaySetting.allCases {
            guard let parameters = setting.parameters else { #expect(setting == .off); continue }
            #expect((0...2).contains(parameters.time))
            #expect((-100...100).contains(parameters.feedback))
            #expect((10...20_000).contains(parameters.lowPassCutoff))
            #expect((0...100).contains(parameters.wetDryMix))
        }
    }
}
