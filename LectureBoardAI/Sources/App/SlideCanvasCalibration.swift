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

enum SlideCanvasConfirmationMode: Sendable {
  case userConfirmed
  /// Preserves deterministic whole-frame fixtures without weakening the app default.
  case testOnlyUseFullCapturedFrame
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
