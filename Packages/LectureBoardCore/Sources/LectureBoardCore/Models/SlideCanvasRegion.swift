import Foundation

/// A validated slide-canvas boundary in top-left normalized window coordinates.
public struct SlideCanvasRegion: Equatable, Hashable, Sendable {
  public let normalizedRect: NormalizedRect

  public init?(x: Double, y: Double, width: Double, height: Double) {
    self.init(
      normalizedRect: NormalizedRect(
        x: x,
        y: y,
        width: width,
        height: height
      )
    )
  }

  public init?(_ normalizedRect: NormalizedRect) {
    self.init(normalizedRect: normalizedRect)
  }

  public init?(normalizedRect: NormalizedRect) {
    let boundaryTolerance = 16 * Double.ulpOfOne
    let values = [
      normalizedRect.x,
      normalizedRect.y,
      normalizedRect.width,
      normalizedRect.height,
    ]
    guard values.allSatisfy(\.isFinite) else { return nil }
    guard
      normalizedRect.x >= 0,
      normalizedRect.y >= 0,
      normalizedRect.width > 0,
      normalizedRect.height > 0,
      normalizedRect.x < 1,
      normalizedRect.y < 1,
      normalizedRect.maxX <= 1 + boundaryTolerance,
      normalizedRect.maxY <= 1 + boundaryTolerance,
      normalizedRect.maxX > normalizedRect.x,
      normalizedRect.maxY > normalizedRect.y
    else {
      return nil
    }

    self.normalizedRect = NormalizedRect(
      x: normalizedRect.x,
      y: normalizedRect.y,
      width: min(normalizedRect.width, 1 - normalizedRect.x),
      height: min(normalizedRect.height, 1 - normalizedRect.y)
    )
  }

  public var isFullFrame: Bool {
    normalizedRect
      == NormalizedRect(x: 0, y: 0, width: 1, height: 1)
  }

  /// Maps the normalized region to source pixels without dropping a touched pixel.
  ///
  /// Minimum edges round down and maximum edges round up. Both are then clamped
  /// to the source dimensions, so the result remains valid at the right and
  /// bottom boundaries even when floating-point multiplication is inexact.
  public func pixelRect(
    sourcePixelWidth: Int,
    sourcePixelHeight: Int
  ) -> SlideCanvasPixelRect? {
    guard sourcePixelWidth > 0, sourcePixelHeight > 0 else { return nil }

    let minimumX = Self.pixelBoundary(
      normalizedRect.x,
      extent: sourcePixelWidth,
      rounding: .down
    )
    let minimumY = Self.pixelBoundary(
      normalizedRect.y,
      extent: sourcePixelHeight,
      rounding: .down
    )
    let maximumX = Self.pixelBoundary(
      normalizedRect.maxX,
      extent: sourcePixelWidth,
      rounding: .up
    )
    let maximumY = Self.pixelBoundary(
      normalizedRect.maxY,
      extent: sourcePixelHeight,
      rounding: .up
    )

    return SlideCanvasPixelRect(
      x: minimumX,
      y: minimumY,
      width: maximumX - minimumX,
      height: maximumY - minimumY,
      sourcePixelWidth: sourcePixelWidth,
      sourcePixelHeight: sourcePixelHeight
    )
  }

  private enum PixelBoundaryRounding {
    case down
    case up
  }

  private static func pixelBoundary(
    _ normalizedValue: Double,
    extent: Int,
    rounding: PixelBoundaryRounding
  ) -> Int {
    guard normalizedValue > 0 else { return 0 }
    guard normalizedValue < 1 else { return extent }

    let scaledValue = normalizedValue * Double(extent)
    let roundedValue: Double
    switch rounding {
    case .down:
      roundedValue = scaledValue.rounded(.down)
    case .up:
      roundedValue = scaledValue.rounded(.up)
    }

    guard roundedValue > 0 else { return 0 }
    guard roundedValue < Double(extent) else { return extent }
    return Int(roundedValue)
  }
}

/// An outward-rounded slide-canvas boundary in top-left source-pixel coordinates.
public struct SlideCanvasPixelRect: Equatable, Hashable, Sendable {
  public let x: Int
  public let y: Int
  public let width: Int
  public let height: Int

  public var maxX: Int { x + width }
  public var maxY: Int { y + height }

  fileprivate init?(
    x: Int,
    y: Int,
    width: Int,
    height: Int,
    sourcePixelWidth: Int,
    sourcePixelHeight: Int
  ) {
    guard
      sourcePixelWidth > 0,
      sourcePixelHeight > 0,
      x >= 0,
      y >= 0,
      width > 0,
      height > 0,
      x <= sourcePixelWidth - width,
      y <= sourcePixelHeight - height
    else {
      return nil
    }

    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}
