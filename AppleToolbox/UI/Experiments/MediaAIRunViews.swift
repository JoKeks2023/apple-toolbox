import SwiftUI

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
