import SwiftUI

/// Continuous view-space metrics for content that lives in canvas world space.
/// HUD controls and transient interaction overlays intentionally do not use it.
struct CanvasZoomMetrics {
    let scale: Double

    private var factor: CGFloat { CGFloat(scale) }

    func length(_ base: CGFloat) -> CGFloat {
        base * factor
    }

    func font(
        _ baseSize: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: length(baseSize), weight: weight, design: design)
    }
}
