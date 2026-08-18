import Foundation
import ImageLensCore

public typealias WorldPoint = ImageLensCore.WorldPoint
public typealias WorldSize = ImageLensCore.WorldSize
public typealias WorldRect = ImageLensCore.WorldRect

/// A position in the local view coordinate space that renders the canvas.
public struct ViewPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = ViewPoint(x: 0, y: 0)
}

/// A size measured in view points (pixels at a backing scale of one).
public struct ViewSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = ViewSize(width: 0, height: 0)

    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }
}

/// An axis-aligned rectangle in local view coordinates.
public struct ViewRect: Codable, Hashable, Sendable {
    public var origin: ViewPoint
    public var size: ViewSize

    public init(origin: ViewPoint, size: ViewSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(
            origin: ViewPoint(x: x, y: y),
            size: ViewSize(width: width, height: height)
        )
    }

    public static let zero = ViewRect(origin: .zero, size: .zero)
}
