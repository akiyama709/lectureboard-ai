import CoreGraphics

/// One validated bridge between Quartz's global top-left display coordinates
/// and AppKit's global bottom-left window coordinates.
struct DisplayCoordinateSnapshot: Equatable, Sendable {
  let displayID: CGDirectDisplayID

  private let quartzOriginX: Double
  private let quartzOriginY: Double
  private let quartzWidth: Double
  private let quartzHeight: Double
  private let appKitOriginX: Double
  private let appKitOriginY: Double
  private let appKitWidth: Double
  private let appKitHeight: Double

  init?(
    displayID: CGDirectDisplayID,
    quartzGlobalFrame: CGRect,
    appKitFrame: CGRect
  ) {
    let quartzRawWidth = Double(quartzGlobalFrame.size.width)
    let quartzRawHeight = Double(quartzGlobalFrame.size.height)
    let appKitRawWidth = Double(appKitFrame.size.width)
    let appKitRawHeight = Double(appKitFrame.size.height)
    let values = [
      Double(quartzGlobalFrame.origin.x),
      Double(quartzGlobalFrame.origin.y),
      quartzRawWidth,
      quartzRawHeight,
      Double(quartzGlobalFrame.origin.x) + quartzRawWidth,
      Double(quartzGlobalFrame.origin.y) + quartzRawHeight,
      Double(appKitFrame.origin.x),
      Double(appKitFrame.origin.y),
      appKitRawWidth,
      appKitRawHeight,
      Double(appKitFrame.origin.x) + appKitRawWidth,
      Double(appKitFrame.origin.y) + appKitRawHeight,
    ]
    guard
      displayID != 0,
      values.allSatisfy(\.isFinite),
      quartzRawWidth > 0,
      quartzRawHeight > 0,
      appKitRawWidth > 0,
      appKitRawHeight > 0
    else {
      return nil
    }

    self.displayID = displayID
    quartzOriginX = Double(quartzGlobalFrame.origin.x)
    quartzOriginY = Double(quartzGlobalFrame.origin.y)
    quartzWidth = quartzRawWidth
    quartzHeight = quartzRawHeight
    appKitOriginX = Double(appKitFrame.origin.x)
    appKitOriginY = Double(appKitFrame.origin.y)
    appKitWidth = appKitRawWidth
    appKitHeight = appKitRawHeight
  }

  var quartzGlobalFrame: CGRect {
    CGRect(
      x: quartzOriginX,
      y: quartzOriginY,
      width: quartzWidth,
      height: quartzHeight
    )
  }

  var appKitFrame: CGRect {
    CGRect(
      x: appKitOriginX,
      y: appKitOriginY,
      width: appKitWidth,
      height: appKitHeight
    )
  }
}

/// A placement proven to belong to one capture operation, exact window, and
/// current ScreenCaptureKit delivery.
struct SlideCanvasOverlayPlacement: Equatable, Sendable {
  let captureOperationID: CaptureOperationID
  let windowID: CGWindowID
  let frameSequenceNumber: UInt64

  private let targetOriginX: Double
  private let targetOriginY: Double
  private let targetWidth: Double
  private let targetHeight: Double

  fileprivate init(
    captureOperationID: CaptureOperationID,
    windowID: CGWindowID,
    frameSequenceNumber: UInt64,
    appKitTargetFrame: CGRect
  ) {
    self.captureOperationID = captureOperationID
    self.windowID = windowID
    self.frameSequenceNumber = frameSequenceNumber
    targetOriginX = Double(appKitTargetFrame.minX)
    targetOriginY = Double(appKitTargetFrame.minY)
    targetWidth = Double(appKitTargetFrame.width)
    targetHeight = Double(appKitTargetFrame.height)
  }

  var appKitTargetFrame: CGRect {
    CGRect(
      x: targetOriginX,
      y: targetOriginY,
      width: targetWidth,
      height: targetHeight
    )
  }
}

/// Metadata-safe reasons why a current confirmed canvas could not be mapped.
/// These cases deliberately retain no window title, coordinates, or captured
/// content.
enum SlideCanvasOverlayMappingRejection: String, Equatable, Sendable {
  case captureContextMismatch
  case surfaceGeometryUnavailableOrMismatched
  case screenGeometryUnavailable
  case unsupportedSelectionProvenance
  case invalidSurfaceGeometry
  case contentScaleMismatch
  /// Defensive failure: current `SlideCanvasRegion` and positive image-size
  /// invariants make this unreachable for constructible production input.
  case invalidCanvasRegion
  case canvasOutsideCapturedContent
  /// Defensive failure: preceding containment and finite-geometry checks make
  /// this unreachable for constructible production input.
  case invalidQuartzTarget
  case noContainingDisplay
  case ambiguousContainingDisplays
  case invalidAppKitTarget
}

enum SlideCanvasOverlayMappingResult: Equatable, Sendable {
  case mapped(SlideCanvasOverlayPlacement)
  case rejected(SlideCanvasOverlayMappingRejection)
}

enum SlideCanvasOverlayMappingState: Equatable, Sendable {
  case unavailable
  case mapped
  case rejected(SlideCanvasOverlayMappingRejection)
}

/// Maps a confirmed output-surface canvas to the exact current onscreen window
/// content rectangle. Every missing or ambiguous coordinate fact fails closed.
enum SlideCanvasOverlayMapper {
  private static let outputPixelTolerance = 1.0

  static func makePlacement(
    selection: ConfirmedSlideCanvasSelection,
    frame: CapturedPowerPointFrame,
    captureOperationID: CaptureOperationID,
    displays: [DisplayCoordinateSnapshot]
  ) -> SlideCanvasOverlayPlacement? {
    switch evaluatePlacement(
      selection: selection,
      frame: frame,
      captureOperationID: captureOperationID,
      displays: displays
    ) {
    case .mapped(let placement):
      return placement
    case .rejected:
      return nil
    }
  }

  static func evaluatePlacement(
    selection: ConfirmedSlideCanvasSelection,
    frame: CapturedPowerPointFrame,
    captureOperationID: CaptureOperationID,
    displays: [DisplayCoordinateSnapshot]
  ) -> SlideCanvasOverlayMappingResult {
    guard
      selection.captureOperationID == captureOperationID,
      selection.windowID == frame.windowID,
      frame.windowID != 0
    else {
      return .rejected(.captureContextMismatch)
    }
    guard
      let frameSurface = frame.captureSurfaceGeometry,
      frameSurface.outputPixelWidth == frame.image.width,
      frameSurface.outputPixelHeight == frame.image.height
    else {
      return .rejected(.surfaceGeometryUnavailableOrMismatched)
    }
    guard let screenGeometry = frame.captureScreenGeometry else {
      return .rejected(.screenGeometryUnavailable)
    }

    let selectedSurface: CaptureSurfaceGeometry
    switch selection.provenance {
    case .screenCaptureKit(let surface):
      selectedSurface = surface
    case .testOnlyWholeFrame:
      return .rejected(.unsupportedSelectionProvenance)
    }
    guard selectedSurface == frameSurface else {
      return .rejected(.surfaceGeometryUnavailableOrMismatched)
    }

    let scaleFactor = frameSurface.scaleFactor
    let contentScale = frameSurface.contentScale
    let outputWidth = Double(frameSurface.outputPixelWidth)
    let outputHeight = Double(frameSurface.outputPixelHeight)
    let contentMinimumX = frameSurface.contentOriginX * scaleFactor
    let contentMinimumY = frameSurface.contentOriginY * scaleFactor
    let contentPixelWidth = frameSurface.contentWidth * scaleFactor
    let contentPixelHeight = frameSurface.contentHeight * scaleFactor
    let contentMaximumX = contentMinimumX + contentPixelWidth
    let contentMaximumY = contentMinimumY + contentPixelHeight
    let screenRect = screenGeometry.screenRect

    let calculatedValues = [
      outputWidth,
      outputHeight,
      contentMinimumX,
      contentMinimumY,
      contentPixelWidth,
      contentPixelHeight,
      contentMaximumX,
      contentMaximumY,
      Double(screenRect.minX),
      Double(screenRect.minY),
      Double(screenRect.width),
      Double(screenRect.height),
      Double(screenRect.maxX),
      Double(screenRect.maxY),
    ]
    guard
      calculatedValues.allSatisfy(\.isFinite),
      contentPixelWidth > 0,
      contentPixelHeight > 0,
      contentMinimumX >= -outputPixelTolerance,
      contentMinimumY >= -outputPixelTolerance,
      contentMaximumX <= outputWidth + outputPixelTolerance,
      contentMaximumY <= outputHeight + outputPixelTolerance
    else {
      return .rejected(.invalidSurfaceGeometry)
    }

    // contentRect and contentScale describe the same captured content in
    // different units. Permit only one output pixel of SDK rounding drift.
    let widthDifferenceInOutputPixels =
      abs(
        Double(screenRect.width) * contentScale - frameSurface.contentWidth
      ) * scaleFactor
    let heightDifferenceInOutputPixels =
      abs(
        Double(screenRect.height) * contentScale - frameSurface.contentHeight
      ) * scaleFactor
    guard
      widthDifferenceInOutputPixels.isFinite,
      heightDifferenceInOutputPixels.isFinite,
      widthDifferenceInOutputPixels <= outputPixelTolerance,
      heightDifferenceInOutputPixels <= outputPixelTolerance
    else {
      return .rejected(.contentScaleMismatch)
    }
    guard
      let canvasPixels = selection.region.pixelRect(
        sourcePixelWidth: frameSurface.outputPixelWidth,
        sourcePixelHeight: frameSurface.outputPixelHeight
      )
    else {
      return .rejected(.invalidCanvasRegion)
    }

    let canvasMinimumX = Double(canvasPixels.x)
    let canvasMinimumY = Double(canvasPixels.y)
    let canvasMaximumX = Double(canvasPixels.maxX)
    let canvasMaximumY = Double(canvasPixels.maxY)
    guard
      canvasMinimumX >= contentMinimumX,
      canvasMinimumY >= contentMinimumY,
      canvasMaximumX <= contentMaximumX,
      canvasMaximumY <= contentMaximumY
    else {
      return .rejected(.canvasOutsideCapturedContent)
    }

    let leftFraction = (canvasMinimumX - contentMinimumX) / contentPixelWidth
    let topFraction = (canvasMinimumY - contentMinimumY) / contentPixelHeight
    let rightFraction = (canvasMaximumX - contentMinimumX) / contentPixelWidth
    let bottomFraction = (canvasMaximumY - contentMinimumY) / contentPixelHeight
    let quartzTargetFrame = CGRect(
      x: Double(screenRect.minX) + leftFraction * Double(screenRect.width),
      y: Double(screenRect.minY) + topFraction * Double(screenRect.height),
      width: (rightFraction - leftFraction) * Double(screenRect.width),
      height: (bottomFraction - topFraction) * Double(screenRect.height)
    )
    guard isValidTargetFrame(quartzTargetFrame) else {
      return .rejected(.invalidQuartzTarget)
    }

    let containingDisplays = displays.filter {
      fullyContains(quartzTargetFrame, in: $0.quartzGlobalFrame)
    }
    guard !containingDisplays.isEmpty else {
      return .rejected(.noContainingDisplay)
    }
    guard containingDisplays.count == 1, let display = containingDisplays.first else {
      return .rejected(.ambiguousContainingDisplays)
    }

    let quartzDisplay = display.quartzGlobalFrame
    let appKitDisplay = display.appKitFrame
    let normalizedLeft =
      (Double(quartzTargetFrame.minX) - Double(quartzDisplay.minX))
      / Double(quartzDisplay.width)
    let normalizedRight =
      (Double(quartzTargetFrame.maxX) - Double(quartzDisplay.minX))
      / Double(quartzDisplay.width)
    let normalizedTop =
      (Double(quartzTargetFrame.minY) - Double(quartzDisplay.minY))
      / Double(quartzDisplay.height)
    let normalizedBottom =
      (Double(quartzTargetFrame.maxY) - Double(quartzDisplay.minY))
      / Double(quartzDisplay.height)
    let appKitTargetFrame = CGRect(
      x: Double(appKitDisplay.minX) + normalizedLeft * Double(appKitDisplay.width),
      y: Double(appKitDisplay.maxY) - normalizedBottom * Double(appKitDisplay.height),
      width: (normalizedRight - normalizedLeft) * Double(appKitDisplay.width),
      height: (normalizedBottom - normalizedTop) * Double(appKitDisplay.height)
    )
    guard isValidTargetFrame(appKitTargetFrame) else {
      return .rejected(.invalidAppKitTarget)
    }

    return .mapped(
      SlideCanvasOverlayPlacement(
        captureOperationID: captureOperationID,
        windowID: frame.windowID,
        frameSequenceNumber: frame.sequenceNumber,
        appKitTargetFrame: appKitTargetFrame
      )
    )
  }

  private static func fullyContains(_ target: CGRect, in container: CGRect) -> Bool {
    target.minX >= container.minX
      && target.minY >= container.minY
      && target.maxX <= container.maxX
      && target.maxY <= container.maxY
  }

  private static func isValidTargetFrame(_ frame: CGRect) -> Bool {
    let rawWidth = Double(frame.size.width)
    let rawHeight = Double(frame.size.height)
    let values = [
      Double(frame.origin.x),
      Double(frame.origin.y),
      rawWidth,
      rawHeight,
      Double(frame.origin.x) + rawWidth,
      Double(frame.origin.y) + rawHeight,
    ]
    return values.allSatisfy(\.isFinite) && rawWidth > 0 && rawHeight > 0
  }
}
