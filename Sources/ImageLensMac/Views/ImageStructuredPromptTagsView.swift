import ImageLensCore
import SwiftUI

/// Eight stable visual-prompt affordances revealed beside an image.
/// Missing categories remain visible but disabled so the spatial vocabulary
/// does not jump between analyses.
struct ImageStructuredPromptTagsView: View {
    let modules: [PromptModule]
    let scale: Double
    let isVisible: Bool
    let coordinateSpaceName: String
    let selectedModuleIDs: Set<PromptModuleID>
    let onHoverChanged: (Bool) -> Void
    let onSelectionToggle: (PromptModuleID) -> Void
    let onDragChanged: (PromptModule, PromptModuleCategory, CGPoint, CGPoint) -> Void
    let onDragEnded: (PromptModule, PromptModuleCategory, CGPoint) -> Void
    let onBundleDragChanged: ([PromptModuleID], CGPoint, CGPoint) -> Void
    let onBundleDragEnded: ([PromptModuleID], CGPoint) -> Void

    var body: some View {
        Group {
            if scale >= 0.55 {
                VStack(alignment: .leading, spacing: tagSpacing) {
                    ForEach(PromptModuleCategory.allCases, id: \.self) { category in
                        let module = module(for: category)
                        StructuredPromptTagView(
                            category: category,
                            module: module,
                            scale: scale,
                            isVisible: isVisible,
                            isSelected: module.map {
                                selectedModuleIDs.contains($0.id)
                            } ?? false,
                            coordinateSpaceName: coordinateSpaceName,
                            onDragActivityChanged: onHoverChanged,
                            onSelectionToggle: onSelectionToggle,
                            onDragChanged: onDragChanged,
                            onDragEnded: onDragEnded
                        )
                    }
                }
                .overlay(alignment: .trailing) {
                    if !selectedModuleIDsInCategoryOrder.isEmpty {
                        StructuredPromptBundleHandle(
                            moduleIDs: selectedModuleIDsInCategoryOrder,
                            scale: scale,
                            coordinateSpaceName: coordinateSpaceName,
                            onDragActivityChanged: onHoverChanged,
                            onDragChanged: onBundleDragChanged,
                            onDragEnded: onBundleDragEnded
                        )
                        .offset(x: 50 * scale)
                        .zIndex(20)
                    }
                }
            } else {
                Label("8 类", systemImage: "square.stack.3d.up")
                    .font(.system(size: 8 * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6 * scale)
                    .padding(.vertical, 4 * scale)
                    .background(.ultraThinMaterial, in: Capsule())
                    .help("放大到 55% 以上以拖动结构化提示词")
            }
        }
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(.easeOut(duration: 0.14), value: isVisible)
        .onHover(perform: onHoverChanged)
        .onDisappear {
            onHoverChanged(false)
        }
    }

    private var tagSpacing: CGFloat { 4 * scale }

    private func module(for category: PromptModuleCategory) -> PromptModule? {
        modules.first {
            $0.category == category
                && !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var selectedModuleIDsInCategoryOrder: [PromptModuleID] {
        PromptModuleCategory.allCases.compactMap { category in
            guard let module = module(for: category),
                  selectedModuleIDs.contains(module.id) else { return nil }
            return module.id
        }
    }
}

private struct StructuredPromptTagView: View {
    let category: PromptModuleCategory
    let module: PromptModule?
    let scale: Double
    let isVisible: Bool
    let isSelected: Bool
    let coordinateSpaceName: String
    let onDragActivityChanged: (Bool) -> Void
    let onSelectionToggle: (PromptModuleID) -> Void
    let onDragChanged: (PromptModule, PromptModuleCategory, CGPoint, CGPoint) -> Void
    let onDragEnded: (PromptModule, PromptModuleCategory, CGPoint) -> Void

    @State private var isHovering = false
    @State private var isPreviewVisible = false
    @GestureState private var isDragging = false

    var body: some View {
        HStack(spacing: 3 * scale) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10 * scale, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
            }

            Text(category.displayName)
                .font(.system(size: fontSize, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(module == nil ? .tertiary : .primary)
        }
            .frame(width: tagWidth, height: tagHeight)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.2)
                    : (isHovering || isDragging
                        ? Color.accentColor.opacity(0.12)
                        : Color.primary.opacity(0.045)),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(
                        isSelected
                            ? Color.accentColor.opacity(0.86)
                            : (isHovering || isDragging
                            ? Color.accentColor.opacity(0.62)
                            : Color.clear),
                        lineWidth: isSelected ? 1.5 * scale : max(0.5, scale)
                    )
            }
            .opacity(module == nil ? 0.55 : 1)
            .contentShape(Capsule())
            .onHover { hovering in
                isHovering = hovering
                isPreviewVisible = hovering && module != nil
            }
            .highPriorityGesture(
                DragGesture(
                    minimumDistance: 4,
                    coordinateSpace: .named(coordinateSpaceName)
                )
                .updating($isDragging) { _, state, _ in
                    state = module != nil
                }
                .onChanged { value in
                    guard let module else { return }
                    isPreviewVisible = false
                    onDragActivityChanged(true)
                    onDragChanged(module, category, value.startLocation, value.location)
                }
                .onEnded { value in
                    guard let module else { return }
                    onDragEnded(module, category, value.location)
                    onDragActivityChanged(false)
                }
            )
            .overlay(alignment: .trailing) {
                if let module {
                    StructuredPromptTagPreview(category: category, module: module)
                        .offset(x: -(tagWidth + 10 * scale))
                        .opacity(isPreviewVisible ? 1 : 0)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(10)
            .animation(.easeOut(duration: 0.12), value: isPreviewVisible)
            .animation(.easeOut(duration: 0.12), value: isSelected)
            .help(
                module == nil
                    ? "本次分析没有生成此分类提示词"
                    : "拖到图片或视频生成节点补充提示词；拖到空白处展开节点"
            )
            .accessibilityLabel("\(category.displayName)提示词")
            .accessibilityValue(module?.content ?? "暂无内容")
            .accessibilityHint(
                module == nil
                    ? "当前不可选择或拖动"
                    : "拖到生成节点补充提示词，或拖到空白处展开节点"
            )
            .onDisappear {
                isPreviewVisible = false
            }
            .onChange(of: isVisible) { _, visible in
                guard !visible else { return }
                isHovering = false
                isPreviewVisible = false
            }
    }

    private var tagWidth: CGFloat { 58 * scale }
    private var tagHeight: CGFloat { 22 * scale }
    private var fontSize: CGFloat { 10 * scale }

}

private struct StructuredPromptBundleHandle: View {
    let moduleIDs: [PromptModuleID]
    let scale: Double
    let coordinateSpaceName: String
    let onDragActivityChanged: (Bool) -> Void
    let onDragChanged: ([PromptModuleID], CGPoint, CGPoint) -> Void
    let onDragEnded: ([PromptModuleID], CGPoint) -> Void

    @GestureState private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3 * scale) {
            Text("\(moduleIDs.count)")
                .monospacedDigit()

            Image(systemName: "arrow.right")
                .accessibilityHidden(true)
        }
        .font(.system(size: 9 * scale, weight: .bold))
        .foregroundStyle(Color.white)
        .frame(width: 34 * scale, height: 22 * scale)
        .background(
            isDragging
                ? Color.accentColor
                : Color.accentColor.opacity(isHovering ? 0.92 : 0.78),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.48), lineWidth: 1 * scale)
        }
        .shadow(color: .black.opacity(0.14), radius: 4 * scale, y: 2 * scale)
        .frame(width: 44 * scale, height: 36 * scale)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .highPriorityGesture(
            DragGesture(
                minimumDistance: 0,
                coordinateSpace: .named(coordinateSpaceName)
            )
            .updating($isDragging) { _, state, _ in
                state = true
            }
            .onChanged { value in
                onDragActivityChanged(true)
                onDragChanged(moduleIDs, value.startLocation, value.location)
            }
            .onEnded { value in
                onDragEnded(moduleIDs, value.location)
                onDragActivityChanged(false)
            }
        )
        .animation(.easeOut(duration: 0.12), value: isDragging)
        .animation(.easeOut(duration: 0.12), value: isHovering)
        .help("结构化提示词输出：已选 \(moduleIDs.count) 项，拖到生图节点以连接")
        .accessibilityLabel("结构化提示词输出")
        .accessibilityValue("已选 \(moduleIDs.count) 项")
        .accessibilityHint("拖到生图节点以批量连接")
    }
}

private struct StructuredPromptTagPreview: View {
    let category: PromptModuleCategory
    let module: PromptModule

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(category.displayName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)

            Text(module.content)
                .font(.callout)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(11)
        .frame(width: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, y: 5)
        .accessibilityHidden(true)
    }
}
