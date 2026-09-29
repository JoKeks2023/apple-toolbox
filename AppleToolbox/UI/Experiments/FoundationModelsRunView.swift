import SwiftUI

struct FoundationModelsRunView: View {
    @StateObject private var model = FoundationModelsExperimentService()

    var body: some View {
        Section("Model availability") {
            ForEach(model.facts) { fact in
                LabeledContent(fact.title) { Text(fact.value).multilineTextAlignment(.trailing) }
            }
            Button("Refresh Availability", systemImage: "arrow.clockwise", action: model.refreshAvailability)
        }
        if !model.execution.isEmpty { AIExecutionSection(facts: model.execution) }
        TextField("Prompt", text: $model.prompt, axis: .vertical)
        Group {
            if model.isGenerating {
                Button("Stop Generating", systemImage: "stop.fill", action: model.stop).buttonStyle(.borderedProminent)
            } else {
                Button("Ask", systemImage: "paperplane", action: model.ask).buttonStyle(.borderedProminent)
                    .disabled(!model.isModelAvailable || model.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button("Generate Structured Result", systemImage: "list.bullet.rectangle", action: model.generateIdea).buttonStyle(.bordered)
                    .disabled(!model.isModelAvailable)
            }
        }
        .experimentSession(model)
        if !model.response.isEmpty {
            Section("Streamed response") { Text(model.response) }
        }
        if let idea = model.idea {
            Section("@Generable ToolboxExperimentIdea") {
                LabeledContent("title: String", value: idea.title)
                LabeledContent("framework: String", value: idea.framework)
                LabeledContent("difficulty: Difficulty", value: idea.difficulty)
                ForEach(Array(idea.steps.enumerated()), id: \.offset) { index, step in
                    LabeledContent("steps[\(index)]") { Text(step).multilineTextAlignment(.trailing) }
                }
            }
        }
        OutputView(text: model.output, isError: model.isError)
    }
}
