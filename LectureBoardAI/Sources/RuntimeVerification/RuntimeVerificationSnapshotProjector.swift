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

  static func elapsedMilliseconds(
    from startedUptime: TimeInterval,
    to currentUptime: TimeInterval
  ) -> Int {
    let elapsed = (currentUptime - startedUptime) * 1_000
    guard elapsed.isFinite else { return 0 }
    return max(Int(elapsed.rounded(.down)), 0)
  }
}
