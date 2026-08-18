import ImageLensCore
import SwiftUI

/// The aggregate prompt shown below an image while its hover tools are active.
///
/// Structured modules intentionally do not live here. They are exposed as the
/// independent draggable category tags beside the image.
struct ImageAnalysisSummaryView: View {
    enum Phase {
        case empty
        case analyzing
        case failed(message: String)
        case result(summary: String, modules: [PromptModule])
    }

    let phase: Phase
    let scale: Double
    let isVisible: Bool
    let onRetry: (() -> Void)?
    let onCancel: (() -> Void)?
    let onHoverChanged: (Bool) -> Void

    @State private var isHovering = false

    init(
        phase: Phase,
        scale: Double = 1,
        isVisible: Bool = true,
        onRetry: (() -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onHoverChanged: @escaping (Bool) -> Void = { _ in }
    ) {
        self.phase = phase
        self.scale = scale
        self.isVisible = isVisible
        self.onRetry = onRetry
        self.onCancel = onCancel
        self.onHoverChanged = onHoverChanged
    }

    var body: some View {
        Color.clear
            .overlay(alignment: .topLeading) {
                if scale >= 0.5 {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .onHover { hovering in
                isHovering = hovering
                onHoverChanged(hovering)
            }
            .onChange(of: isVisible) { _, visible in
                guard !visible, isHovering else { return }
                isHovering = false
                onHoverChanged(false)
            }
            .animation(.easeOut(duration: 0.14), value: isVisible)
            .animation(.easeOut(duration: 0.16), value: isHovering)
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .empty:
            if let onRetry {
                Button(action: onRetry) {
                    compactAnalysisLabel(icon: "viewfinder", text: "分析图片")
                }
                .buttonStyle(.plain)
                .help("分析图片并提取提示词")
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                compactAnalysisLabel(icon: "viewfinder", text: "尚未分析")
            }

        case .analyzing:
            HStack(spacing: spacing) {
                ProgressView()
                    .controlSize(.mini)
                Text("正在提取提示词…")
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let onCancel {
                    Button(role: .cancel, action: onCancel) {
                        Image(systemName: "stop.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("取消分析")
                }
            }
            .summaryLabelStyle(fontSize: fontSize, scale: scale)
            .summarySurface(scale: scale)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("正在分析图片并提取提示词")

        case .failed(let message):
            HStack(spacing: spacing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("分析未完成")
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let onRetry {
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                    .help("重新分析")
                }
            }
            .summaryLabelStyle(fontSize: fontSize, scale: scale)
            .summarySurface(scale: scale)
            .help(message.isEmpty ? "暂时无法得到分析结果" : message)

        case .result(let summary, let modules):
            HStack(alignment: .top, spacing: spacing) {
                Image(systemName: "text.quote")
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 1)
                Text(normalizedSummary(summary, modules: modules))
                    .lineLimit(isHovering ? nil : 1)
                    .lineSpacing(3 * scale)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .summaryLabelStyle(fontSize: fontSize, scale: scale)
            .summarySurface(scale: scale)
            .help(isHovering ? "完整汇总提示词" : "移入以展开完整提示词")
            .accessibilityLabel("汇总提示词")
        }
    }

    private func compactAnalysisLabel(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9 * scale, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 8 * scale)
            .padding(.vertical, 4 * scale)
            .background(Color.accentColor.opacity(0.1), in: Capsule())
            .overlay {
                Capsule().stroke(Color.accentColor.opacity(0.35), lineWidth: max(0.5, scale))
            }
    }

    private var fontSize: CGFloat { 11 * scale }
    private var spacing: CGFloat { 8 * scale }

    private func normalizedSummary(_ summary: String, modules: [PromptModule]) -> String {
        let moduleLines = modules
            .map(\.content)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !moduleLines.isEmpty {
            return moduleLines.joined(separator: "\n")
        }

        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.replacingOccurrences(
            of: #"(?<=[。！？.!?])\s*[,，]\s*"#,
            with: "\n",
            options: .regularExpression
        )
    }
}

private extension View {
    func summaryLabelStyle(fontSize: CGFloat, scale: Double) -> some View {
        self
            .font(.system(size: fontSize, weight: .regular))
            .foregroundStyle(.primary)
            .padding(.horizontal, 12 * scale)
            .padding(.vertical, 9 * scale)
    }

    func summarySurface(scale: Double) -> some View {
        self
            .background(
                .regularMaterial,
                in: RoundedRectangle(
                    cornerRadius: 10 * scale,
                    style: .continuous
                )
            )
    }
}
