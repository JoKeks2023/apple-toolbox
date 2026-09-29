import Testing
import Foundation
@testable import AppleToolbox

@MainActor
struct AudioRecordingTests {

    @Test func formatsMapToExtensionsAndCoreAudioIDs() {
        #expect(AudioRecordingFormat.aac.fileExtension == "m4a")
        #expect(AudioRecordingFormat.alac.fileExtension == "m4a")
        #expect(AudioRecordingFormat.wav.fileExtension == "wav")
        #expect(AudioRecordingFormat.caf.fileExtension == "caf")
        #expect(fourCharacterCode(AudioRecordingFormat.aac.formatID) == "aac ")
        #expect(fourCharacterCode(AudioRecordingFormat.alac.formatID) == "alac")
        #expect(fourCharacterCode(AudioRecordingFormat.wav.formatID) == "lpcm")
    }

    @Test func linearPCMSettingsCarryBitDepthAndFloatFlag() {
        let wav = AudioRecordingFormat.wav.recorderSettings(sampleRate: 44_100, channels: 1)
        #expect(wav["AVLinearPCMBitDepthKey"] as? Int == 16)
        #expect(wav["AVLinearPCMIsFloatKey"] as? Bool == false)
        let caf = AudioRecordingFormat.caf.recorderSettings(sampleRate: 48_000, channels: 2)
        #expect(caf["AVLinearPCMBitDepthKey"] as? Int == 32)
        #expect(caf["AVLinearPCMIsFloatKey"] as? Bool == true)
        #expect(caf["AVSampleRateKey"] as? Double == 48_000)
        #expect(caf["AVNumberOfChannelsKey"] as? Int == 2)
        #expect(AudioRecordingFormat.aac.recorderSettings(sampleRate: 44_100, channels: 1)["AVLinearPCMBitDepthKey"] == nil)
    }

    @Test func fourCharacterCodeFallsBackToDecimalForNonPrintableValues() {
        #expect(fourCharacterCode(0) == "0")
        #expect(fourCharacterCode(7) == "7")
    }

    @Test func queryDurationIsClampedToTheCatalogRange() {
        #expect(ShazamCaptureLength.queryDuration(requested: 5, minimum: 3, maximum: 12) == 5)
        #expect(ShazamCaptureLength.queryDuration(requested: 30, minimum: 3, maximum: 12) == 12)
        #expect(ShazamCaptureLength.queryDuration(requested: 1, minimum: 3, maximum: 12) == 3)
        // An invalid range from the framework leaves the requested value untouched.
        #expect(ShazamCaptureLength.queryDuration(requested: 10, minimum: 0, maximum: 0) == 10)
    }
}
