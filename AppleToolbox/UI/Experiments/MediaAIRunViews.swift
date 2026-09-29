import SwiftUI

struct MusicKitRunView: View {
    @StateObject private var music = MusicExperimentService()

    var body: some View {
        Button("Request MusicKit Authorization", action: music.requestAuthorization).buttonStyle(.borderedProminent)
        OutputView(text: music.output, isError: music.output.localizedCaseInsensitiveContains("denied") || music.output.localizedCaseInsensitiveContains("restricted"))
    }
}

struct SpeechRunView: View {
    @StateObject private var speech = SpeechExperimentService()

    var body: some View {
        Group {
            if speech.isRunning { Button("Stop Speech Recognition", action: speech.stop).buttonStyle(.borderedProminent) }
            else { Button("Start Speech Recognition", action: speech.start).buttonStyle(.borderedProminent) }
        }
        .experimentSession(speech)
        OutputView(text: speech.output, isError: speech.output.localizedCaseInsensitiveContains("error") || speech.output.localizedCaseInsensitiveContains("denied"))
    }
}
