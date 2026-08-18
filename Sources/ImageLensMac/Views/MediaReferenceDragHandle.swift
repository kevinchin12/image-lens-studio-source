import ImageLensCore
import SwiftUI

/// The single reference-output affordance shared by image and video nodes.
/// It stays separate from node-drag surfaces so starting a reference drag
/// cannot accidentally move media or operate video playback controls.
struct MediaReferenceDragHandle: View {
    private static let visibleDiameter = 18.0
    private static let defaultOutsideGap = 6.0
    private static let defaultHoverDiameter = 44.0

    let mediaKind: AssetMediaKind
    let scale: Double
    let coordinateSpaceName: String
    let onDragActivityChanged: (Bool) -> Void
    let onDragChanged: (CGPoint, CGPoint) -> Void
    let onDragEnded: (CGPoint) -> Void
    var hoverDiameter = Self.defaultHoverDiameter
    var minimumHoverDiameter = 34.0

    @GestureState private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        let visibleDiameter = Self.visibleDiameter * scale
        let hoverDiameter = Self.effectiveHoverDiameter(
            scale: scale,
            hoverDiameter: hoverDiameter,
            minimumHoverDiameter: minimumHoverDiameter
        )

        GeometryReader { proxy in
            Color.clear
                .overlay {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: visibleDiameter, height: visibleDiameter)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 8 * scale, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }
                .contentShape(Circle())
                .onHover { hovering in
                    isHovering = hovering
                    onDragActivityChanged(hovering || isDragging)
                }
                .highPriorityGesture(
                    DragGesture(
                        minimumDistance: 0,
                        coordinateSpace: .named(coordinateSpaceName)
                    )
                    .updating($isDragging) { _, state, _ in state = true }
                    .onChanged { value in
                        let frame = proxy.frame(in: .named(coordinateSpaceName))
                        let visibleCenter = CGPoint(
                            x: frame.midX,
                            y: frame.midY
                        )
                        onDragActivityChanged(true)
                        onDragChanged(visibleCenter, value.location)
                    }
                    .onEnded { value in
                        onDragEnded(value.location)
                        onDragActivityChanged(isHovering)
                    }
                )
                .animation(.easeOut(duration: 0.12), value: isDragging)
                .animation(.easeOut(duration: 0.12), value: isHovering)
                .help("拖到图片生成或视频生成节点，作为参考素材")
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint("拖到生成节点，作为参考素材")
        }
        .frame(width: hoverDiameter, height: hoverDiameter)
    }

    private var accessibilityLabel: String {
        mediaKind == .video ? "视频参考输出" : "图片参考输出"
    }

    static func outsideOffset(
        scale: Double,
        hoverDiameter: Double = defaultHoverDiameter,
        outsideGap: Double = defaultOutsideGap
    ) -> CGFloat {
        effectiveHoverDiameter(scale: scale, hoverDiameter: hoverDiameter) / 2
            + (outsideGap + visibleDiameter / 2) * scale
    }

    private static func effectiveHoverDiameter(
        scale: Double,
        hoverDiameter: Double,
        minimumHoverDiameter: Double = 34.0
    ) -> CGFloat {
        max(minimumHoverDiameter, hoverDiameter * scale)
    }
}
