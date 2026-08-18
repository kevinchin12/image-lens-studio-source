import Foundation

public enum CanvasScrollZoomPolicy {
    /// Converts one command-scroll event into a multiplicative zoom factor.
    /// Positive deltas zoom in and negative deltas zoom out. Clamping the
    /// exponent prevents unusual mouse drivers from producing a single-frame
    /// jump while preserving continuous, reciprocal zoom behavior.
    public static func factor(deltaY: Double, isPrecise: Bool) -> Double? {
        guard deltaY.isFinite, deltaY != 0 else { return nil }

        let boundedDelta: Double
        let sensitivity: Double
        if isPrecise {
            boundedDelta = min(40, max(-40, deltaY))
            sensitivity = 0.012
        } else {
            boundedDelta = min(12, max(-12, deltaY))
            sensitivity = 0.10
        }

        let factor = exp(boundedDelta * sensitivity)
        return factor.isFinite && factor > 0 ? factor : nil
    }
}
