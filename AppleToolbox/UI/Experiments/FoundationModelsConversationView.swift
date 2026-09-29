import SwiftUI

struct FoundationModelsConversationView: View {
    @StateObject private var chat = FoundationModelsConversationService()

    var body: some View {
        if chat.isSupported {
            Section("Session") {
                LabeledContent("Model", value: chat.availabilityText)
                Picker("Tools", selection: $chat.toolset) {
                    ForEach(FMToolset.allCases) { Text($0.rawValue).tag($0) }
                }
                .disabled(chat.isResponding)
                LabeledContent("Turns in this session", value: "\(chat.turns)")
                if let contextSize = chat.contextSize {
                    ContextGauge(used: chat.transcriptTokens, contextSize: contextSize)
                }
                LabeledContent("Tool schemas", value: chat.toolSchemaTokens.map { "\($0) tokens" } ?? "—")
                if let usage = chat.usageText {
                    LabeledContent("Session usage") { Text(usage).font(.caption.monospacedDigit()).multilineTextAlignment(.trailing) }
                }
            }
            ConversationSection(chat: chat)
            if let failure = chat.failure {
                Section("Error state") {
                    Label(failure.kind.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)
                    Text(failure.kind.explanation).font(.callout)
                    Text(failure.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                    if failure.kind.offersCondensedSession {
                        Button("Continue in Condensed Session", systemImage: "arrow.triangle.branch", action: chat.continueInCondensedSession)
                    }
                }
            }
            TextField("Message", text: $chat.prompt, axis: .vertical)
                .disabled(chat.isResponding)
            if let note = chat.promptLanguageNote {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
            if chat.isResponding {
                Button("Stop Waiting", systemImage: "stop.fill", action: chat.stop)
                    .buttonStyle(.borderedProminent)
                    .experimentSession(chat)
            } else {
                Button("Send", systemImage: "paperplane", action: chat.send)
                    .buttonStyle(.borderedProminent)
                    .disabled(!chat.isModelAvailable || chat.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .experimentSession(chat)
                Button("New Session", systemImage: "arrow.counterclockwise") { chat.resetConversation() }
                    .disabled(!chat.hasSession)
                Button("Send Oversized Prompt", systemImage: "rectangle.stack.badge.plus", action: chat.sendOversizedPrompt)
                    .disabled(!chat.isModelAvailable)
                Text("Sends about six times more text than the context window holds, to show the framework's real context-overflow error.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        OutputView(text: chat.output, isError: chat.isError)
    }
}

private struct ContextGauge: View {
    let used: Int?
    let contextSize: Int

    var body: some View {
        let fraction = FMContextMath.usage(tokens: used ?? 0, contextSize: contextSize)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Transcript tokens")
                Spacer()
                Text("\(used.map(String.init) ?? "—") / \(contextSize)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: fraction).tint(fraction > 0.8 ? .orange : .accentColor)
            Text("tokenCount(for: transcript) against SystemLanguageModel.contextSize")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct ConversationSection: View {
    @ObservedObject var chat: FoundationModelsConversationService

    var body: some View {
        Section("Transcript") {
            if chat.entries.isEmpty && chat.pendingPrompt == nil {
                Text("The session's transcript appears here: instructions with tool definitions, prompts, tool calls with their arguments, tool output and responses.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(chat.entries) { TranscriptBubble(role: $0.role, title: $0.title, text: $0.text) }
            if let pending = chat.pendingPrompt {
                TranscriptBubble(role: .prompt, title: "Prompt · sending", text: pending)
                ForEach(Array(chat.toolActivity.enumerated()), id: \.offset) { _, call in
                    TranscriptBubble(role: .toolCall, title: "Tool call · running", text: call)
                }
                if chat.streamingReply.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Waiting for the model…").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    TranscriptBubble(role: .response, title: "Response · streaming", text: chat.streamingReply)
                }
            }
        }
    }
}

private struct TranscriptBubble: View {
    let role: FMTranscriptEntry.Role
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(tint)
            Text(text.isEmpty ? "(empty)" : text)
                .font(role == .toolCall || role == .toolOutput ? .caption.monospaced() : .callout)
                .lineLimit(role == .toolOutput ? 14 : role == .instructions ? 6 : nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }

    private var symbol: String {
        switch role {
        case .instructions: "doc.text"
        case .prompt: "person.fill"
        case .toolCall: "wrench.and.screwdriver"
        case .toolOutput: "tray.and.arrow.down"
        case .response: "sparkles"
        case .other: "questionmark.square"
        }
    }

    private var tint: Color {
        switch role {
        case .instructions, .other: .secondary
        case .prompt: .blue
        case .toolCall, .toolOutput: .orange
        case .response: .purple
        }
    }
}
