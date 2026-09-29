import SwiftUI
#if os(iOS) || os(macOS)
import PhotosUI
#endif

struct VisionLabRunView: View {
    @StateObject private var vision = VisionLabService()
    #if os(iOS) || os(macOS)
    @State private var pickedItem: PhotosPickerItem?
    #endif

    var body: some View {
        #if os(iOS) || os(macOS)
        Picker("Request", selection: Binding(get: { vision.request }, set: vision.setRequest)) {
            ForEach(VisionLabRequest.allCases) { Text($0.rawValue).tag($0) }
        }
        .experimentSession(vision)
        Picker("Source", selection: Binding(get: { vision.source }, set: vision.setSource)) {
            ForEach(VisionLabSource.allCases) { Text($0.rawValue).tag($0) }
        }
        switch vision.source {
        case .camera:
            #if os(iOS)
            Picker("Camera", selection: Binding(get: { vision.cameraPosition }, set: vision.setCameraPosition)) {
                ForEach(VisionCameraPosition.allCases) { Text($0.rawValue).tag($0) }
            }
            #endif
            HStack {
                Button(vision.isRunning ? "Stop Live Analysis" : "Start Live Analysis", systemImage: vision.isRunning ? "stop.fill" : "camera.viewfinder") {
                    vision.isRunning ? vision.stop() : vision.start()
                }
                .buttonStyle(.borderedProminent)
                if vision.isTracking {
                    Button("Stop Tracking", action: vision.stopTracking).buttonStyle(.bordered)
                }
            }
        case .photo:
            let title = vision.image == nil ? "Choose Photo" : "Choose Another Photo"
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Label(title, systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.borderedProminent)
            .onChange(of: pickedItem) { _, item in load(item) }
        }
        if let image = vision.image {
            VisionImageOverlayView(image: image, analysis: vision.analysis,
                                   selectsTrackingRect: vision.isRunning && vision.request == .tracking,
                                   onSelect: vision.startTracking)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        OutputView(text: vision.output, isError: vision.isError)
        Section("Analysis") {
            LabeledContent("Request") { Text(vision.request.apiName).font(.caption.monospaced()) }
            if let image = vision.image {
                LabeledContent("Analyzed image", value: "\(image.width) × \(image.height)")
            }
            LabeledContent(vision.source == .camera ? "Frames analyzed" : "Runs", value: "\(vision.framesAnalyzed)")
            if let latency = vision.latencyMilliseconds {
                LabeledContent("Latency", value: String(format: "%.0f ms", latency)).monospacedDigit()
            }
            if vision.isAnalyzing {
                ProgressView("Analyzing…")
            }
        }
        Section("Results (\(vision.analysis.rows.count))") {
            if vision.analysis.rows.isEmpty {
                Text(vision.analysis.summary.isEmpty ? "Observations from the selected request appear here." : vision.analysis.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vision.analysis.rows) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.subheadline.weight(.semibold))
                        Text(row.detail).font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                }
            }
        }
        #else
        OutputView(text: vision.output, isError: true)
        #endif
    }

    private var caption: String {
        if vision.request == .tracking {
            return vision.source == .camera ? "Drag a rectangle (or tap) on the live image to choose the object TrackObjectRequest follows." : "Tracking needs consecutive frames from the live camera."
        }
        return vision.source == .camera ? "Each overlay is drawn on the exact frame Vision analyzed; frames arriving meanwhile are dropped." : "The photo is decoded upright (EXIF orientation applied) and capped at 2048 px."
    }

    #if os(iOS) || os(macOS)
    private func load(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    vision.photoLoadFailed("The picked item has no image data.")
                    return
                }
                vision.usePhoto(data)
            } catch {
                vision.photoLoadFailed(error.localizedDescription)
            }
        }
    }
    #endif
}

#if os(iOS) || os(macOS)
private struct VisionImageOverlayView: View {
    let image: CGImage
    let analysis: VisionAnalysis
    let selectsTrackingRect: Bool
    let onSelect: (CGRect) -> Void
    @State private var dragStart: CGPoint?
    @State private var dragEnd: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let imageRect = VisionGeometry.aspectFitRect(imageSize: CGSize(width: image.width, height: image.height), in: proxy.size)
            ZStack(alignment: .topLeading) {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                Canvas { context, _ in
                    for shape in analysis.shapes { Self.draw(shape, in: imageRect, context: &context) }
                }
                if let dragStart, let dragEnd {
                    Rectangle()
                        .stroke(.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: abs(dragEnd.x - dragStart.x), height: abs(dragEnd.y - dragStart.y))
                        .offset(x: min(dragStart.x, dragEnd.x), y: min(dragStart.y, dragEnd.y))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragStart = value.startLocation
                        dragEnd = value.location
                    }
                    .onEnded { value in
                        let start = VisionGeometry.normalizedPoint(value.startLocation, in: imageRect)
                        let end = VisionGeometry.normalizedPoint(value.location, in: imageRect)
                        dragStart = nil
                        dragEnd = nil
                        onSelect(VisionGeometry.selectionRect(from: start, to: end))
                    },
                including: selectsTrackingRect ? .all : .subviews
            )
        }
        .frame(height: 360)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static func draw(_ shape: VisionOverlayShape, in imageRect: CGRect, context: inout GraphicsContext) {
        let points = shape.points.map { VisionGeometry.viewPoint($0, in: imageRect) }
        guard !points.isEmpty else { return }
        let color = color(for: shape.tint)
        switch shape.kind {
        case .polygon, .polyline:
            var path = Path()
            path.addLines(points)
            if shape.kind == .polygon { path.closeSubpath() }
            context.stroke(path, with: .color(color), lineWidth: shape.tint == .secondary ? 1.5 : 2.5)
        case .points:
            for point in points {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)), with: .color(color))
            }
        }
        if let label = shape.label, let top = points.min(by: { $0.y < $1.y }) {
            context.draw(Text(label).font(.caption2.weight(.semibold)).foregroundStyle(color), at: CGPoint(x: top.x, y: top.y - 2), anchor: .bottomLeading)
        }
    }

    private static func color(for tint: VisionOverlayShape.Tint) -> Color {
        switch tint {
        case .primary: .green
        case .secondary: .cyan
        case .tracking: .yellow
        case .lost: .red
        }
    }
}
#endif
