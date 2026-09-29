import SwiftUI

struct NaturalLanguageRunView: View {
    @StateObject private var nl = NaturalLanguageExperimentService()

    var body: some View {
        if nl.isSupported {
            Picker("Analysis", selection: $nl.mode) {
                ForEach(NLAnalysisMode.allCases) { Text($0.rawValue).tag($0) }
            }
            if nl.mode != .embeddings {
                TextField("Text to analyze", text: $nl.input, axis: .vertical)
            }
            NLControls(nl: nl)
            Button(nl.isAnalyzing ? "Analyzing…" : "Analyze", systemImage: "text.magnifyingglass", action: nl.analyze)
                .buttonStyle(.borderedProminent)
                .disabled(nl.isAnalyzing || !canAnalyze)
            NLResults(nl: nl)
        }
        OutputView(text: nl.output, isError: nl.isError)
            .task { await nl.loadEmbeddingSupport() }
            // Re-runs when a choice changes (and once on appear); typing only re-runs via the button.
            .task(id: analysisKey) { if canAnalyze { nl.analyze() } }
    }

    private var canAnalyze: Bool {
        nl.mode == .embeddings
            ? !nl.firstTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            : !nl.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var analysisKey: String {
        [nl.mode.rawValue, nl.tokenUnit.rawValue, nl.tagScheme.rawValue, "\(nl.omitPunctuation)", nl.sentimentUnit.rawValue,
         nl.embeddingKind.rawValue, nl.embeddingLanguage, "\(nl.neighborCount)"].joined(separator: "|")
    }
}

private struct NLControls: View {
    @ObservedObject var nl: NaturalLanguageExperimentService

    var body: some View {
        switch nl.mode {
        case .language, .lemmas:
            EmptyView()
        case .tokens:
            Picker("Token unit", selection: $nl.tokenUnit) {
                ForEach(NLTokenUnitOption.allCases) { Text($0.rawValue).tag($0) }
            }
        case .tags:
            Picker("Tag scheme", selection: $nl.tagScheme) {
                ForEach(NLTagSchemeOption.allCases) { Text($0.rawValue).tag($0) }
            }
            Toggle("Omit punctuation", isOn: $nl.omitPunctuation)
        case .sentiment:
            Picker("Score per", selection: $nl.sentimentUnit) {
                ForEach(NLSentimentUnitOption.allCases) { Text($0.rawValue).tag($0) }
            }
        case .embeddings:
            Picker("Embedding", selection: $nl.embeddingKind) {
                ForEach(NLEmbeddingKind.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Language", selection: $nl.embeddingLanguage) {
                if nl.embeddingSupport.isEmpty { Text("English").tag("en") }
                ForEach(nl.embeddingSupport) { Text("\($0.name) · \($0.summary)").tag($0.code) }
            }
            TextField(nl.embeddingKind == .word ? "First word" : "First sentence", text: $nl.firstTerm, axis: .vertical)
            TextField(nl.embeddingKind == .word ? "Second word (distance)" : "Second sentence (distance)", text: $nl.secondTerm, axis: .vertical)
            if nl.embeddingKind == .word {
                Picker("Nearest neighbours", selection: $nl.neighborCount) {
                    ForEach(NaturalLanguageExperimentService.neighborCounts, id: \.self) { Text("\($0)").tag($0) }
                }
            }
        }
    }
}

private struct NLResults: View {
    @ObservedObject var nl: NaturalLanguageExperimentService

    var body: some View {
        switch nl.mode {
        case .language: languageSection
        case .tokens: tokensSection
        case .tags: tagsSection
        case .sentiment: sentimentSection
        case .lemmas: lemmasSection
        case .embeddings: embeddingSections
        }
    }

    @ViewBuilder private var languageSection: some View {
        Section("NLLanguageRecognizer") {
            LabeledContent("Dominant language", value: nl.dominantLanguage.map { "\($0.name) (\($0.code))" } ?? "—")
            ForEach(nl.hypotheses) { guess in
                ScoreRow(title: "\(guess.name) (\(guess.code))", value: guess.probability.formatted(.percent.precision(.fractionLength(1))), fraction: guess.probability, tint: .accentColor)
            }
        }
    }

    @ViewBuilder private var tokensSection: some View {
        Section("Tokens · \(nl.tokens.count)") {
            ForEach(nl.tokens.prefix(200)) { token in
                HStack(alignment: .firstTextBaseline) {
                    Text(token.text).lineLimit(3)
                    Spacer(minLength: 8)
                    ForEach(token.attributes, id: \.self) { Text($0).font(.caption2.weight(.semibold)).foregroundStyle(.orange) }
                    Text("@\(token.offset) · \(token.length)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            if nl.tokens.count > 200 {
                Text("Showing the first 200 of \(nl.tokens.count) tokens.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var tagsSection: some View {
        Section("Tagged tokens · \(nl.taggedTokens.count)") {
            TokenFlowLayout(spacing: 6) {
                ForEach(nl.taggedTokens) { token in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(token.text).font(.callout)
                        Text(token.tag).font(.caption2.weight(.semibold)).foregroundStyle(token.tone.color)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(token.tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(.vertical, 4)
            let entities = NaturalLanguageFormat.entityCounts(nl.taggedTokens)
            if !entities.isEmpty {
                LabeledContent("Named entities", value: entities.map { "\($0.tone.title) ×\($0.count)" }.joined(separator: " · "))
            }
            if !nl.availableSchemes.isEmpty {
                LabeledContent("Schemes for \(nl.dominantLanguage?.name ?? "this language")") {
                    Text(nl.availableSchemes.joined(separator: ", ")).font(.caption).multilineTextAlignment(.trailing)
                }
            }
            if nl.selectedSchemeMissing {
                Button("Request Tagger Assets", systemImage: "arrow.down.circle", action: nl.requestTaggerAssets)
            }
        }
    }

    @ViewBuilder private var sentimentSection: some View {
        Section("sentimentScore (−1 … 1)") {
            if let overall = nl.overallSentiment {
                ScoreRow(title: "Overall · \(NaturalLanguageFormat.sentimentLabel(for: overall))", value: overall.formatted(.number.precision(.fractionLength(2))),
                         fraction: NaturalLanguageFormat.sentimentFraction(for: overall), tint: Self.sentimentColor(overall))
            }
            ForEach(nl.sentiments) { part in
                VStack(alignment: .leading, spacing: 4) {
                    Text(part.text).font(.callout).lineLimit(4)
                    ScoreRow(title: NaturalLanguageFormat.sentimentLabel(for: part.score), value: part.score.formatted(.number.precision(.fractionLength(2))),
                             fraction: NaturalLanguageFormat.sentimentFraction(for: part.score), tint: Self.sentimentColor(part.score))
                }
            }
        }
    }

    @ViewBuilder private var lemmasSection: some View {
        Section("Lemmas · \(nl.lemmas.count)") {
            ForEach(nl.lemmas) { item in
                LabeledContent(item.word) {
                    Text(item.lemma ?? "—")
                        .foregroundStyle(item.lemma == nil ? .secondary : item.lemma?.caseInsensitiveCompare(item.word) == .orderedSame ? .secondary : .primary)
                        .fontWeight(item.lemma.map { $0.caseInsensitiveCompare(item.word) != .orderedSame } == true ? .semibold : .regular)
                }
            }
        }
    }

    @ViewBuilder private var embeddingSections: some View {
        if let report = nl.embeddingReport {
            Section("NLEmbedding") {
                ForEach(report.facts) { LabeledContent($0.title, value: $0.value) }
                if let distance = report.distance {
                    LabeledContent("Cosine distance", value: distance.formatted(.number.precision(.fractionLength(3))))
                    LabeledContent("Cosine similarity", value: NaturalLanguageFormat.cosineSimilarity(fromDistance: distance).formatted(.number.precision(.fractionLength(3))))
                }
                if !report.vectorPreview.isEmpty {
                    LabeledContent("Vector (first \(report.vectorPreview.count))") {
                        Text(report.vectorPreview.map { $0.formatted(.number.precision(.fractionLength(3))) }.joined(separator: ", "))
                            .font(.caption.monospacedDigit())
                            .multilineTextAlignment(.trailing)
                    }
                }
                ForEach(report.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }
            if !report.neighbors.isEmpty {
                Section("Nearest neighbours of “\(nl.firstTerm.lowercased())”") {
                    ForEach(report.neighbors) { neighbor in
                        LabeledContent(neighbor.term, value: neighbor.distance.formatted(.number.precision(.fractionLength(3))))
                    }
                }
            }
        }
        Section("Bundled embeddings per language") {
            if nl.embeddingSupport.isEmpty {
                Text("Checking NLEmbedding revisions…").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(nl.embeddingSupport) { support in
                LabeledContent(support.name) {
                    Text(Self.revisions(support))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(support.wordRevisions.isEmpty && support.sentenceRevisions.isEmpty ? .secondary : .primary)
                }
            }
        }
    }

    private static func revisions(_ support: NLEmbeddingSupport) -> String {
        let word = support.wordRevisions.isEmpty ? "—" : support.wordRevisions.map(String.init).joined(separator: ",")
        let sentence = support.sentenceRevisions.isEmpty ? "—" : support.sentenceRevisions.map(String.init).joined(separator: ",")
        return "word r\(word) · sentence r\(sentence)"
    }

    private static func sentimentColor(_ score: Double) -> Color {
        score >= 0.2 ? .green : score <= -0.2 ? .red : .secondary
    }
}

private struct ScoreRow: View {
    let title: String
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(fraction, 0), 1)).tint(tint)
        }
    }
}

extension NLTagTone {
    var color: Color {
        switch self {
        case .noun, .word: .blue
        case .verb: .green
        case .adjective: .orange
        case .adverb: .yellow
        case .pronoun: .purple
        case .function: .gray
        case .number: .teal
        case .person: .pink
        case .place: .mint
        case .organization: .indigo
        case .punctuation, .whitespace: .secondary
        case .other: .brown
        }
    }
}

/// Wraps chips onto as many rows as needed.
private struct TokenFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
