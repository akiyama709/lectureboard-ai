import Foundation
import LectureBoardCore

@MainActor
enum RuntimeVerificationSnapshotProjector {
  static func makeSnapshot(
    from model: AppModel,
    timestamp: Date,
    elapsedMilliseconds: Int,
    screenRecordingPermission: ScreenRecordingPermissionState
  ) -> RuntimeVerificationSnapshot {
    RuntimeVerificationSnapshot(
      timestamp: timestamp,
      elapsedMilliseconds: elapsedMilliseconds,
      screenRecordingPermission: screenRecordingPermission,
      captureState: captureState(for: model.captureStatus),
      visionState: visionState(for: model.slideAnalysisStatus),
      slideCanvasState: slideCanvasState(for: model.slideCanvasStatus),
      slideCanvasOverlayState: slideCanvasOverlayState(
        for: model.slideCanvasOverlayMappingState
      ),
      slideCanvasInvalidationReason: slideCanvasInvalidationReason(
        for: model.slideCanvasInvalidationReason
      ),
      frameCount: model.capturedFrameCount,
      newFrameCount: model.newCapturedFrameCount,
      repeatedFrameCount: model.repeatedCapturedFrameCount,
      stableFrameCount: model.stableFrameCount,
      slideChangeCount: model.slideChangeCount,
      slideIdentityState: model.slideIdentityState,
      slideIdentityFrameSyncState: model.slideIdentityFrameSyncState,
      slideIdentitySampleCount: model.slideIdentitySampleCount,
      slideIdentityContinuityBreakCount: model.slideIdentityContinuityBreakCount,
      contentRevisionCount: model.contentRevisionCount,
      recognizedTextCount: model.latestSlideAnalysis?.textBlocks.count ?? 0,
      detectedRectangleCount: model.latestSlideAnalysis?.graphicRegions.count ?? 0,
      strokeCandidateRegionCount: model.latestSlideAnalysis?.strokeCandidateRegions.count ?? 0,
      occupiedRegionCount: model.latestSlideAnalysis?.occupiedRegions.count ?? 0,
      lastNewFrameAt: model.lastNewFrameAt,
      latestDifferenceFromStableFrame: model.latestDifferenceFromStableFrame
    )
  }

  static func captureState(for status: AppModel.CaptureStatus) -> RuntimeCaptureState {
    switch status {
    case .stopped:
      return .stopped
    case .starting:
      return .starting
    case .capturing:
      return .capturing
    case .error:
      return .failed
    }
  }

  static func visionState(for status: AppModel.SlideAnalysisStatus) -> RuntimeVisionState {
    switch status {
    case .idle:
      return .idle
    case .analyzing:
      return .analyzing
    case .ready:
      return .completed
    case .error:
      return .failed
    }
  }

  static func slideCanvasState(for status: SlideCanvasStatus) -> RuntimeSlideCanvasState {
    switch status {
    case .unavailable:
      return .unavailable
    case .waitingForFrame:
      return .waitingForFrame
    case .needsConfirmation:
      return .needsConfirmation
    case .selecting:
      return .selecting
    case .confirmed:
      return .confirmed
    case .invalidated:
      return .invalidated
    }
  }

  static func slideCanvasOverlayState(
    for state: SlideCanvasOverlayMappingState
  ) -> RuntimeSlideCanvasOverlayState {
    switch state {
    case .unavailable:
      return .unavailable
    case .mapped:
      return .mapped
    case .rejected(let reason):
      switch reason {
      case .captureContextMismatch:
        return .captureContextMismatch
      case .surfaceGeometryUnavailableOrMismatched:
        return .surfaceGeometryUnavailableOrMismatched
      case .screenGeometryUnavailable:
        return .screenGeometryUnavailable
      case .unsupportedSelectionProvenance:
        return .unsupportedSelectionProvenance
      case .invalidSurfaceGeometry:
        return .invalidSurfaceGeometry
      case .contentScaleMismatch:
        return .contentScaleMismatch
      case .invalidCanvasRegion:
        return .invalidCanvasRegion
      case .canvasOutsideCapturedContent:
        return .canvasOutsideCapturedContent
      case .invalidQuartzTarget:
        return .invalidQuartzTarget
      case .noContainingDisplay:
        return .noContainingDisplay
      case .ambiguousContainingDisplays:
        return .ambiguousContainingDisplays
      case .invalidAppKitTarget:
        return .invalidAppKitTarget
      }
    }
  }

  static func slideCanvasInvalidationReason(
    for reason: SlideCanvasInvalidationReason?
  ) -> RuntimeSlideCanvasInvalidationReason? {
    guard let reason else { return nil }
    switch reason {
    case .newFrameSurfaceGeometryUnavailableOrMismatched:
      return .newFrameSurfaceGeometryUnavailableOrMismatched
    case .idleRepeatSurfaceGeometryUnavailableOrMismatched:
      return .idleRepeatSurfaceGeometryUnavailableOrMismatched
    case .selectionContextMismatch:
      return .selectionContextMismatch
    case .confirmedFrameRejected:
      return .confirmedFrameRejected
    }
  }

  static func elapsedMilliseconds(
    from startedUptime: TimeInterval,
    to currentUptime: TimeInterval
  ) -> Int {
    let elapsed = (currentUptime - startedUptime) * 1_000
    guard elapsed.isFinite else { return 0 }
    return max(Int(elapsed.rounded(.down)), 0)
  }
}
