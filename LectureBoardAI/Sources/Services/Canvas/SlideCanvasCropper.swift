import CoreGraphics
import Foundation
import LectureBoardCore

enum SlideCanvasSelectionProvenance: Equatable, Sendable {
  case screenCaptureKit(CaptureSurfaceGeometry)
  case testOnlyWholeFrame(pixelWidth: Int, pixelHeight: Int)
}

/// A user-confirmed canvas boundary bound to one exact capture operation and surface.
struct ConfirmedSlideCanvasSelection: Equatable, Sendable {
  let captureOperationID: CaptureOperationID
  let windowID: CGWindowID
  let provenance: SlideCanvasSelectionProvenance
  let region: SlideCanvasRegion

  init?(
    captureOperationID: CaptureOperationID,
    windowID: CGWindowID,
    captureSurfaceGeometry: CaptureSurfaceGeometry,
    region: SlideCanvasRegion
  ) {
    guard windowID != 0 else { return nil }

    self.captureOperationID = captureOperationID
    self.windowID = windowID
    provenance = .screenCaptureKit(captureSurfaceGeometry)
    self.region = region
  }

  /// Keeps synthetic full-frame app fixtures explicit and separate from production
  /// ScreenCaptureKit provenance.
  static func testOnlyFullFrame(
    captureOperationID: CaptureOperationID,
    windowID: CGWindowID,
    sourcePixelWidth: Int,
    sourcePixelHeight: Int
  ) -> ConfirmedSlideCanvasSelection? {
    guard
      windowID != 0,
      sourcePixelWidth > 0,
      sourcePixelHeight > 0,
      let fullFrameRegion = SlideCanvasRegion(
        NormalizedRect(x: 0, y: 0, width: 1, height: 1)
      )
    else {
      return nil
    }

    return ConfirmedSlideCanvasSelection(
      captureOperationID: captureOperationID,
      windowID: windowID,
      provenance: .testOnlyWholeFrame(
        pixelWidth: sourcePixelWidth,
        pixelHeight: sourcePixelHeight
      ),
      region: fullFrameRegion
    )
  }

  private init(
    captureOperationID: CaptureOperationID,
    windowID: CGWindowID,
    provenance: SlideCanvasSelectionProvenance,
    region: SlideCanvasRegion
  ) {
    self.captureOperationID = captureOperationID
    self.windowID = windowID
    self.provenance = provenance
    self.region = region
  }

  func matches(
    _ frame: CapturedPowerPointFrame,
    captureOperationID: CaptureOperationID
  ) -> Bool {
    invalidationReason(for: frame, captureOperationID: captureOperationID) == nil
  }

  func invalidationReason(
    for frame: CapturedPowerPointFrame,
    captureOperationID: CaptureOperationID
  ) -> SlideCanvasInvalidationReason? {
    guard
      self.captureOperationID == captureOperationID,
      windowID == frame.windowID
    else {
      return .selectionContextMismatch
    }

    switch provenance {
    case .screenCaptureKit(let geometry):
      guard
        frame.captureSurfaceGeometry == geometry,
        geometry.outputPixelWidth == frame.image.width,
        geometry.outputPixelHeight == frame.image.height
      else {
        return SlideCanvasInvalidationReason.surfaceGeometryUnavailableOrMismatched(
          for: frame.deliveryKind
        )
      }
      return nil
    case .testOnlyWholeFrame(let pixelWidth, let pixelHeight):
      guard
        region.isFullFrame,
        pixelWidth == frame.image.width,
        pixelHeight == frame.image.height
      else {
        return .selectionContextMismatch
      }
      return nil
    }
  }
}

/// A capture delivery whose image and fingerprints contain only the confirmed canvas.
struct CapturedSlideCanvasFrame: @unchecked Sendable {
  let windowID: CGWindowID
  let sequenceNumber: UInt64
  let capturedAt: Date
  let displayTime: UInt64?
  let deliveryKind: CapturedFrameDeliveryKind
  let image: CGImage
  let fingerprint: FrameFingerprint
  let contentFingerprint: ContentFingerprint?
}

enum SlideCanvasFramePreparer {
  enum Outcome {
    case prepared(CapturedSlideCanvasFrame)
    case rejected(SlideCanvasInvalidationReason)
  }

  static func makeFrame(
    from frame: CapturedPowerPointFrame,
    captureOperationID: CaptureOperationID,
    selection: ConfirmedSlideCanvasSelection
  ) -> CapturedSlideCanvasFrame? {
    switch evaluate(
      frame,
      captureOperationID: captureOperationID,
      selection: selection
    ) {
    case .prepared(let canvasFrame):
      return canvasFrame
    case .rejected:
      return nil
    }
  }

  static func invalidationReason(
    for frame: CapturedPowerPointFrame,
    captureOperationID: CaptureOperationID,
    selection: ConfirmedSlideCanvasSelection
  ) -> SlideCanvasInvalidationReason? {
    switch evaluate(
      frame,
      captureOperationID: captureOperationID,
      selection: selection
    ) {
    case .prepared:
      return nil
    case .rejected(let reason):
      return reason
    }
  }

  static func evaluate(
    _ frame: CapturedPowerPointFrame,
    captureOperationID: CaptureOperationID,
    selection: ConfirmedSlideCanvasSelection
  ) -> Outcome {
    if let reason = selection.invalidationReason(
      for: frame,
      captureOperationID: captureOperationID
    ) {
      return .rejected(reason)
    }

    let canvasImage: CGImage
    let fingerprint: FrameFingerprint
    let contentFingerprint: ContentFingerprint?

    if selection.region.isFullFrame {
      guard frame.fingerprint.isValid else { return .rejected(.confirmedFrameRejected) }
      guard frame.contentFingerprint?.isValid != false else {
        return .rejected(.confirmedFrameRejected)
      }
      canvasImage = frame.image
      fingerprint = frame.fingerprint
      contentFingerprint = frame.contentFingerprint
    } else {
      guard
        let pixelRect = selection.region.pixelRect(
          sourcePixelWidth: frame.image.width,
          sourcePixelHeight: frame.image.height
        ),
        let croppedImage = cropTopLeft(image: frame.image, pixelRect: pixelRect),
        let croppedFingerprint = CGImageRasterizer.makeFrameFingerprint(
          from: croppedImage
        ),
        let croppedContentFingerprint = CGImageRasterizer.makeContentFingerprint(
          from: croppedImage
        )
      else {
        return .rejected(.confirmedFrameRejected)
      }
      canvasImage = croppedImage
      fingerprint = croppedFingerprint
      contentFingerprint = croppedContentFingerprint
    }

    return .prepared(
      CapturedSlideCanvasFrame(
        windowID: frame.windowID,
        sequenceNumber: frame.sequenceNumber,
        capturedAt: frame.capturedAt,
        displayTime: frame.displayTime,
        deliveryKind: frame.deliveryKind,
        image: canvasImage,
        fingerprint: fingerprint,
        contentFingerprint: contentFingerprint
      )
    )
  }

  private static func cropTopLeft(
    image: CGImage,
    pixelRect: SlideCanvasPixelRect
  ) -> CGImage? {
    image.cropping(
      to: CGRect(
        x: pixelRect.x,
        y: pixelRect.y,
        width: pixelRect.width,
        height: pixelRect.height
      )
    )
  }
}
