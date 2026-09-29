import SwiftUI

struct RoomPlanRunView: View {
    @StateObject private var room = RoomPlanExperimentService()

    var body: some View {
        Button("Start Room Capture", systemImage: "cube.transparent", action: room.startCapture)
            .buttonStyle(.borderedProminent)
            .disabled(!room.isSupported || room.isActive)
            .experimentSession(room)
            #if canImport(RoomPlan) && os(iOS)
            .experimentFullScreenCover(isPresented: Binding(get: { room.isPresentingCapture }, set: { if !$0 { room.cancelCapture() } })) {
                RoomCaptureScreen(room: room)
            }
            #endif
        if let summary = room.summary {
            RoomSummaryView(summary: summary)
        }
        #if !os(tvOS)
        if let exportURL = room.exportURL {
            ShareLink(item: exportURL, preview: SharePreview(exportURL.lastPathComponent)) {
                Label("Share USDZ Model", systemImage: "square.and.arrow.up")
            }
        }
        #endif
        OutputView(text: room.output, isError: [.unavailable, .permissionDenied, .hardwareUnsupported, .platformUnsupported].contains(room.status))
    }
}

private struct RoomSummaryView: View {
    let summary: RoomScanSummary

    var body: some View {
        Section("Captured room") {
            ForEach(summary.rows) { LabeledContent($0.title, value: $0.value) }
        }
        Section("Objects (\(summary.objects.count) categories)") {
            if summary.objects.isEmpty {
                Text("RoomPlan detected no furniture or appliances.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.objects) { LabeledContent($0.title, value: $0.value) }
            }
        }
    }
}

#if canImport(RoomPlan) && os(iOS)
private struct RoomCaptureScreen: View {
    @ObservedObject var room: RoomPlanExperimentService

    var body: some View {
        RoomCaptureContainer(room: room)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                HStack {
                    if room.phase != .finished {
                        Button("Cancel", role: .cancel, action: room.cancelCapture).buttonStyle(.bordered)
                    }
                    Spacer()
                    switch room.phase {
                    case .scanning:
                        Button("Done", action: room.finishScanning).buttonStyle(.borderedProminent)
                    case .processing:
                        ProgressView("Processing").padding(.horizontal)
                    case .finished, .idle:
                        Button("Done", action: room.closeCapture).buttonStyle(.borderedProminent)
                    }
                }
                .controlSize(.large)
                .padding()
            }
    }
}

private struct RoomCaptureContainer: UIViewRepresentable {
    let room: RoomPlanExperimentService

    func makeUIView(context: Context) -> UIView { room.makeCaptureView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
