import CoreGraphics
import LectureBoardCore

enum SlideCanvasStatus: Equatable, Sendable {
  case unavailable
  case waitingForFrame
  case needsConfirmation
  case selecting
  case confirmed
  case invalidated
}

/// A bounded, content-free reason for invalidating the slide-canvas boundary.
enum SlideCanvasInvalidationReason: Equatable, Sendable {
  case newFrameSurfaceGeometryUnavailableOrMismatched
  case idleRepeatSurfaceGeometryUnavailableOrMismatched
  case selectionContextMismatch
  case confirmedFrameRejected

  static func surfaceGeometryUnavailableOrMismatched(
    for deliveryKind: CapturedFrameDeliveryKind
  ) -> SlideCanvasInvalidationReason {
    switch deliveryKind {
    case .new:
      return .newFrameSurfaceGeometryUnavailableOrMismatched
    case .idleRepeat:
      return .idleRepeatSurfaceGeometryUnavailableOrMismatched
    }
  }
}

enum SlideCanvasConfirmationMode: Sendable {
  case userConfirmed
  /// Treats only the validated captured-content pixels of the exact PowerPoint window chosen by
  /// the user as the production slide surface. Padding in the stream output remains excluded.
  case automaticCapturedContent
  /// Preserves deterministic whole-frame fixtures without weakening the app default.
  case testOnlyUseFullCapturedFrame
}

/// Builds the production automatic selection from the same inward-rounded content crop used by
/// frame sampling. The normalized representation is accepted only when converting it back through
/// the public slide-canvas rounding contract reproduces that pixel crop exactly.
enum AutomaticSlideCanvasSelection {
  static func region(
    for surfaceGeometry: CaptureSurfaceGeometry
  ) -> SlideCanvasRegion? {
    guard
      let pixelCrop = FrameFingerprintSampler.PixelCrop(
        surfaceGeometry: surfaceGeometry
      )
    else {
      return nil
    }

    let sourcePixelWidth = surfaceGeometry.outputPixelWidth
    let sourcePixelHeight = surfaceGeometry.outputPixelHeight
    let maximumX = pixelCrop.x + pixelCrop.width
    let maximumY = pixelCrop.y + pixelCrop.height

    guard
      let minimumNormalizedX = normalizedMinimumBoundary(
        pixelCrop.x,
        extent: sourcePixelWidth
      ),
      let minimumNormalizedY = normalizedMinimumBoundary(
        pixelCrop.y,
        extent: sourcePixelHeight
      ),
      let maximumNormalizedX = normalizedMaximumBoundary(
        maximumX,
        extent: sourcePixelWidth
      ),
      let maximumNormalizedY = normalizedMaximumBoundary(
        maximumY,
        extent: sourcePixelHeight
      ),
      let region = SlideCanvasRegion(
        x: minimumNormalizedX,
        y: minimumNormalizedY,
        width: maximumNormalizedX - minimumNormalizedX,
        height: maximumNormalizedY - minimumNormalizedY
      ),
      let roundTrip = region.pixelRect(
        sourcePixelWidth: sourcePixelWidth,
        sourcePixelHeight: sourcePixelHeight
      ),
      roundTrip.x == pixelCrop.x,
      roundTrip.y == pixelCrop.y,
      roundTrip.width == pixelCrop.width,
      roundTrip.height == pixelCrop.height,
      SlideCanvasSelectionPolicy.accepts(
        region,
        sourcePixelWidth: sourcePixelWidth,
        sourcePixelHeight: sourcePixelHeight
      )
    else {
      return nil
    }

    return region
  }

  /// Places an interior normalized boundary halfway through the edge pixel. Outward rounding still
  /// selects that entire pixel, while floating-point division cannot expand into adjacent padding.
  private static func normalizedMinimumBoundary(
    _ pixel: Int,
    extent: Int
  ) -> Double? {
    guard extent > 0, pixel >= 0, pixel < extent else { return nil }
    guard pixel > 0 else { return 0 }
    return (Double(pixel) + 0.5) / Double(extent)
  }

  /// Mirrors `normalizedMinimumBoundary` at the trailing edge. The exact outer surface boundary is
  /// retained so a content crop that fills the output surface remains a true full-frame region.
  private static func normalizedMaximumBoundary(
    _ pixel: Int,
    extent: Int
  ) -> Double? {
    guard extent > 0, pixel > 0, pixel <= extent else { return nil }
    guard pixel < extent else { return 1 }
    return (Double(pixel) - 0.5) / Double(extent)
  }
}

enum SlideCanvasSelectionPolicy {
  static let minimumPixelWidth = 32
  static let minimumPixelHeight = 24
  static let minimumPixelArea = 1_024

  static func accepts(
    _ region: SlideCanvasRegion,
    sourcePixelWidth: Int,
    sourcePixelHeight: Int
  ) -> Bool {
    guard
      let pixelRect = region.pixelRect(
        sourcePixelWidth: sourcePixelWidth,
        sourcePixelHeight: sourcePixelHeight
      ),
      pixelRect.width >= minimumPixelWidth,
      pixelRect.height >= minimumPixelHeight,
      pixelRect.width <= Int.max / pixelRect.height,
      pixelRect.width * pixelRect.height >= minimumPixelArea
    else {
      return false
    }

    return true
  }
}

struct SlideCanvasCalibrationSource: @unchecked Sendable {
  let captureOperationID: CaptureOperationID
  let windowID: CGWindowID
  let sequenceNumber: UInt64
  let captureSurfaceGeometry: CaptureSurfaceGeometry
  let image: CGImage

  var pixelWidth: Int { image.width }
  var pixelHeight: Int { image.height }

  init?(
    captureOperationID: CaptureOperationID,
    windowID: CGWindowID,
    sequenceNumber: UInt64,
    captureSurfaceGeometry: CaptureSurfaceGeometry,
    image: CGImage
  ) {
    guard
      windowID != 0,
      captureSurfaceGeometry.outputPixelWidth == image.width,
      captureSurfaceGeometry.outputPixelHeight == image.height
    else {
      return nil
    }

    self.captureOperationID = captureOperationID
    self.windowID = windowID
    self.sequenceNumber = sequenceNumber
    self.captureSurfaceGeometry = captureSurfaceGeometry
    self.image = image
  }
}

enum SlideCanvasDragSelection {
  static func region(
    from start: CGPoint,
    to end: CGPoint,
    in canvasSize: CGSize
  ) -> SlideCanvasRegion? {
    guard
      canvasSize.width.isFinite,
      canvasSize.height.isFinite,
      canvasSize.width > 0,
      canvasSize.height > 0,
      start.x.isFinite,
      start.y.isFinite,
      end.x.isFinite,
      end.y.isFinite
    else {
      return nil
    }

    let clampedStartX = min(max(start.x, 0), canvasSize.width)
    let clampedStartY = min(max(start.y, 0), canvasSize.height)
    let clampedEndX = min(max(end.x, 0), canvasSize.width)
    let clampedEndY = min(max(end.y, 0), canvasSize.height)
    let minimumX = min(clampedStartX, clampedEndX)
    let minimumY = min(clampedStartY, clampedEndY)
    let maximumX = max(clampedStartX, clampedEndX)
    let maximumY = max(clampedStartY, clampedEndY)

    return SlideCanvasRegion(
      NormalizedRect(
        x: Double(minimumX / canvasSize.width),
        y: Double(minimumY / canvasSize.height),
        width: Double((maximumX - minimumX) / canvasSize.width),
        height: Double((maximumY - minimumY) / canvasSize.height)
      )
    )
  }
}
