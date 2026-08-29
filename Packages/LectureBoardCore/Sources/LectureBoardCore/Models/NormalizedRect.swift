import Foundation

public struct NormalizedRect: Codable, Hashable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var area: Double {
    max(0, width) * max(0, height)
  }

  public var maxX: Double { x + width }
  public var maxY: Double { y + height }

  public func clamped() -> NormalizedRect {
    let minimumX = min(max(x, 0), 1)
    let minimumY = min(max(y, 0), 1)
    let maximumX = min(max(maxX, 0), 1)
    let maximumY = min(max(maxY, 0), 1)
    return NormalizedRect(
      x: minimumX,
      y: minimumY,
      width: max(0, maximumX - minimumX),
      height: max(0, maximumY - minimumY)
    )
  }

  public func intersectionArea(with other: NormalizedRect) -> Double {
    let overlapWidth = max(0, min(maxX, other.maxX) - max(x, other.x))
    let overlapHeight = max(0, min(maxY, other.maxY) - max(y, other.y))
    return overlapWidth * overlapHeight
  }

  public func intersects(_ other: NormalizedRect, tolerance: Double = 0) -> Bool {
    intersectionArea(with: other) > tolerance
  }

  public func inset(by amount: Double) -> NormalizedRect {
    NormalizedRect(
      x: x + amount,
      y: y + amount,
      width: max(0, width - 2 * amount),
      height: max(0, height - 2 * amount)
    )
  }
}
