import AppKit
import ImageLensCore
import SwiftUI

/// Standalone sheet content for painting an image-edit mask.
///
/// The parent owns presentation and persistence. The editor reads the source
/// image URL, keeps all editing state local, and returns an exact-size grayscale
/// PNG where white is the region to regenerate and black is preserved.
struct MaskEditorView: View {
    let sourceImageURL: URL
    let onCancel: () -> Void
    let onCommit: (Data, PixelSize) -> Void

    @State private var sourceImage: NSImage?
    @State private var imagePixelSize = CGSize.zero
    @State private var isLoading = true
    @State private var isRendering = false
    @State private var errorMessage: String?
    @State private var tool: MaskEditorTool = .paint
    @State private var brushDiameterInPixels: CGFloat = 96
    @State private var zoom: CGFloat = 1
    @State private var pan = CGSize.zero
    @State private var editorViewportSize = CGSize.zero
    @State private var strokes: [MaskEditorStroke] = []
    @State private var undoStack: [[MaskEditorStroke]] = []
    @State private var redoStack: [[MaskEditorStroke]] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()
            editorSurface
            Divider()
            footer
        }
        .frame(minWidth: 840, idealWidth: 1040, minHeight: 620, idealHeight: 760)
        .task(id: sourceImageURL) { await loadSourceImage() }
        .alert(
            "无法完成蒙版编辑",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "发生未知错误")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("蒙版局部编辑")
                    .font(.headline)
                Text("红色区域会被重新生成，未涂抹区域保持不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 20)
            Button("取消", action: onCancel)
                .keyboardShortcut(.cancelAction)
            Button {
                renderMask()
            } label: {
                if isRendering {
                    ProgressView()
                        .controlSize(.small)
                        .frame(minWidth: 44)
                } else {
                    Text("使用蒙版")
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canCommitMask)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("工具", selection: $tool) {
                ForEach(MaskEditorTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImage)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)

            Divider().frame(height: 22)

            Label("大小", systemImage: "circle.dashed")
                .font(.callout)
            Slider(
                value: $brushDiameterInPixels,
                in: brushDiameterRange,
                step: max(1, brushDiameterRange.upperBound / 200)
            )
            .frame(width: 150)
            .disabled(tool == .pan || sourceImage == nil)
            Text("\(Int(brushDiameterInPixels.rounded())) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            Divider().frame(height: 22)

            Button("撤销", systemImage: "arrow.uturn.backward", action: undo)
                .labelStyle(.iconOnly)
                .help("撤销上一笔")
                .disabled(undoStack.isEmpty)
            Button("重做", systemImage: "arrow.uturn.forward", action: redo)
                .labelStyle(.iconOnly)
                .help("重做下一笔")
                .disabled(redoStack.isEmpty)
            Button("清空", systemImage: "trash", action: clearMask)
                .labelStyle(.iconOnly)
                .help("清空蒙版，可撤销")
                .disabled(strokes.isEmpty)

            Spacer(minLength: 12)

            Button {
                applyZoom(zoom / 1.2)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .help("缩小")
            .disabled(sourceImage == nil)

            Text("\(Int((zoom * 100).rounded()))%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48)

            Button {
                applyZoom(zoom * 1.2)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .help("放大")
            .disabled(sourceImage == nil)

            Button("适合窗口") {
                zoom = 1
                pan = .zero
            }
            .disabled(sourceImage == nil)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var editorSurface: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if isLoading {
                ProgressView("正在加载原图…")
                    .controlSize(.regular)
            } else if let sourceImage {
                MaskPaintingSurface(
                    sourceImage: sourceImage,
                    imagePixelSize: imagePixelSize,
                    tool: tool,
                    brushDiameterInPixels: brushDiameterInPixels,
                    zoom: $zoom,
                    pan: $pan,
                    strokes: strokes,
                    onViewportSizeChanged: { editorViewportSize = $0 },
                    onCommitStroke: commitStroke
                )
            } else {
                ContentUnavailableView(
                    "无法显示原图",
                    systemImage: "photo.badge.exclamationmark",
                    description: Text("请关闭编辑器并重新选择图片。")
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var canCommitMask: Bool {
        sourceImage != nil && !strokes.isEmpty && !isLoading && !isRendering
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: tool == .pan ? "hand.draw" : "cursorarrow.motionlines")
            Text(
                tool == .pan
                    ? "拖动平移画面；使用触控板捏合或右上角按钮缩放。"
                    : "在图片内拖动涂抹；切换到抓手后可平移画面。"
            )
            Spacer()
            if imagePixelSize.width > 0, imagePixelSize.height > 0 {
                Text("\(Int(imagePixelSize.width)) × \(Int(imagePixelSize.height)) px")
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
    }

    private var brushDiameterRange: ClosedRange<CGFloat> {
        let longestEdge = max(imagePixelSize.width, imagePixelSize.height)
        return 1 ... max(64, longestEdge / 4)
    }

    private func commitStroke(_ stroke: MaskEditorStroke) {
        guard !stroke.points.isEmpty else { return }
        undoStack.append(strokes)
        redoStack.removeAll()
        strokes.append(stroke)
    }

    private func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    private func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
    }

    private func clearMask() {
        guard !strokes.isEmpty else { return }
        undoStack.append(strokes)
        redoStack.removeAll()
        strokes.removeAll()
    }

    private func applyZoom(_ proposedZoom: CGFloat) {
        guard editorViewportSize.width > 0, editorViewportSize.height > 0 else {
            zoom = MaskEditorGeometry.clampedZoom(proposedZoom)
            pan = .zero
            return
        }
        let geometry = MaskEditorGeometry(
            imagePixelSize: imagePixelSize,
            viewportSize: editorViewportSize,
            zoom: zoom,
            pan: pan
        )
        let result = geometry.zoomed(
            to: proposedZoom,
            around: CGPoint(
                x: editorViewportSize.width / 2,
                y: editorViewportSize.height / 2
            )
        )
        zoom = result.zoom
        pan = result.pan
    }

    private func loadSourceImage() async {
        isLoading = true
        sourceImage = nil
        errorMessage = nil
        let sourceURL = sourceImageURL
        let loaded = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
            let accessed = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                return (try Data(contentsOf: sourceURL, options: [.mappedIfSafe]), nil)
            } catch {
                return (nil, error.localizedDescription)
            }
        }.value
        guard !Task.isCancelled else { return }
        defer { isLoading = false }
        guard let data = loaded.0, let decodedImage = NSImage(data: data) else {
            errorMessage = loaded.1 ?? "文件不是可读取的图片。"
            return
        }
        var proposedRect = CGRect(origin: .zero, size: decodedImage.size)
        guard let cgImage = decodedImage.cgImage(
            forProposedRect: &proposedRect,
            context: nil,
            hints: nil
        ) else {
            errorMessage = "无法读取原图像素。"
            return
        }
        let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
        sourceImage = NSImage(cgImage: cgImage, size: pixelSize)
        imagePixelSize = pixelSize
        brushDiameterInPixels = min(
            max(24, min(pixelSize.width, pixelSize.height) * 0.045),
            brushDiameterRange.upperBound
        )
        zoom = 1
        pan = .zero
        strokes.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
    }

    private func renderMask() {
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else { return }
        let imagePixelSize = imagePixelSize
        let strokes = strokes
        isRendering = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, String?) in
                do {
                    return (try MaskPNGRenderer.data(imagePixelSize: imagePixelSize, strokes: strokes), nil)
                } catch {
                    return (nil, error.localizedDescription)
                }
            }.value
            isRendering = false
            if let data = result.0 {
                onCommit(
                    data,
                    PixelSize(
                        width: Int(imagePixelSize.width.rounded()),
                        height: Int(imagePixelSize.height.rounded())
                    )
                )
            } else {
                errorMessage = result.1 ?? "无法输出蒙版。"
            }
        }
    }
}

private struct MaskPaintingSurface: View {
    let sourceImage: NSImage
    let imagePixelSize: CGSize
    let tool: MaskEditorTool
    let brushDiameterInPixels: CGFloat
    @Binding var zoom: CGFloat
    @Binding var pan: CGSize
    let strokes: [MaskEditorStroke]
    let onViewportSizeChanged: (CGSize) -> Void
    let onCommitStroke: (MaskEditorStroke) -> Void

    @State private var activeStroke: MaskEditorStroke?
    @State private var panAtGestureStart: CGSize?
    @State private var lastMagnification: CGFloat = 1
    @State private var hoverLocation: CGPoint?

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let geometry = MaskEditorGeometry(
                imagePixelSize: imagePixelSize,
                viewportSize: viewportSize,
                zoom: zoom,
                pan: pan
            )

            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Color.black.opacity(0.16))
                    .frame(width: geometry.imageRect.width, height: geometry.imageRect.height)
                    .offset(x: geometry.imageRect.minX, y: geometry.imageRect.minY)

                Image(nsImage: sourceImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: geometry.imageRect.width, height: geometry.imageRect.height)
                    .offset(x: geometry.imageRect.minX, y: geometry.imageRect.minY)

                maskOverlay(geometry: geometry, viewportSize: viewportSize)

                if let hoverLocation,
                   tool != .pan,
                   geometry.imageRect.contains(hoverLocation) {
                    Circle()
                        .strokeBorder(.white, lineWidth: 1)
                        .background(Circle().stroke(.black.opacity(0.7), lineWidth: 2))
                        .frame(
                            width: max(2, brushDiameterInPixels * geometry.displayScale),
                            height: max(2, brushDiameterInPixels * geometry.displayScale)
                        )
                        .position(hoverLocation)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: viewportSize.width, height: viewportSize.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverLocation = location
                case .ended: hoverLocation = nil
                }
            }
            .gesture(dragGesture(geometry: geometry))
            .simultaneousGesture(magnificationGesture(geometry: geometry))
            .onAppear { onViewportSizeChanged(viewportSize) }
            .onChange(of: viewportSize) { _, _ in
                onViewportSizeChanged(viewportSize)
                pan = geometry.constrainedPan(pan)
            }
        }
    }

    private func maskOverlay(
        geometry: MaskEditorGeometry,
        viewportSize: CGSize
    ) -> some View {
        Canvas { context, _ in
            context.clip(to: Path(geometry.imageRect))
            // Paint and erase must share one compositing layer. Applying
            // destination-out in a fresh layer per stroke would only erase that
            // empty temporary layer instead of the previously painted preview.
            context.drawLayer { layer in
                for stroke in strokes {
                    draw(stroke, in: &layer, geometry: geometry)
                }
                if let activeStroke {
                    draw(activeStroke, in: &layer, geometry: geometry)
                }
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height)
        .allowsHitTesting(false)
    }

    private func dragGesture(geometry: MaskEditorGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                hoverLocation = value.location
                if tool == .pan {
                    if panAtGestureStart == nil { panAtGestureStart = pan }
                    let origin = panAtGestureStart ?? pan
                    pan = geometry.constrainedPan(
                        CGSize(
                            width: origin.width + value.translation.width,
                            height: origin.height + value.translation.height
                        )
                    )
                    return
                }

                guard let point = geometry.imagePoint(fromViewPoint: value.location) else { return }
                let mode: MaskEditorStroke.Mode = tool == .erase ? .erase : .paint
                if activeStroke == nil {
                    activeStroke = MaskEditorStroke(
                        mode: mode,
                        diameterInPixels: brushDiameterInPixels,
                        points: [point]
                    )
                    return
                }
                guard let last = activeStroke?.points.last else { return }
                let samplingDistance = max(0.75, brushDiameterInPixels * 0.018)
                guard hypot(point.x - last.x, point.y - last.y) >= samplingDistance else { return }
                activeStroke?.points.append(point)
            }
            .onEnded { _ in
                panAtGestureStart = nil
                guard tool != .pan, let stroke = activeStroke else {
                    activeStroke = nil
                    return
                }
                activeStroke = nil
                onCommitStroke(stroke)
            }
    }

    private func magnificationGesture(geometry: MaskEditorGeometry) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let incremental = value / max(0.001, lastMagnification)
                let anchor = hoverLocation ?? CGPoint(
                    x: geometry.viewportSize.width / 2,
                    y: geometry.viewportSize.height / 2
                )
                let result = geometry.zoomed(to: zoom * incremental, around: anchor)
                zoom = result.zoom
                pan = result.pan
                lastMagnification = value
            }
            .onEnded { _ in lastMagnification = 1 }
    }

    private func draw(
        _ stroke: MaskEditorStroke,
        in context: inout GraphicsContext,
        geometry: MaskEditorGeometry
    ) {
        guard let first = stroke.points.first else { return }
        let width = max(1, stroke.diameterInPixels * geometry.displayScale)
        let color = Color.red.opacity(0.42)
        let firstViewPoint = geometry.viewPoint(fromImagePoint: first)

        context.blendMode = stroke.mode == .erase ? .destinationOut : .normal
        if stroke.points.count == 1 {
            context.fill(
                Path(
                    ellipseIn: CGRect(
                        x: firstViewPoint.x - width / 2,
                        y: firstViewPoint.y - width / 2,
                        width: width,
                        height: width
                    )
                ),
                with: .color(stroke.mode == .erase ? .black : color)
            )
            context.blendMode = .normal
            return
        }

        var path = Path()
        path.move(to: firstViewPoint)
        for point in stroke.points.dropFirst() {
            path.addLine(to: geometry.viewPoint(fromImagePoint: point))
        }
        context.stroke(
            path,
            with: .color(stroke.mode == .erase ? .black : color),
            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        )
        context.blendMode = .normal
    }
}
