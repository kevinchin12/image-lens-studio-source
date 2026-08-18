/// A position in the canvas's unbounded world coordinate space.
public struct WorldPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = WorldPoint(x: 0, y: 0)
}

/// A size measured in canvas world units.
public struct WorldSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    public static let zero = WorldSize(width: 0, height: 0)

    public var isEmpty: Bool {
        width <= 0 || height <= 0
    }
}

/// An axis-aligned rectangle in canvas world coordinates.
public struct WorldRect: Codable, Hashable, Sendable {
    public var origin: WorldPoint
    public var size: WorldSize

    public init(origin: WorldPoint, size: WorldSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(
            origin: WorldPoint(x: x, y: y),
            size: WorldSize(width: width, height: height)
        )
    }

    public static let zero = WorldRect(origin: .zero, size: .zero)

    public var minX: Double { Swift.min(origin.x, origin.x + size.width) }
    public var minY: Double { Swift.min(origin.y, origin.y + size.height) }
    public var maxX: Double { Swift.max(origin.x, origin.x + size.width) }
    public var maxY: Double { Swift.max(origin.y, origin.y + size.height) }
    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var isEmpty: Bool { width == 0 || height == 0 }

    /// Returns an equivalent rectangle with a minimum origin and non-negative
    /// dimensions. This supports marquee drags in any direction.
    public var standardized: WorldRect {
        WorldRect(x: minX, y: minY, width: width, height: height)
    }

    public func contains(_ point: WorldPoint) -> Bool {
        point.x >= minX && point.x <= maxX
            && point.y >= minY && point.y <= maxY
    }

    public func contains(_ other: WorldRect) -> Bool {
        other.minX >= minX && other.maxX <= maxX
            && other.minY >= minY && other.maxY <= maxY
    }

    /// Edge-only contact is not considered intersection.
    public func intersects(_ other: WorldRect) -> Bool {
        maxX > other.minX && minX < other.maxX
            && maxY > other.minY && minY < other.maxY
    }

    public func insetBy(dx: Double, dy: Double) -> WorldRect {
        WorldRect(
            x: minX + dx,
            y: minY + dy,
            width: width - (2 * dx),
            height: height - (2 * dy)
        )
    }

    public func expanded(by margin: Double) -> WorldRect {
        insetBy(dx: -margin, dy: -margin)
    }
}
