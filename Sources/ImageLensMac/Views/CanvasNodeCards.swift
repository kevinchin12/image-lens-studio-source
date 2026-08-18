import AppKit
import AVFoundation
import ImageLensCanvas
import ImageLensCore
import ImageLensProviders
import SwiftUI

struct CanvasHorizontalScrollRegionPreferenceKey: PreferenceKey {
    static let defaultValue: [CGRect] = []

    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

enum CanvasNodeSelectionAppearance {
    static func strokeColor(isPrimary: Bool, isSelected: Bool) -> Color {
        if isPrimary { return Color.accentColor.opacity(0.58) }
        if isSelected { return Color.accentColor.opacity(0.4) }
        return Color.secondary.opacity(0.22)
    }

    static func lineWidth(isPrimary: Bool, isSelected: Bool, scale: Double) -> CGFloat {
        let width = isPrimary ? 1.5 : (isSelected ? 1.25 : 1)
        return CGFloat(width * scale)
    }
}

private let supportedAspectRatios = ["1:1", "3:2", "4:3", "3:4", "16:9", "9:16"]

private enum CanvasPromptTypography {
    static let bodyFontSize: CGFloat = 10.5
    static let lineSpacing: CGFloat = 5
}

private struct GeneratorReferenceThumbnail: View {
    let session: WorkspaceSession
    let asset: Asset
    let roles: [GeneratorAssetRole]
    let scale: Double
    let onRemove: () -> Void
    let onUseAsGeneralReference: () -> Void

    @State private var isHovering = false

    var body: some View {
        AssetThumbnailView(
            session: session,
            asset: asset,
            size: 40 * scale
        )
        .overlay(alignment: .topTrailing) {
            if asset.isVideo {
                Image(systemName: "film.fill")
                    .font(.system(size: 7 * scale, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(3 * scale)
                    .background(Color.black.opacity(0.58), in: Circle())
                    .offset(x: -2 * scale, y: 2 * scale)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let semanticRoleLabel {
                Text(semanticRoleLabel)
                    .font(.system(size: 6.5 * scale, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 3 * scale)
                    .padding(.vertical, 2 * scale)
                    .background(Color.black.opacity(0.62), in: Capsule())
                    .padding(2 * scale)
            }
        }
        .overlay(alignment: .topTrailing) {
            if isHovering {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 7 * scale, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 15 * scale, height: 15 * scale)
                        .background(Color.black.opacity(0.68), in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 4 * scale, y: -4 * scale)
                .help("移除参考素材")
            }
        }
        .frame(width: 40 * scale, height: 40 * scale, alignment: .center)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .contextMenu {
            if semanticRoleLabel != nil {
                Button("改为整体参考", systemImage: "scope") {
                    onUseAsGeneralReference()
                }
                Divider()
            }
            Button("从当前节点移除", systemImage: "link.badge.minus", role: .destructive) {
                onRemove()
            }
        }
        .help(referenceHelp)
    }

    private var semanticRoleLabel: String? {
        let semanticRoles = roles.filter { $0 != .general }
        guard let first = semanticRoles.first else { return nil }
        let suffix = semanticRoles.count > 1 ? " +\(semanticRoles.count - 1)" : ""
        return "\(first.canvasReferenceTitle)\(suffix)"
    }

    private var referenceHelp: String {
        let roleSummary = roles.map(\.canvasReferenceTitle).joined(separator: "、")
        return roleSummary.isEmpty ? asset.displayName : "\(asset.displayName) · \(roleSummary)"
    }
}

private struct GeneratorOutputThumbnail: View {
    let session: WorkspaceSession
    let asset: Asset
    let scale: Double
    let isSelected: Bool

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        AssetThumbnailView(session: session, asset: asset, size: metrics.length(54))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.length(7), style: .continuous)
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.16),
                    lineWidth: metrics.length(isSelected ? 2 : 1)
                )
        }
        .accessibilityLabel("切换到 \(asset.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct GeneratorOutputRailView: View {
    let session: WorkspaceSession
    let nodeID: CanvasNodeID
    let generatorID: GeneratorID
    let mediaKind: GenerationMediaKind
    let scale: Double
    let coordinateSpaceName: String
    @Binding var selectedOutputAssetID: AssetID?

    @State private var observedLatestGenerationID: GenerationID?

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: metrics.length(8)) {
                    ForEach(allOutputAssets) { asset in
                        Button {
                            session.select(nodeID)
                            selectedOutputAssetID = asset.id
                        } label: {
                            GeneratorOutputThumbnail(
                                session: session,
                                asset: asset,
                                scale: scale,
                                isSelected: selectedOutputAssetID == asset.id
                            )
                        }
                        .buttonStyle(.plain)
                        .help("切换到 \(asset.displayName)")
                        .contextMenu {
                            Button("导出此结果…", systemImage: "square.and.arrow.up") {
                                Task { await AssetExportCoordinator.export(asset.id, from: session) }
                            }
                            Button("在 Finder 中显示", systemImage: "folder") {
                                session.revealAssetInFinder(asset.id)
                            }
                        }
                        .id(asset.id)
                    }
                }
                .frame(height: metrics.length(54), alignment: .leading)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                // Re-selecting the generator recreates this conditional rail.
                // Preserve the currently displayed result when it is still
                // valid instead of jumping back to the newest batch.
                normalizeSelection(preferLatest: false)
                scrollToLatest(using: proxy, animated: false)
            }
            .onChange(of: outputHistorySignature) { _, _ in
                let latestID = outputBatches.last?.id
                let hasNewBatch = latestID != observedLatestGenerationID
                normalizeSelection(preferLatest: hasNewBatch)
                scrollToLatest(using: proxy, animated: true)
            }
        }
        .frame(height: metrics.length(54))
        .contentShape(Rectangle())
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CanvasHorizontalScrollRegionPreferenceKey.self,
                    value: [
                        proxy.frame(in: .named(coordinateSpaceName)).insetBy(
                            dx: -metrics.length(10),
                            dy: -metrics.length(10)
                        )
                    ]
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "历次生成结果，共 \(outputBatches.count) 批、\(allOutputAssets.count) \(mediaKind == .video ? "个视频" : "张图片")"
        )
    }

    private var outputBatches: [GeneratorOutputBatch] {
        session.generationOutputBatches(for: generatorID)
    }

    private var allOutputAssets: [Asset] {
        outputBatches.flatMap(\.assets)
    }

    private var outputHistorySignature: [String] {
        outputBatches.flatMap { batch in
            [batch.id.rawValue.uuidString] + batch.assets.map { $0.id.rawValue.uuidString }
        }
    }

    private func normalizeSelection(preferLatest: Bool) {
        guard let latestBatch = outputBatches.last else {
            selectedOutputAssetID = nil
            observedLatestGenerationID = nil
            return
        }
        defer { observedLatestGenerationID = latestBatch.id }
        if !preferLatest,
           let selectedOutputAssetID,
           allOutputAssets.contains(where: { $0.id == selectedOutputAssetID }) {
            return
        }
        selectedOutputAssetID = latestBatch.assets.first?.id
    }

    private func scrollToLatest(using proxy: ScrollViewProxy, animated: Bool) {
        guard let latestAssetID = allOutputAssets.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(latestAssetID, anchor: .trailing)
            }
        } else {
            proxy.scrollTo(latestAssetID, anchor: .trailing)
        }
    }
}

private struct GeneratorMediaStage: View {
    private struct LoadedOutputImage {
        let assetID: AssetID
        let image: NSImage?
    }

    let session: WorkspaceSession
    let outputAsset: Asset?
    let imageEditGeneratorID: GeneratorID?
    let imageEditMaskIdentity: String?
    let showsImageEditMask: Bool
    let nodeWidth: Double
    let scale: Double
    let isGenerating: Bool
    let mediaKind: GenerationMediaKind

    @State private var loadedOutputImage: LoadedOutputImage?
    @State private var maskImage: NSImage?
    @State private var videoPlayback = VideoPlaybackController()
    @State private var isVideoControlVisible = true
    @State private var videoControlHideTask: Task<Void, Never>?

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        GeometryReader { proxy in
            let available = proxy.size
            let ratio = displayedAspectRatio
            let fitted = fittedSize(in: available, ratio: ratio)

            ZStack {
                RoundedRectangle(cornerRadius: metrics.length(9), style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.9))
                    .overlay {
                        RoundedRectangle(cornerRadius: metrics.length(9), style: .continuous)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: metrics.length(1))
                    }
                    .overlay {
                        if outputAsset?.isVideo == true {
                            ZStack {
                                LocalVideoRenderView(controller: videoPlayback, scale: scale)

                                if videoPlayback.player == nil, let outputImage {
                                    Image(nsImage: outputImage)
                                        .resizable()
                                        .scaledToFit()
                                        .transition(.opacity)
                                }
                            }
                                .clipShape(RoundedRectangle(
                                    cornerRadius: metrics.length(9),
                                    style: .continuous
                                ))
                                .contentShape(Rectangle())
                                .onHover { isHovering in
                                    videoControlHideTask?.cancel()
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        isVideoControlVisible = isHovering || !videoPlayback.isPlaying
                                    }
                                }
                                .onTapGesture { toggleVideoPlayback() }
                                .overlay(alignment: .center) {
                                    if isVideoControlVisible || !videoPlayback.isPlaying {
                                        Image(systemName: videoPlayback.isPlaying ? "pause.fill" : "play.fill")
                                            .font(metrics.font(18, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .frame(width: metrics.length(42), height: metrics.length(42))
                                            .background(Color.black.opacity(0.52), in: Circle())
                                            .allowsHitTesting(false)
                                            .transition(.opacity)
                                    }
                                }
                        } else if let outputImage {
                            ZStack {
                                Image(nsImage: outputImage)
                                    .resizable()
                                    .scaledToFit()

                                if let maskImage, showsImageEditMask {
                                    Image(nsImage: maskImage)
                                        .resizable()
                                        .interpolation(.high)
                                        .scaledToFit()
                                        .colorMultiply(.red)
                                        .blendMode(.screen)
                                        .opacity(0.44)
                                        .allowsHitTesting(false)
                                        .accessibilityHidden(true)
                                }
                            }
                            .clipShape(RoundedRectangle(
                                cornerRadius: metrics.length(9),
                                style: .continuous
                            ))
                        } else {
                            VStack(spacing: metrics.length(7)) {
                                Image(systemName: isGenerating ? "hourglass" : mediaSystemImage)
                                    .font(metrics.font(24, weight: .light))
                                Text(isGenerating ? "正在生成\(mediaTitle)" : "\(mediaTitle)生成画面")
                                    .font(metrics.font(10.5, weight: .medium))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: fitted.width, height: fitted.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: metrics.length(fittedStageHeight))
        .task(id: outputAsset?.id) {
            videoPlayback.stopAndRelease()
            loadedOutputImage = nil
            guard let outputAsset else { return }
            let image: NSImage?
            if outputAsset.isVideo {
                guard let url = try? await session.resolvedAssetURL(for: outputAsset) else { return }
                guard !Task.isCancelled else { return }
                image = await loadVideoPoster(from: url)
            } else {
                let url = session.assetURL(for: outputAsset)
                let data = await loadImageData(from: url)
                guard !Task.isCancelled else { return }
                image = data.flatMap(NSImage.init(data:))
            }
            guard !Task.isCancelled else { return }
            loadedOutputImage = LoadedOutputImage(assetID: outputAsset.id, image: image)
        }
        .task(id: imageEditMaskIdentity) {
            maskImage = nil
            guard let imageEditGeneratorID,
                  imageEditMaskIdentity != nil else { return }
            let data = try? await session.imageEditMaskData(for: imageEditGeneratorID)
            guard !Task.isCancelled else { return }
            maskImage = data.flatMap(NSImage.init(data:))
        }
        .onDisappear {
            videoControlHideTask?.cancel()
            videoPlayback.stopAndRelease()
        }
        .accessibilityElement(children: outputAsset == nil ? .ignore : .contain)
        .accessibilityLabel(
            outputAsset == nil
                ? (isGenerating ? "正在生成\(mediaTitle)" : "空白\(mediaTitle)生成画面")
                : "生成结果 \(outputAsset?.displayName ?? "")"
        )
    }

    private var displayedAspectRatio: CGFloat {
        guard let ratio = outputAsset?.contentAspectRatio, ratio > 0 else {
            return 16.0 / 9.0
        }
        return CGFloat(ratio)
    }

    private var outputImage: NSImage? {
        guard let outputAsset,
              let loadedOutputImage,
              loadedOutputImage.assetID == outputAsset.id else {
            return nil
        }
        return loadedOutputImage.image
    }

    private var fittedStageHeight: Double {
        GeneratorNodeLayoutPolicy.fittedMediaStageHeight(
            nodeWidth: nodeWidth,
            contentAspectRatio: Double(displayedAspectRatio)
        )
    }

    private func fittedSize(in available: CGSize, ratio: CGFloat) -> CGSize {
        let maxWidth = max(metrics.length(80), available.width)
        let maxHeight = max(metrics.length(80), available.height)
        let candidateHeight = maxWidth / ratio
        if candidateHeight <= maxHeight {
            return CGSize(width: maxWidth, height: candidateHeight)
        }
        return CGSize(width: maxHeight * ratio, height: maxHeight)
    }

    private func loadVideoPoster(from url: URL) async -> NSImage? {
        let loadTask = Task.detached(priority: .utility) { () -> NSImage? in
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1_280, height: 1_280)
            guard let frame = try? await generator.image(
                at: CMTime(seconds: 0.1, preferredTimescale: 600)
            ).image else { return nil }
            return NSImage(cgImage: frame, size: .zero)
        }
        return await withTaskCancellationHandler(
            operation: { await loadTask.value },
            onCancel: { loadTask.cancel() }
        )
    }

    private func loadImageData(from url: URL) async -> Data? {
        let loadTask = Task.detached(priority: .utility) {
            try? Data(contentsOf: url, options: [.mappedIfSafe])
        }
        return await withTaskCancellationHandler(
            operation: { await loadTask.value },
            onCancel: { loadTask.cancel() }
        )
    }

    private func toggleVideoPlayback() {
        guard let outputAsset, outputAsset.isVideo else { return }
        Task {
            await videoPlayback.toggle {
                try await session.resolvedAssetURL(for: outputAsset)
            }
            if videoPlayback.isPlaying {
                scheduleVideoControlHide()
            } else {
                videoControlHideTask?.cancel()
                withAnimation(.easeOut(duration: 0.15)) {
                    isVideoControlVisible = true
                }
            }
        }
    }

    private func scheduleVideoControlHide() {
        videoControlHideTask?.cancel()
        isVideoControlVisible = true
        videoControlHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled, videoPlayback.isPlaying else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                isVideoControlVisible = false
            }
        }
    }

    private var mediaTitle: String { mediaKind == .video ? "视频" : "图片" }
    private var mediaSystemImage: String { mediaKind == .video ? "film" : "photo" }

}

struct GeneratorPromptLayout: Equatable {
    static let referenceLineCount = 3
    static let readOnlyLineSpacing = 4.0
    static let readOnlySectionSpacing = 7.0

    static var defaultEditorHeight: Double {
        let font = NSFont.systemFont(ofSize: CanvasPromptTypography.bodyFontSize)
        return Double(ceil(
            font.ascender - font.descender + font.leading
                + CanvasPromptTypography.lineSpacing
        )) * Double(referenceLineCount)
    }

    let fullTextHeight: Double
    let requiredNodeHeight: Double

    init(
        prompt: String,
        leadingReadOnlyLines: [String] = [],
        trailingReadOnlyLines: [String] = [],
        nodeWidth: Double,
        baseNodeHeight: Double
    ) {
        let font = NSFont.systemFont(ofSize: CanvasPromptTypography.bodyFontSize)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = CanvasPromptTypography.lineSpacing
        let lineHeight = ceil(
            font.ascender - font.descender + font.leading
                + CanvasPromptTypography.lineSpacing
        )
        let referenceTextHeight = lineHeight * CGFloat(Self.referenceLineCount)
        let availableWidth = max(1, CGFloat(nodeWidth) - 32)
        let measuredBounds = (prompt as NSString).boundingRect(
            with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraphStyle]
        )
        let measuredTextHeight = max(lineHeight, ceil(measuredBounds.height))
        let readOnlyHeight = Self.readOnlyHeight(
            lines: leadingReadOnlyLines,
            availableWidth: max(1, availableWidth - 30),
            font: font,
            paragraphStyle: paragraphStyle,
            lineHeight: lineHeight
        ) + Self.readOnlyHeight(
            lines: trailingReadOnlyLines,
            availableWidth: max(1, availableWidth - 30),
            font: font,
            paragraphStyle: paragraphStyle,
            lineHeight: lineHeight
        )
        let readOnlySectionCount = [leadingReadOnlyLines, trailingReadOnlyLines]
            .filter { !$0.isEmpty }
            .count

        fullTextHeight = Double(measuredTextHeight)
        requiredNodeHeight = ceil(
            baseNodeHeight
                + Double(max(0, measuredTextHeight - referenceTextHeight))
                + (measuredTextHeight > referenceTextHeight + 1 ? 8 : 0)
                + readOnlyHeight
                + Double(readOnlySectionCount) * Self.readOnlySectionSpacing
        )
    }

    private static func readOnlyHeight(
        lines: [String],
        availableWidth: CGFloat,
        font: NSFont,
        paragraphStyle: NSParagraphStyle,
        lineHeight: CGFloat
    ) -> Double {
        guard !lines.isEmpty else { return 0 }
        let contentHeight = lines.reduce(CGFloat.zero) { partial, line in
            let bounds = (line as NSString).boundingRect(
                with: NSSize(width: availableWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font, .paragraphStyle: paragraphStyle]
            )
            return partial + max(lineHeight, ceil(bounds.height))
        }
        return Double(contentHeight)
            + Double(max(0, lines.count - 1)) * readOnlyLineSpacing
    }
}

private enum CanvasNodeControlStyle {
    case plain
    case secondary
    case prominent
}

/// A control label whose visible chrome belongs to canvas world space.
/// The native Button/Menu still owns actions and menu presentation, while
/// every visible metric here scales continuously with the viewport.
private struct CanvasNodeControlLabel: View {
    let title: String
    let systemImage: String
    var showsChevron = false
    var fillsAvailableWidth = false
    let scale: Double
    let style: CanvasNodeControlStyle

    @Environment(\.isEnabled) private var isEnabled

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        HStack(spacing: metrics.length(4)) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            if showsChevron {
                Image(systemName: "chevron.down")
                    .font(metrics.font(8, weight: .bold))
            }
        }
        .font(metrics.font(11, weight: .semibold))
        .foregroundStyle(style == .prominent ? Color.white : Color.primary)
        .padding(.horizontal, metrics.length(8))
        .frame(
            maxWidth: fillsAvailableWidth ? .infinity : nil,
            minHeight: metrics.length(28),
            maxHeight: metrics.length(28)
        )
        .background {
            RoundedRectangle(cornerRadius: metrics.length(7), style: .continuous)
                .fill(
                    style == .prominent
                        ? Color.accentColor
                        : (style == .secondary ? Color.primary.opacity(0.075) : Color.clear)
                )
        }
        .opacity(isEnabled ? 1 : 0.42)
        .contentShape(RoundedRectangle(cornerRadius: metrics.length(7), style: .continuous))
    }
}

private struct GeneratorSettingsSummaryLabel: View {
    let modelTitle: String
    let aspectRatio: String
    let variationCount: Int
    let mediaKind: GenerationMediaKind
    let videoDurationSeconds: Int?
    let scale: Double

    @Environment(\.isEnabled) private var isEnabled

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        HStack(spacing: metrics.length(8)) {
            Image(systemName: "cpu")
                .font(metrics.font(12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: metrics.length(17))

            VStack(alignment: .leading, spacing: metrics.length(1)) {
                Text(modelTitle)
                    .font(metrics.font(10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(settingsDetail)
                    .font(metrics.font(8.5, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(metrics.font(8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.length(9))
        .frame(
            maxWidth: .infinity,
            minHeight: metrics.length(GeneratorNodeLayoutPolicy.footerHeight),
            maxHeight: metrics.length(GeneratorNodeLayoutPolicy.footerHeight)
        )
        .background {
            RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous)
                .fill(Color.primary.opacity(0.075))
        }
        .opacity(isEnabled ? 1 : 0.42)
        .contentShape(RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous))
    }

    private var settingsDetail: String {
        if let videoDurationSeconds {
            return "\(aspectRatio) · \(videoDurationSeconds) 秒"
        }
        return "\(aspectRatio) · \(variationCount) 张"
    }
}

private struct GeneratorPrimaryActionLabel: View {
    let systemImage: String
    let scale: Double
    let style: CanvasNodeControlStyle

    @Environment(\.isEnabled) private var isEnabled

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        Image(systemName: systemImage)
            .font(metrics.font(15, weight: .semibold))
            .foregroundStyle(style == .prominent ? Color.white : Color.primary)
            .frame(
                width: metrics.length(GeneratorNodeLayoutPolicy.footerHeight),
                height: metrics.length(GeneratorNodeLayoutPolicy.footerHeight),
                alignment: .center
            )
            .background {
                RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous)
                    .fill(
                        style == .prominent
                            ? Color.accentColor
                            : Color.primary.opacity(0.075)
                    )
            }
            .opacity(isEnabled ? 1 : 0.42)
            .contentShape(RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous))
    }
}

private struct GeneratorSectionLabel: View {
    let title: String
    let systemImage: String
    let scale: Double

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(metrics.font(10, weight: .semibold))
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct GeneratorInputSummaryLabel: View {
    let title: String
    let summary: String
    let systemImage: String
    let scale: Double

    @Environment(\.isEnabled) private var isEnabled

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        HStack(spacing: metrics.length(8)) {
            Image(systemName: systemImage)
                .font(metrics.font(11, weight: .medium))
                .frame(width: metrics.length(15))

            VStack(alignment: .leading, spacing: metrics.length(1)) {
                Text(title)
                    .font(metrics.font(10.5, weight: .semibold))
                Text(summary)
                    .font(metrics.font(9.5, weight: .regular))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.down")
                .font(metrics.font(8, weight: .bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, metrics.length(9))
        .frame(
            maxWidth: .infinity,
            minHeight: metrics.length(GeneratorNodeLayoutPolicy.inputRowHeight),
            maxHeight: metrics.length(GeneratorNodeLayoutPolicy.inputRowHeight)
        )
        .background {
            RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous)
                .fill(Color.primary.opacity(0.055))
        }
        .overlay {
            RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous)
                .stroke(Color.secondary.opacity(0.18), lineWidth: metrics.length(1))
        }
        .opacity(isEnabled ? 1 : 0.42)
        .contentShape(RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous))
    }
}

private struct CanvasNodePopoverPanel<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 6)

            Divider()
            content
        }
        .padding(8)
        .frame(minWidth: 220, maxWidth: 300, alignment: .leading)
    }
}

private struct CanvasPopoverActionLabel: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var showsChevron = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .frame(width: 16)
            Text(title)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(Color.accentColor)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

private struct CanvasPopoverActionButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var isActionEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            CanvasPopoverActionLabel(
                title: title,
                systemImage: systemImage,
                isSelected: isSelected
            )
            .background(
                isHovering ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isActionEnabled)
        .opacity(isActionEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }
}

private struct CanvasModelOptionButton: View {
    let title: String
    let summary: String
    var isSelected = false
    var isActionEnabled = true
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "sparkles")
                    .frame(width: 16)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.callout.weight(.medium))
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovering ? Color.accentColor.opacity(0.12) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isActionEnabled)
        .opacity(isActionEnabled ? 1 : 0.45)
        .onHover { isHovering = $0 }
    }
}

private struct CanvasCompactChoiceButton: View {
    let title: String
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    isSelected
                        ? Color.accentColor.opacity(0.14)
                        : Color.primary.opacity(0.055),
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct CanvasPopoverSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 2)
    }
}

private struct CanvasPopoverEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout.weight(.medium))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PromptModuleCanvasNodeView: View {
    let session: WorkspaceSession
    let node: CanvasNode
    let module: PromptModule
    let scale: Double

    @FocusState private var isContentEditorFocused: Bool
    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        let connectedGenerators = session.canvasGenerators.filter(isConnected)
        let removalPresentation = CanvasRemovalPresentation(
            session: session,
            contextualNodeID: node.id
        )

        VStack(alignment: .leading, spacing: metrics.length(8)) {
            HStack(spacing: metrics.length(7)) {
                Image(systemName: module.role.visualCategory == nil ? "text.badge.plus" : "text.quote")
                Text(roleTitle)
                Spacer(minLength: 0)
            }
            .font(metrics.font(11, weight: .semibold))

            promptContent
        }
        .padding(metrics.length(10))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: metrics.length(12)))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.length(12))
                .stroke(
                    CanvasNodeSelectionAppearance.strokeColor(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id)
                    ),
                    lineWidth: CanvasNodeSelectionAppearance.lineWidth(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id),
                        scale: scale
                    )
                )
        }
        .shadow(color: .black.opacity(0.07), radius: 8 * scale, y: 3 * scale)
        .onAppear {
            guard module.content.isEmpty,
                  session.selectedNodeID == node.id else { return }
            isContentEditorFocused = true
        }
        .onChange(of: isContentEditorFocused) { _, isFocused in
            guard isFocused, !session.isNodeSelected(node.id) else { return }
            session.setSelection([node.id], preferredPrimary: node.id)
        }
        .contextMenu {
            connectionContextMenus(connectedGenerators: connectedGenerators)
            if !session.canvasGenerators.isEmpty {
                Divider()
            }
            Button(
                removalPresentation.title,
                systemImage: removalPresentation.systemImage,
                role: .destructive
            ) {
                if !session.isNodeSelected(node.id) { session.select(node.id) }
                session.removeSelectedNodesFromCanvas()
            }
            .help(removalPresentation.help)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("提示词模块 \(roleTitle)")
        .accessibilityAddTraits(session.isNodeSelected(node.id) ? .isSelected : [])
    }

    private var promptContent: some View {
        TextField(
            "编辑\(roleTitle)提示词…",
            text: Binding(
                get: { session.promptModule(for: module.id)?.content ?? "" },
                set: { session.updatePromptModuleContent(id: module.id, content: $0) }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(metrics.font(CanvasPromptTypography.bodyFontSize))
        .lineSpacing(metrics.length(CanvasPromptTypography.lineSpacing))
        .lineLimit(2 ... 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
        .focused($isContentEditorFocused)
        .accessibilityLabel("\(roleTitle)提示词内容")
    }

    @ViewBuilder
    private func connectionContextMenus(connectedGenerators: [Generator]) -> some View {
        if session.canvasGenerators.contains(where: { generator in
            !connectedGenerators.contains { $0.id == generator.id }
        }) {
            Menu("连接到生成节点", systemImage: "link.badge.plus") {
                ForEach(session.canvasGenerators.filter { generator in
                    !connectedGenerators.contains { $0.id == generator.id }
                }) { generator in
                    Button(generator.name) {
                        Task { await session.connect(moduleID: module.id, to: generator.id) }
                    }
                }
            }
        }

        if !connectedGenerators.isEmpty {
            Menu("断开连接", systemImage: "link.badge.minus") {
                ForEach(connectedGenerators) { generator in
                    Button(generator.name) {
                        Task { await session.disconnect(moduleID: module.id, from: generator.id) }
                    }
                }
            }
        }
    }

    private func isConnected(_ generator: Generator) -> Bool {
        session.recipe(for: generator.recipeID)?.bindings.contains {
            $0.moduleID == module.id && $0.isEnabled
        } ?? false
    }

    private var roleTitle: String {
        switch module.role {
        case .visual(let category): category.displayName
        case .instruction: "创作指令"
        }
    }
}

struct TextBlockCanvasNodeView: View {
    let session: WorkspaceSession
    let node: CanvasNode
    let textBlock: TextBlock
    let scale: Double

    @FocusState private var isEditorFocused: Bool
    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }

    var body: some View {
        let removalPresentation = CanvasRemovalPresentation(
            session: session,
            contextualNodeID: node.id
        )

        VStack(alignment: .leading, spacing: metrics.length(8)) {
            Label("备注", systemImage: "note.text")
                .font(metrics.font(11, weight: .semibold))

            TextField(
                "写下备注…",
                text: Binding(
                    get: { session.textBlock(for: textBlock.id)?.text ?? "" },
                    set: { session.updateTextBlock(id: textBlock.id, text: $0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(metrics.font(CanvasPromptTypography.bodyFontSize))
            .lineSpacing(metrics.length(CanvasPromptTypography.lineSpacing))
            .lineLimit(2 ... 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .focused($isEditorFocused)
            .accessibilityLabel("备注内容")

            Text("仅用于画布整理")
                .font(metrics.font(10))
                .foregroundStyle(.secondary)
        }
        .padding(metrics.length(10))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: metrics.length(12)))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.length(12))
                .stroke(
                    CanvasNodeSelectionAppearance.strokeColor(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id)
                    ),
                    lineWidth: CanvasNodeSelectionAppearance.lineWidth(
                        isPrimary: session.selectedNodeID == node.id,
                        isSelected: session.isNodeSelected(node.id),
                        scale: scale
                    )
                )
        }
        .shadow(color: .black.opacity(0.06), radius: 7 * scale, y: 2 * scale)
        .contentShape(Rectangle())
        .onTapGesture {
            session.select(node.id, extending: NSEvent.modifierFlags.contains(.shift))
        }
        .onAppear {
            guard textBlock.text.isEmpty, session.selectedNodeID == node.id else { return }
            isEditorFocused = true
        }
        .contextMenu {
            Button(
                removalPresentation.title,
                systemImage: removalPresentation.systemImage,
                role: .destructive
            ) {
                if !session.isNodeSelected(node.id) { session.select(node.id) }
                session.removeSelectedNodesFromCanvas()
            }
            .help(removalPresentation.help)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("备注")
        .accessibilityAddTraits(session.isNodeSelected(node.id) ? .isSelected : [])
    }
}

struct GeneratorCanvasNodeView: View {
    let session: WorkspaceSession
    let node: CanvasNode
    let generator: Generator
    let scale: Double
    let isResizePreview: Bool
    let coordinateSpaceName: String
    let isReferenceDropTargeted: Bool
    let targetedReferenceIsCompatible: Bool
    let isPromptDropTargeted: Bool
    @Binding var selectedOutputAssetID: AssetID?

    @State private var isGenerationSettingsPopoverPresented = false
    @State private var isPromptModulePopoverPresented = false
    @State private var prefersImageEditSource = false
    @State private var isImageEditMaskVisible = true
    @FocusState private var isPromptEditorFocused: Bool

    private var metrics: CanvasZoomMetrics { CanvasZoomMetrics(scale: scale) }
    var body: some View {
        let preview = generator.promptText
        let compiledPreview = session.compiledPreview(for: generator)
        let effectivePrompt = compiledPreview?.finalText ?? preview
        let structuredInputs = visualStructuredInputs(from: compiledPreview)
        let subjectInputs = structuredInputs.filter { $0.role == .visual(.subject) }
        let trailingInputs = structuredInputs.filter { $0.role != .visual(.subject) }
        let isGenerating = session.isGenerating(generator.id)
        let isGenerationLaneOccupied = !session.activeGenerationGeneratorIDs.isEmpty
        let removalPresentation = CanvasRemovalPresentation(
            session: session,
            contextualNodeID: node.id
        )
        let promptLayout = GeneratorPromptLayout(
            prompt: preview,
            leadingReadOnlyLines: subjectInputs.map(structuredPromptDisplayText),
            trailingReadOnlyLines: trailingInputs.map(structuredPromptDisplayText),
            nodeWidth: node.frame.width,
            baseNodeHeight: fittedBaseNodeHeight
                + (generator.imageEdit == nil
                    ? 0
                    : GeneratorNodeLayoutPolicy.imageEditSupplementaryHeight)
        )
        let requiredNodeHeight = promptLayout.requiredNodeHeight

        VStack(alignment: .leading, spacing: metrics.length(6)) {
            GeneratorMediaStage(
                session: session,
                outputAsset: displayedStageAsset,
                imageEditGeneratorID: generator.imageEdit == nil ? nil : generator.id,
                imageEditMaskIdentity: imageEditMaskIdentity,
                showsImageEditMask: shouldShowImageEditMask,
                nodeWidth: node.frame.width,
                scale: scale,
                isGenerating: isGenerating,
                mediaKind: generator.mediaKind
            )

            VStack(alignment: .leading, spacing: metrics.length(7)) {
                if generator.imageEdit != nil {
                    imageEditSummary
                }

                referenceMediaSection

                if !subjectInputs.isEmpty {
                    structuredPromptSection(subjectInputs)
                }

                promptEditor

                if !trailingInputs.isEmpty {
                    structuredPromptSection(trailingInputs)
                }

                Spacer(minLength: 0)

                HStack(spacing: metrics.length(6)) {
                    generationSettingsMenu
                        .layoutPriority(1)

                    if isGenerating {
                        Button(role: .cancel) {
                            session.cancelGeneration(generatorID: generator.id)
                        } label: {
                            GeneratorPrimaryActionLabel(
                                systemImage: "stop.fill",
                                scale: scale,
                                style: .secondary
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("取消生成")
                    } else {
                        Button {
                            session.startGeneration(generatorID: generator.id)
                        } label: {
                            GeneratorPrimaryActionLabel(
                                systemImage: "arrow.up",
                                scale: scale,
                                style: .prominent
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("生成\(mediaTitle)")
                        .disabled(
                            effectivePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || isGenerationLaneOccupied
                                || !currentModelSupportsReferences
                        )
                        .help(
                            currentModelSupportsReferences
                                ? "立即调用 Gemini 生成\(mediaTitle)"
                                : "当前模型不支持已连接的参考素材"
                        )
                    }
                }
            }
            .padding(metrics.length(8))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(metrics.length(8))
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: metrics.length(14)))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.length(14))
                .stroke(
                    isPromptDropTargeted
                        ? Color.indigo.opacity(0.86)
                        : isReferenceDropTargeted
                        ? targetedReferenceColor
                        : CanvasNodeSelectionAppearance.strokeColor(
                            isPrimary: session.selectedNodeID == node.id,
                            isSelected: session.isNodeSelected(node.id)
                        ),
                    lineWidth: isPromptDropTargeted || isReferenceDropTargeted
                        ? metrics.length(3)
                        : CanvasNodeSelectionAppearance.lineWidth(
                            isPrimary: session.selectedNodeID == node.id,
                            isSelected: session.isNodeSelected(node.id),
                            scale: scale
                        )
                )
        }
        .overlay {
            if isPromptDropTargeted {
                RoundedRectangle(cornerRadius: metrics.length(14))
                    .fill(Color.indigo.opacity(0.08))
                    .allowsHitTesting(false)
            } else if isReferenceDropTargeted {
                RoundedRectangle(cornerRadius: metrics.length(14))
                    .fill(targetedReferenceColor.opacity(0.08))
                    .allowsHitTesting(false)
            }
        }
        .background {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .named(coordinateSpaceName))
                Color.clear
                    .preference(
                        key: CanvasReferenceNodeDropTargetPreferenceKey.self,
                        value: [
                            CanvasReferenceNodeDropTargetFrame(
                                target: CanvasReferenceNodeDropTarget(
                                    generatorID: generator.id,
                                    acceptedMediaKinds: acceptedReferenceMediaKinds
                                ),
                                frame: frame
                            )
                        ]
                    )
                    .preference(
                        key: CanvasPromptNodeDropTargetPreferenceKey.self,
                        value: [
                            CanvasPromptNodeDropTargetFrame(
                                target: CanvasPromptNodeDropTarget(generatorID: generator.id),
                                frame: frame
                            )
                        ]
                    )
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            session.select(node.id, extending: NSEvent.modifierFlags.contains(.shift))
        }
        .contextMenu {
            if isGenerating {
                Button("取消生成", systemImage: "stop.circle", role: .cancel) {
                    session.cancelGeneration(generatorID: generator.id)
                }
            } else {
                Button("生成\(mediaTitle)", systemImage: generator.mediaKind == .video ? "film" : "sparkles") {
                    session.startGeneration(generatorID: generator.id)
                }
                .disabled(
                    effectivePrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || isGenerationLaneOccupied
                        || !currentModelSupportsReferences
                )
            }

            if let edit = generator.imageEdit {
                Divider()
                Button("重新绘制蒙版…", systemImage: "paintbrush.pointed") {
                    session.presentMaskEditor(
                        sourceAssetID: edit.sourceAssetID,
                        generatorID: generator.id
                    )
                }
                .disabled(isGenerating)
                Button("移除局部改图", systemImage: "xmark.circle") {
                    session.removeMaskEdit(from: generator.id)
                }
                .disabled(isGenerating)
            } else if let selectedOutputAsset, selectedOutputAsset.isStillImage {
                Divider()
                Button("基于当前结果局部改图…", systemImage: "paintbrush.pointed") {
                    session.presentMaskEditor(sourceAssetID: selectedOutputAsset.id)
                }
            }

            modelContextMenu.disabled(isGenerating)
            aspectRatioContextMenu.disabled(isGenerating)
            if generator.mediaKind == .video {
                videoDurationContextMenu.disabled(isGenerating)
            } else {
                variationCountContextMenu.disabled(isGenerating)
            }
            referenceImageContextMenus.disabled(isGenerating)

            if let selectedOutputAsset {
                Divider()
                Button("导出当前结果…", systemImage: "square.and.arrow.up") {
                    Task {
                        await AssetExportCoordinator.export(selectedOutputAsset.id, from: session)
                    }
                }
                Button("在 Finder 中显示当前结果", systemImage: "folder") {
                    session.revealAssetInFinder(selectedOutputAsset.id)
                }
            }

            Divider()
            Button(
                removalPresentation.title,
                systemImage: removalPresentation.systemImage,
                role: .destructive
            ) {
                if !session.isNodeSelected(node.id) { session.select(node.id) }
                session.removeSelectedNodesFromCanvas()
            }
            .help(removalPresentation.help)
        }
        .onAppear {
            guard !isResizePreview else { return }
            session.fitCanvasNodeHeight(
                nodeID: node.id,
                height: requiredNodeHeight
            )
        }
        .onChange(of: requiredNodeHeight) { _, requiredHeight in
            guard !isResizePreview else { return }
            session.fitCanvasNodeHeight(
                nodeID: node.id,
                height: requiredHeight
            )
        }
        .onChange(of: selectedOutputAssetID) { _, selectedAssetID in
            guard let sourceAssetID = imageEditSourceAsset?.id,
                  selectedAssetID != sourceAssetID else { return }
            prefersImageEditSource = false
        }
        .onChange(of: imageEditMaskIdentity) { _, _ in
            prefersImageEditSource = false
            isImageEditMaskVisible = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(mediaTitle)生成节点，提示词可直接编辑")
        .accessibilityAddTraits(session.isNodeSelected(node.id) ? .isSelected : [])
    }

    private var promptEditor: some View {
        TextField(
            "描述想生成的内容…",
            text: Binding(
                get: { session.generator(for: generator.id)?.promptText ?? "" },
                set: { session.updateGeneratorPrompt(id: generator.id, text: $0) }
            ),
            axis: .vertical
        )
        .textFieldStyle(.plain)
        .font(metrics.font(CanvasPromptTypography.bodyFontSize))
        .lineSpacing(metrics.length(CanvasPromptTypography.lineSpacing))
        .lineLimit(nil)
        .fixedSize(horizontal: false, vertical: true)
        .frame(
            maxWidth: .infinity,
            minHeight: metrics.length(GeneratorPromptLayout.defaultEditorHeight),
            alignment: .topLeading
        )
        .layoutPriority(1)
        .focused($isPromptEditorFocused)
        .disabled(session.isGenerating(generator.id))
        .accessibilityLabel("\(mediaTitle)生成提示词")
    }

    private var imageEditSummary: some View {
        HStack(spacing: metrics.length(7)) {
            Image(systemName: "paintbrush.pointed.fill")
                .font(metrics.font(10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("局部改图 · Beta")
                .font(metrics.font(9.5, weight: .semibold))
            .layoutPriority(-1)
            Spacer(minLength: 0)

            HStack(spacing: metrics.length(5)) {
                Button(maskVisibilityTitle) {
                    toggleImageEditMaskVisibility()
                }
                .accessibilityLabel(maskVisibilityTitle)

                Button(originalImageToggleTitle) {
                    prefersImageEditSource.toggle()
                }
                .disabled(!hasImageEditResult)
                .accessibilityLabel(originalImageToggleTitle)

                Button("重新绘制") {
                    guard let edit = generator.imageEdit else { return }
                    session.presentMaskEditor(
                        sourceAssetID: edit.sourceAssetID,
                        generatorID: generator.id
                    )
                }
                .disabled(session.isGenerating(generator.id))
            }
            .buttonStyle(.plain)
            .font(metrics.font(9, weight: .medium))
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, metrics.length(7))
        .frame(height: metrics.length(GeneratorNodeLayoutPolicy.imageEditSummaryHeight))
        .background(Color.accentColor.opacity(0.07), in: Capsule())
        .help("Gemini 当前使用语义蒙版，不保证像素级严格锁区")
    }

    private func structuredPromptSection(
        _ inputs: [ModuleInputSnapshot]
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.length(GeneratorPromptLayout.readOnlyLineSpacing)) {
            ForEach(inputs, id: \.moduleID) { input in
                HStack(alignment: .firstTextBaseline, spacing: metrics.length(6)) {
                    Text(structuredPromptTitle(input))
                        .font(metrics.font(9.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: metrics.length(24), alignment: .leading)

                    Text(input.resolvedContent)
                        .font(metrics.font(CanvasPromptTypography.bodyFontSize))
                        .lineSpacing(metrics.length(CanvasPromptTypography.lineSpacing))
                        .foregroundStyle(.primary.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(structuredPromptTitle(input))，只读，\(input.resolvedContent)"
                )
            }
        }
        .help("来自已连接的结构化提示词节点；请在来源节点中编辑")
    }

    private func visualStructuredInputs(
        from snapshot: CompiledPromptSnapshot?
    ) -> [ModuleInputSnapshot] {
        snapshot?.moduleInputs.filter { $0.role.visualCategory != nil } ?? []
    }

    private func structuredPromptTitle(_ input: ModuleInputSnapshot) -> String {
        input.role.visualCategory?.displayName ?? "提示"
    }

    private func structuredPromptDisplayText(_ input: ModuleInputSnapshot) -> String {
        "\(structuredPromptTitle(input))  \(input.resolvedContent)"
    }

    private var fittedBaseNodeHeight: Double {
        let stageHeight = GeneratorNodeLayoutPolicy.fittedMediaStageHeight(
            nodeWidth: node.frame.width,
            contentAspectRatio: displayedStageAsset?.contentAspectRatio
        )
        return session.collapsedGeneratorNodeHeight
            - (GeneratorNodeLayoutPolicy.mediaStageHeight - stageHeight)
    }

    private var generationSettingsMenu: some View {
        Button {
            isGenerationSettingsPopoverPresented.toggle()
        } label: {
            GeneratorSettingsSummaryLabel(
                modelTitle: currentModelDisplayName,
                aspectRatio: generator.parameters.aspectRatio,
                variationCount: normalizedVariationCount,
                mediaKind: generator.mediaKind,
                videoDurationSeconds: generator.mediaKind == .video
                    ? generator.parameters.videoDurationSeconds
                    : nil,
                scale: scale
            )
        }
        .buttonStyle(.plain)
        .frame(height: metrics.length(GeneratorNodeLayoutPolicy.footerHeight))
        .help("设置\(mediaTitle)生成模型、比例和\(generator.mediaKind == .video ? "时长" : "生成数量")")
        .disabled(session.isGenerating(generator.id))
        .accessibilityLabel(
            "\(mediaTitle)生成设置，\(currentModelDisplayName)，"
                + settingsAccessibilityDetail
        )
        .popover(
            isPresented: $isGenerationSettingsPopoverPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .top
        ) {
            CanvasNodePopoverPanel(title: "\(mediaTitle)生成设置") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        CanvasPopoverSectionHeader(title: "模型")

                        if !hasKnownCurrentModel {
                            CanvasModelOptionButton(
                                title: currentTarget.modelID,
                                summary: "当前节点保存的自定义模型 ID",
                                isSelected: true
                            ) {}
                        }

                        modelOptions

                        Divider()

                        CanvasPopoverSectionHeader(title: "\(mediaTitle)比例")
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                            spacing: 6
                        ) {
                            ForEach(supportedAspectRatios, id: \.self) { ratio in
                                CanvasCompactChoiceButton(
                                    title: ratio,
                                    isSelected: generator.parameters.aspectRatio == ratio
                                ) {
                                    session.updateGeneratorAspectRatio(
                                        id: generator.id,
                                        aspectRatio: ratio
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 8)

                        Divider()

                        if generator.mediaKind == .image {
                            CanvasPopoverSectionHeader(title: "生成数量")
                            HStack(spacing: 6) {
                                ForEach(
                                    Array(GenerationParameters.supportedVariationCount),
                                    id: \.self
                                ) { count in
                                    CanvasCompactChoiceButton(
                                        title: "\(count) 张",
                                        isSelected: normalizedVariationCount == count
                                    ) {
                                        session.updateGeneratorVariationCount(
                                            id: generator.id,
                                            count: count
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        } else {
                            CanvasPopoverSectionHeader(title: "视频时长")
                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                                spacing: 6
                            ) {
                                ForEach(
                                    Array(GenerationParameters.supportedVideoDurationSeconds),
                                    id: \.self
                                ) { seconds in
                                    CanvasCompactChoiceButton(
                                        title: "\(seconds) 秒",
                                        isSelected: generator.parameters.videoDurationSeconds == seconds
                                    ) {
                                        session.updateGeneratorVideoDuration(
                                            id: generator.id,
                                            seconds: seconds
                                        )
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                        }
                    }
                }
                .frame(maxHeight: 460)
            }
        }
    }

    private func promptModuleMenu(connectedCount: Int, summary: String) -> some View {
        Button {
            isPromptModulePopoverPresented.toggle()
        } label: {
            CanvasNodeControlLabel(
                title: connectedCount == 0 ? "提示词" : "提示词 \(connectedCount)",
                systemImage: "text.badge.plus",
                showsChevron: true,
                scale: scale,
                style: .plain
            )
        }
        .buttonStyle(.plain)
        .frame(height: metrics.length(GeneratorNodeLayoutPolicy.inputRowHeight))
        .disabled(session.isGenerating(generator.id))
        .help("添加或移除提示词模块")
        .popover(
            isPresented: $isPromptModulePopoverPresented,
            attachmentAnchor: .rect(.bounds),
            arrowEdge: .bottom
        ) {
            CanvasNodePopoverPanel(title: "提示词模块") {
                promptModuleMenuContent
            }
        }
        .accessibilityLabel("提示词节点 \(connectedCount) 个，\(summary)")
    }

    private var referenceMediaSection: some View {
        let assets = generator.uniqueReferenceAssetIDs.compactMap(session.asset(for:))
        return VStack(alignment: .leading, spacing: metrics.length(5)) {
            HStack(spacing: metrics.length(6)) {
                ForEach(Array(assets.prefix(4))) { asset in
                    let roles = generator.assetBindings
                        .filter { $0.assetID == asset.id && $0.isEnabled }
                        .sorted { $0.order < $1.order }
                        .map(\.role)
                    GeneratorReferenceThumbnail(
                        session: session,
                        asset: asset,
                        roles: roles,
                        scale: scale,
                        onRemove: {
                            Task {
                                await session.unbindReferenceAsset(asset.id, from: generator.id)
                            }
                        },
                        onUseAsGeneralReference: {
                            Task {
                                await session.useReferenceAssetAsGeneral(asset.id, for: generator.id)
                            }
                        }
                    )
                }

                if assets.count > 4 {
                    Text("+\(assets.count - 4)")
                        .font(metrics.font(10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: metrics.length(36), height: metrics.length(40))
                } else {
                    RoundedRectangle(cornerRadius: metrics.length(8), style: .continuous)
                        .stroke(
                            Color.secondary.opacity(0.28),
                            style: StrokeStyle(
                                lineWidth: metrics.length(1),
                                dash: [metrics.length(4), metrics.length(3)]
                            )
                        )
                        .overlay {
                            Image(systemName: "plus")
                                .font(metrics.font(12, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: metrics.length(40), height: metrics.length(40))
                }

                if assets.isEmpty {
                    Text(generator.mediaKind == .video ? "拖入图片作为参考" : "拖入图片或视频作为参考")
                        .font(metrics.font(9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: metrics.length(GeneratorNodeLayoutPolicy.referenceStripHeight),
            maxHeight: metrics.length(GeneratorNodeLayoutPolicy.referenceStripHeight),
            alignment: .leading
        )
        .help(
            generator.mediaKind == .video
                ? "把图片右侧的蓝色圆点拖到视频生成节点"
                : "把图片或视频右侧的蓝色圆点拖到图片生成节点"
        )
    }

    private var acceptedReferenceMediaKinds: Set<AssetMediaKind> {
        if generator.mediaKind == .video { return [.image] }
        return currentModelDescriptor?.supportedReferenceMediaKinds ?? [.image]
    }

    private var targetedReferenceColor: Color {
        targetedReferenceIsCompatible ? Color.accentColor : Color.orange
    }

    private var promptModuleMenuContent: some View {
        let candidates = promptModuleCandidates
        let boundOnCanvas = promptModules(for: candidates.boundOnCanvasIDs)
        let boundOffCanvas = promptModules(for: candidates.boundOffCanvasIDs)
        let availableOnCanvas = promptModules(for: candidates.availableOnCanvasIDs)

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                if !boundOnCanvas.isEmpty {
                    CanvasPopoverSectionHeader(title: "已连接")
                    ForEach(boundOnCanvas) { promptModule in
                        connectedPromptModuleButton(promptModule)
                    }
                }

                if !boundOffCanvas.isEmpty {
                    CanvasPopoverSectionHeader(title: "已连接 · 未展开到画板")
                    ForEach(boundOffCanvas) { promptModule in
                        connectedPromptModuleButton(
                            promptModule,
                            titleSuffix: "未展开到画板"
                        )
                    }
                }

                if !availableOnCanvas.isEmpty {
                    CanvasPopoverSectionHeader(title: "当前画板")
                    ForEach(availableOnCanvas) { promptModule in
                        CanvasPopoverActionButton(
                            title: moduleMenuTitle(promptModule),
                            systemImage: "text.badge.plus"
                        ) {
                            isPromptModulePopoverPresented = false
                            Task {
                                await session.connect(
                                    moduleID: promptModule.id,
                                    to: generator.id
                                )
                            }
                        }
                    }
                } else {
                    CanvasPopoverEmptyState(
                        title: "当前画板没有可添加的提示词",
                        message: "新建空白提示词，或从图片拖出结构化标签。"
                    )
                }
            }
        }
        .frame(maxHeight: 420)
    }

    private var aspectRatioContextMenu: some View {
        Menu("\(mediaTitle)比例", systemImage: "aspectratio") {
            ForEach(supportedAspectRatios, id: \.self) { ratio in
                Button {
                    session.updateGeneratorAspectRatio(id: generator.id, aspectRatio: ratio)
                } label: {
                    if generator.parameters.aspectRatio == ratio {
                        Label(ratio, systemImage: "checkmark")
                    } else {
                        Text(ratio)
                    }
                }
            }
        }
    }

    private var variationCountContextMenu: some View {
        Menu("生成数量", systemImage: "square.stack.3d.up") {
            ForEach(variationCountChoices, id: \.self) { count in
                Button {
                    session.updateGeneratorVariationCount(id: generator.id, count: count)
                } label: {
                    if normalizedVariationCount == count {
                        Label("\(count) \(variationUnit)", systemImage: "checkmark")
                    } else {
                        Text("\(count) \(variationUnit)")
                    }
                }
            }
        }
    }

    private var videoDurationContextMenu: some View {
        Menu("视频时长", systemImage: "timer") {
            ForEach(Array(GenerationParameters.supportedVideoDurationSeconds), id: \.self) { seconds in
                Button {
                    session.updateGeneratorVideoDuration(id: generator.id, seconds: seconds)
                } label: {
                    if generator.parameters.videoDurationSeconds == seconds {
                        Label("\(seconds) 秒", systemImage: "checkmark")
                    } else {
                        Text("\(seconds) 秒")
                    }
                }
            }
        }
    }

    private var modelContextMenu: some View {
        Menu("\(mediaTitle)生成模型", systemImage: "cpu") {
            modelContextMenuOptions
        }
    }

    private var currentTarget: CompileTarget {
        session.effectiveGenerationTarget(for: generator)
    }

    private var outputBatches: [GeneratorOutputBatch] {
        session.generationOutputBatches(for: generator.id)
    }

    private var allOutputAssets: [Asset] {
        outputBatches.flatMap(\.assets)
    }

    private var selectedOutputAsset: Asset? {
        if let selectedOutputAssetID,
           let selected = allOutputAssets.first(where: { $0.id == selectedOutputAssetID }) {
            return selected
        }
        return outputBatches.last?.assets.first
    }

    private var imageEditSourceAsset: Asset? {
        generator.imageEdit.flatMap { session.asset(for: $0.sourceAssetID) }
    }

    private var displayedStageAsset: Asset? {
        if prefersImageEditSource, let imageEditSourceAsset {
            return imageEditSourceAsset
        }
        return selectedOutputAsset ?? imageEditSourceAsset
    }

    private var isShowingImageEditSource: Bool {
        guard let imageEditSourceAsset else { return false }
        return displayedStageAsset?.id == imageEditSourceAsset.id
    }

    private var hasImageEditResult: Bool {
        guard let imageEditSourceAsset else { return selectedOutputAsset != nil }
        return selectedOutputAsset?.id != imageEditSourceAsset.id
    }

    private var shouldShowImageEditMask: Bool {
        generator.imageEdit != nil
            && isShowingImageEditSource
            && isImageEditMaskVisible
    }

    private var maskVisibilityTitle: String {
        shouldShowImageEditMask ? "隐藏蒙版" : "显示蒙版"
    }

    private var originalImageToggleTitle: String {
        guard hasImageEditResult else { return "正在查看原图" }
        return isShowingImageEditSource ? "查看结果" : "显示原图"
    }

    private func toggleImageEditMaskVisibility() {
        if isShowingImageEditSource {
            isImageEditMaskVisible.toggle()
        } else {
            prefersImageEditSource = true
            isImageEditMaskVisible = true
        }
    }

    private var imageEditMaskIdentity: String? {
        guard let edit = generator.imageEdit else { return nil }
        return edit.maskContentHash ?? edit.maskRelativePath
    }

    private var normalizedVariationCount: Int {
        if generator.mediaKind == .video { return 1 }
        return GenerationParameters.normalizedVariationCount(generator.parameters.variationCount)
    }

    private var mediaTitle: String { generator.mediaKind == .video ? "视频" : "图片" }
    private var variationUnit: String { generator.mediaKind == .video ? "个" : "张" }
    private var variationCountChoices: [Int] {
        generator.mediaKind == .video ? [1] : Array(GenerationParameters.supportedVariationCount)
    }

    private var settingsAccessibilityDetail: String {
        if generator.mediaKind == .video {
            return "比例 \(generator.parameters.aspectRatio)，时长 \(generator.parameters.videoDurationSeconds) 秒"
        }
        return "比例 \(generator.parameters.aspectRatio)，每次 \(normalizedVariationCount) \(variationUnit)"
    }

    private var supportedAspectRatios: [String] {
        if generator.mediaKind == .video {
            return currentVideoModelDescriptor?.supportedAspectRatios
                ?? uniqueValues(VideoGenerationModelCatalog.gemini.models.flatMap(\.supportedAspectRatios))
        }
        return currentModelDescriptor?.supportedAspectRatios
            ?? uniqueValues(ImageGenerationModelCatalog.geminiModels.flatMap(\.supportedAspectRatios))
    }

    private var currentModelDisplayName: String {
        currentVideoModelDescriptor?.displayName
            ?? currentModelDescriptor?.displayName
            ?? currentTarget.modelID
    }

    private var hasKnownCurrentModel: Bool {
        currentVideoModelDescriptor != nil || currentModelDescriptor != nil
    }

    private var currentModelDescriptor: ImageGenerationModelDescriptor? {
        guard generator.mediaKind == .image else { return nil }
        return ImageGenerationModelCatalog.model(
            providerID: currentTarget.providerID,
            modelID: currentTarget.modelID
        )
    }

    private var currentVideoModelDescriptor: VideoGenerationModelDescriptor? {
        guard generator.mediaKind == .video else { return nil }
        return VideoGenerationModelCatalog.model(
            providerID: currentTarget.providerID,
            modelID: currentTarget.modelID
        )
    }

    private var currentModelSupportsReferences: Bool {
        if let model = currentVideoModelDescriptor {
            return isVideoModelCompatible(model)
        }
        return currentModelDescriptor.map(isModelCompatible) ?? true
    }

    @ViewBuilder
    private var modelOptions: some View {
        if generator.mediaKind == .video {
            ForEach(VideoGenerationModelCatalog.gemini.models, id: \.modelID) { model in
                CanvasModelOptionButton(
                    title: model.displayName,
                    summary: videoModelCompatibilitySummary(model),
                    isSelected: currentTarget.providerID == model.providerID
                        && currentTarget.modelID == model.modelID,
                    isActionEnabled: isVideoModelCompatible(model)
                ) {
                    session.updateGeneratorModel(
                        id: generator.id,
                        providerID: model.providerID,
                        modelID: model.modelID
                    )
                }
            }
        } else {
            ForEach(ImageGenerationModelCatalog.geminiModels, id: \.modelID) { model in
                CanvasModelOptionButton(
                    title: model.displayName,
                    summary: modelCompatibilitySummary(model),
                    isSelected: currentTarget.providerID == model.providerID
                        && currentTarget.modelID == model.modelID,
                    isActionEnabled: isModelCompatible(model)
                ) {
                    session.updateGeneratorModel(
                        id: generator.id,
                        providerID: model.providerID,
                        modelID: model.modelID
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var modelContextMenuOptions: some View {
        if generator.mediaKind == .video {
            ForEach(VideoGenerationModelCatalog.gemini.models, id: \.modelID) { model in
                modelContextMenuButton(
                    title: model.displayName,
                    providerID: model.providerID,
                    modelID: model.modelID,
                    isEnabled: isVideoModelCompatible(model)
                )
            }
        } else {
            ForEach(ImageGenerationModelCatalog.geminiModels, id: \.modelID) { model in
                modelContextMenuButton(
                    title: model.displayName,
                    providerID: model.providerID,
                    modelID: model.modelID,
                    isEnabled: isModelCompatible(model)
                )
            }
        }
    }

    private func modelContextMenuButton(
        title: String,
        providerID: ProviderID,
        modelID: String,
        isEnabled: Bool
    ) -> some View {
        Button {
            session.updateGeneratorModel(
                id: generator.id,
                providerID: providerID,
                modelID: modelID
            )
        } label: {
            if currentTarget.providerID == providerID, currentTarget.modelID == modelID {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
        .disabled(!isEnabled)
    }

    private func isModelCompatible(_ model: ImageGenerationModelDescriptor) -> Bool {
        model.supportedAspectRatios.contains(generator.parameters.aspectRatio)
            && generator.uniqueReferenceAssetCount <= model.maxReferenceImages
            && incompatibleReferenceAssets(for: model).isEmpty
    }

    private func modelCompatibilitySummary(_ model: ImageGenerationModelDescriptor) -> String {
        if !model.supportedAspectRatios.contains(generator.parameters.aspectRatio) {
            return "不支持当前 \(generator.parameters.aspectRatio) 比例"
        }
        if generator.uniqueReferenceAssetCount > model.maxReferenceImages {
            return "最多支持 \(model.maxReferenceImages) 项参考素材"
        }
        if incompatibleReferenceAssets(for: model).contains(where: \.isVideo) {
            return "当前模型不支持视频参考"
        }
        return model.summary
    }

    private func incompatibleReferenceAssets(
        for model: ImageGenerationModelDescriptor
    ) -> [Asset] {
        generator.uniqueReferenceAssetIDs.compactMap(session.asset(for:)).filter {
            !model.supportedReferenceMediaKinds.contains($0.mediaKind)
        }
    }

    private func isVideoModelCompatible(_ model: VideoGenerationModelDescriptor) -> Bool {
        model.supportedAspectRatios.contains(generator.parameters.aspectRatio)
            && generator.uniqueReferenceAssetCount <= model.maxReferenceImages
            && incompatibleReferenceAssets(for: model).isEmpty
    }

    private func videoModelCompatibilitySummary(_ model: VideoGenerationModelDescriptor) -> String {
        if !model.supportedAspectRatios.contains(generator.parameters.aspectRatio) {
            return "不支持当前 \(generator.parameters.aspectRatio) 比例"
        }
        if generator.uniqueReferenceAssetCount > model.maxReferenceImages {
            return "最多支持 \(model.maxReferenceImages) 张参考图"
        }
        if incompatibleReferenceAssets(for: model).contains(where: { !$0.isStillImage }) {
            return "视频生成仅接受图片参考"
        }
        return model.summary
    }

    private func incompatibleReferenceAssets(
        for model: VideoGenerationModelDescriptor
    ) -> [Asset] {
        generator.uniqueReferenceAssetIDs.compactMap(session.asset(for:)).filter {
            !model.supportedReferenceMediaKinds.contains($0.mediaKind)
        }
    }

    @ViewBuilder
    private var promptModuleContextMenus: some View {
        let candidates = promptModuleCandidates
        let availableOnCanvas = promptModules(for: candidates.availableOnCanvasIDs)
        let boundOnCanvas = promptModules(for: candidates.boundOnCanvasIDs)
        let boundOffCanvas = promptModules(for: candidates.boundOffCanvasIDs)

        if !availableOnCanvas.isEmpty {
            Menu("添加提示词模块", systemImage: "text.badge.plus") {
                ForEach(availableOnCanvas) { promptModule in
                    Button(moduleMenuTitle(promptModule)) {
                        Task { await session.connect(moduleID: promptModule.id, to: generator.id) }
                    }
                }
            }
        }

        if !boundOnCanvas.isEmpty || !boundOffCanvas.isEmpty {
            Menu("移除提示词模块", systemImage: "text.badge.minus") {
                ForEach(boundOnCanvas) { promptModule in
                    Button(moduleMenuTitle(promptModule)) {
                        Task { await session.disconnect(moduleID: promptModule.id, from: generator.id) }
                    }
                }
                ForEach(boundOffCanvas) { promptModule in
                    Button("\(moduleMenuTitle(promptModule)) · 未展开到画板") {
                        Task { await session.disconnect(moduleID: promptModule.id, from: generator.id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var referenceImageContextMenus: some View {
        let candidates = referenceAssetCandidates
        let boundOffCanvasIDs = Set(candidates.boundOffCanvasIDs)

        if !generator.assetBindings.isEmpty {
            Menu("移除参考素材", systemImage: "photo.badge.minus") {
                ForEach(generator.assetBindings) { binding in
                    if let asset = session.asset(for: binding.assetID) {
                        Button(
                            [
                                asset.displayName,
                                referenceRoleTitle(binding.role),
                                boundOffCanvasIDs.contains(asset.id) ? "不在画板" : nil
                            ]
                            .compactMap { $0 }
                            .joined(separator: " · ")
                        ) {
                            Task {
                                await session.unbindReferenceAssetBinding(
                                    binding.id,
                                    from: generator.id
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var referenceAssetCandidates: CanvasReferenceAssetCandidates {
        CanvasRelationCandidatePolicy.referenceAssets(
            in: session.workspace,
            generator: generator
        )
    }

    private var promptModuleCandidates: CanvasPromptModuleCandidates {
        guard let recipe = session.recipe(for: generator.recipeID) else {
            return CanvasPromptModuleCandidates(
                availableOnCanvasIDs: [],
                boundOnCanvasIDs: [],
                boundOffCanvasIDs: []
            )
        }
        return CanvasRelationCandidatePolicy.promptModules(
            in: session.workspace,
            recipe: recipe
        )
    }

    private func assets(for ids: [AssetID]) -> [Asset] {
        ids.compactMap(session.asset(for:))
    }

    private func promptModules(for ids: [PromptModuleID]) -> [PromptModule] {
        ids.compactMap(session.promptModule(for:))
    }

    private func connectedPromptModuleButton(
        _ promptModule: PromptModule,
        titleSuffix: String? = nil
    ) -> some View {
        CanvasPopoverActionButton(
            title: [moduleMenuTitle(promptModule), titleSuffix]
                .compactMap { $0 }
                .joined(separator: " · "),
            systemImage: "text.badge.minus",
            isSelected: true
        ) {
            isPromptModulePopoverPresented = false
            Task {
                await session.disconnect(
                    moduleID: promptModule.id,
                    from: generator.id
                )
            }
        }
    }

    private func moduleMenuTitle(_ module: PromptModule) -> String {
        let title: String
        switch module.role {
        case .visual(let category): title = category.displayName
        case .instruction: title = "创作指令"
        }
        let content = module.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return title }
        return "\(title) · \(String(content.prefix(28)))"
    }

    private func referenceRoleTitle(_ role: GeneratorAssetRole) -> String {
        role.canvasReferenceTitle
    }

    private func promptInputSummary(_ modules: [PromptModule]) -> String {
        guard !modules.isEmpty else { return "尚未连接" }
        if modules.count == 1, let module = modules.first {
            return "\(promptRoleTitle(module.role)) · \(compactExcerpt(module.content, limit: 14))"
        }

        let roleTitles = uniqueValues(modules.map { promptRoleTitle($0.role) })
        let roleSummary = summarizedValues(roleTitles, maximumVisibleCount: 2)
        return "共 \(modules.count) 个 · \(roleSummary)"
    }

    private func promptRoleTitle(_ role: PromptModuleRole) -> String {
        switch role {
        case .visual(let category): category.displayName
        case .instruction: "创作指令"
        }
    }

    private func compactExcerpt(_ text: String, limit: Int) -> String {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard normalized.count > limit else { return normalized }
        return "\(normalized.prefix(limit))…"
    }

    private func uniqueValues(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func summarizedValues(_ values: [String], maximumVisibleCount: Int) -> String {
        let visible = values.prefix(maximumVisibleCount).joined(separator: "、")
        let remaining = values.count - min(values.count, maximumVisibleCount)
        return remaining > 0 ? "\(visible)等 \(values.count) 类" : visible
    }
}
