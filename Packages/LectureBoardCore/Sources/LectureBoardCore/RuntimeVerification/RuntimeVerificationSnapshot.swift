import Foundation

public enum ScreenRecordingPermissionState: String, Codable, Equatable, Sendable {
  case unknown
  case notDetermined
  case denied
  case authorized
}

public enum RuntimeCaptureState: String, Codable, Equatable, Sendable {
  case idle
  case starting
  case capturing
  case stopped
  case failed
}

public enum RuntimeVisionState: String, Codable, Equatable, Sendable {
  case idle
  case analyzing
  case completed
  case failed
}

/// Metadata-only state for the explicit slide-canvas confirmation boundary.
public enum RuntimeSlideCanvasState: String, Codable, Equatable, Sendable {
  case unavailable
  case waitingForFrame
  case needsConfirmation
  case selecting
  case confirmed
  case invalidated
}

/// Metadata-only outcome for mapping a confirmed slide canvas to an AppKit
/// overlay target. It records no coordinates, display identifiers, or content.
public enum RuntimeSlideCanvasOverlayState: String, Codable, Equatable, Sendable {
  case unavailable
  case mapped
  case captureContextMismatch
  case surfaceGeometryUnavailableOrMismatched
  case screenGeometryUnavailable
  case unsupportedSelectionProvenance
  case invalidSurfaceGeometry
  case contentScaleMismatch
  case invalidCanvasRegion
  case canvasOutsideCapturedContent
  case invalidQuartzTarget
  case noContainingDisplay
  case ambiguousContainingDisplays
  case invalidAppKitTarget
}

/// A metadata-only observation. It deliberately carries no frame image or recognized slide text.
public struct RuntimeVerificationSnapshot: Codable, Equatable, Sendable {
  public let timestamp: Date
  public let elapsedMilliseconds: Int
  public let screenRecordingPermission: ScreenRecordingPermissionState
  public let captureState: RuntimeCaptureState
  public let visionState: RuntimeVisionState
  public let slideCanvasState: RuntimeSlideCanvasState
  public let slideCanvasOverlayState: RuntimeSlideCanvasOverlayState
  public let frameCount: Int
  public let newFrameCount: Int
  public let repeatedFrameCount: Int
  public let stableFrameCount: Int
  public let slideChangeCount: Int
  public let slideIdentityState: SlideIdentityState
  public let slideIdentityFrameSyncState: SlideIdentityFrameSyncState
  public let slideIdentitySampleCount: Int
  public let slideIdentityContinuityBreakCount: Int
  public let contentRevisionCount: Int
  public let recognizedTextCount: Int
  public let detectedRectangleCount: Int
  public let strokeCandidateRegionCount: Int
  public let occupiedRegionCount: Int
  public let lastNewFrameAt: Date?
  public let latestDifferenceFromStableFrame: Double?

  public init(
    timestamp: Date,
    elapsedMilliseconds: Int,
    screenRecordingPermission: ScreenRecordingPermissionState,
    captureState: RuntimeCaptureState,
    visionState: RuntimeVisionState,
    slideCanvasState: RuntimeSlideCanvasState = .unavailable,
    slideCanvasOverlayState: RuntimeSlideCanvasOverlayState = .unavailable,
    frameCount: Int,
    newFrameCount: Int,
    repeatedFrameCount: Int,
    stableFrameCount: Int,
    slideChangeCount: Int,
    slideIdentityState: SlideIdentityState = .unavailable,
    slideIdentityFrameSyncState: SlideIdentityFrameSyncState = .notRequired,
    slideIdentitySampleCount: Int = 0,
    slideIdentityContinuityBreakCount: Int = 0,
    contentRevisionCount: Int = 0,
    recognizedTextCount: Int,
    detectedRectangleCount: Int,
    strokeCandidateRegionCount: Int = 0,
    occupiedRegionCount: Int,
    lastNewFrameAt: Date? = nil,
    latestDifferenceFromStableFrame: Double? = nil
  ) {
    self.timestamp =
      timestamp.timeIntervalSinceReferenceDate.isFinite
      ? timestamp
      : Date(timeIntervalSince1970: 0)
    self.elapsedMilliseconds = max(elapsedMilliseconds, 0)
    self.screenRecordingPermission = screenRecordingPermission
    self.captureState = captureState
    self.visionState = visionState
    self.slideCanvasState = slideCanvasState
    self.slideCanvasOverlayState = slideCanvasOverlayState
    self.frameCount = max(frameCount, 0)
    self.newFrameCount = max(newFrameCount, 0)
    self.repeatedFrameCount = max(repeatedFrameCount, 0)
    self.stableFrameCount = max(stableFrameCount, 0)
    self.slideChangeCount = max(slideChangeCount, 0)
    self.slideIdentityState = slideIdentityState
    self.slideIdentityFrameSyncState = slideIdentityFrameSyncState
    self.slideIdentitySampleCount = max(slideIdentitySampleCount, 0)
    self.slideIdentityContinuityBreakCount = max(slideIdentityContinuityBreakCount, 0)
    self.contentRevisionCount = max(contentRevisionCount, 0)
    self.recognizedTextCount = max(recognizedTextCount, 0)
    self.detectedRectangleCount = max(detectedRectangleCount, 0)
    self.strokeCandidateRegionCount = max(strokeCandidateRegionCount, 0)
    self.occupiedRegionCount = max(occupiedRegionCount, 0)
    self.lastNewFrameAt = lastNewFrameAt.flatMap {
      $0.timeIntervalSinceReferenceDate.isFinite ? $0 : nil
    }
    self.latestDifferenceFromStableFrame = latestDifferenceFromStableFrame.flatMap {
      $0.isFinite ? min(max($0, 0), 1) : nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case timestamp
    case elapsedMilliseconds
    case screenRecordingPermission
    case captureState
    case visionState
    case slideCanvasState
    case slideCanvasOverlayState
    case frameCount
    case newFrameCount
    case repeatedFrameCount
    case stableFrameCount
    case slideChangeCount
    case slideIdentityState
    case slideIdentityFrameSyncState
    case slideIdentitySampleCount
    case slideIdentityContinuityBreakCount
    case contentRevisionCount
    case recognizedTextCount
    case detectedRectangleCount
    case strokeCandidateRegionCount
    case occupiedRegionCount
    case lastNewFrameAt
    case latestDifferenceFromStableFrame
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      timestamp: try container.decode(Date.self, forKey: .timestamp),
      elapsedMilliseconds: try container.decode(Int.self, forKey: .elapsedMilliseconds),
      screenRecordingPermission: try container.decode(
        ScreenRecordingPermissionState.self,
        forKey: .screenRecordingPermission
      ),
      captureState: try container.decode(RuntimeCaptureState.self, forKey: .captureState),
      visionState: try container.decode(RuntimeVisionState.self, forKey: .visionState),
      slideCanvasState: try container.decodeIfPresent(
        RuntimeSlideCanvasState.self,
        forKey: .slideCanvasState
      ) ?? .unavailable,
      slideCanvasOverlayState: try container.decodeIfPresent(
        RuntimeSlideCanvasOverlayState.self,
        forKey: .slideCanvasOverlayState
      ) ?? .unavailable,
      frameCount: try container.decode(Int.self, forKey: .frameCount),
      newFrameCount: try container.decode(Int.self, forKey: .newFrameCount),
      repeatedFrameCount: try container.decode(Int.self, forKey: .repeatedFrameCount),
      stableFrameCount: try container.decode(Int.self, forKey: .stableFrameCount),
      slideChangeCount: try container.decode(Int.self, forKey: .slideChangeCount),
      slideIdentityState: try container.decodeIfPresent(
        SlideIdentityState.self,
        forKey: .slideIdentityState
      ) ?? .unavailable,
      slideIdentityFrameSyncState: try container.decodeIfPresent(
        SlideIdentityFrameSyncState.self,
        forKey: .slideIdentityFrameSyncState
      ) ?? .notRequired,
      slideIdentitySampleCount: try container.decodeIfPresent(
        Int.self,
        forKey: .slideIdentitySampleCount
      ) ?? 0,
      slideIdentityContinuityBreakCount: try container.decodeIfPresent(
        Int.self,
        forKey: .slideIdentityContinuityBreakCount
      ) ?? 0,
      contentRevisionCount: try container.decodeIfPresent(
        Int.self,
        forKey: .contentRevisionCount
      ) ?? 0,
      recognizedTextCount: try container.decode(Int.self, forKey: .recognizedTextCount),
      detectedRectangleCount: try container.decode(
        Int.self,
        forKey: .detectedRectangleCount
      ),
      strokeCandidateRegionCount: try container.decodeIfPresent(
        Int.self,
        forKey: .strokeCandidateRegionCount
      ) ?? 0,
      occupiedRegionCount: try container.decode(Int.self, forKey: .occupiedRegionCount),
      lastNewFrameAt: try container.decodeIfPresent(Date.self, forKey: .lastNewFrameAt),
      latestDifferenceFromStableFrame: try container.decodeIfPresent(
        Double.self,
        forKey: .latestDifferenceFromStableFrame
      )
    )
  }
}
