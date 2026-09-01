import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct RuntimeVerificationSnapshotProjectorTests {
  @Test func mapsCaptureStatesWithoutTreatingStartupAsCapture() {
    #expect(RuntimeVerificationSnapshotProjector.captureState(for: .stopped) == .stopped)
    #expect(RuntimeVerificationSnapshotProjector.captureState(for: .starting) == .starting)
    #expect(RuntimeVerificationSnapshotProjector.captureState(for: .capturing) == .capturing)
    #expect(RuntimeVerificationSnapshotProjector.captureState(for: .error("failed")) == .failed)
  }

  @Test func mapsVisionStatesWithoutTreatingAnalysisAsCompleted() {
    #expect(RuntimeVerificationSnapshotProjector.visionState(for: .idle) == .idle)
    #expect(RuntimeVerificationSnapshotProjector.visionState(for: .analyzing) == .analyzing)
    #expect(RuntimeVerificationSnapshotProjector.visionState(for: .ready) == .completed)
    #expect(RuntimeVerificationSnapshotProjector.visionState(for: .error("failed")) == .failed)
  }

  @Test func mapsEverySlideCanvasStateWithoutCollapsingConfirmationBoundaries() {
    #expect(
      RuntimeVerificationSnapshotProjector.slideCanvasState(for: .unavailable)
        == .unavailable
    )
    #expect(
      RuntimeVerificationSnapshotProjector.slideCanvasState(for: .waitingForFrame)
        == .waitingForFrame
    )
    #expect(
      RuntimeVerificationSnapshotProjector.slideCanvasState(for: .needsConfirmation)
        == .needsConfirmation
    )
    #expect(RuntimeVerificationSnapshotProjector.slideCanvasState(for: .selecting) == .selecting)
    #expect(RuntimeVerificationSnapshotProjector.slideCanvasState(for: .confirmed) == .confirmed)
    #expect(
      RuntimeVerificationSnapshotProjector.slideCanvasState(for: .invalidated)
        == .invalidated
    )
  }

  @Test func mapsEveryOverlayOutcomeWithoutCollapsingRejectionReasons() {
    #expect(
      RuntimeVerificationSnapshotProjector.slideCanvasOverlayState(for: .unavailable)
        == .unavailable
    )
    #expect(
      RuntimeVerificationSnapshotProjector.slideCanvasOverlayState(for: .mapped)
        == .mapped
    )

    let expectations: [(SlideCanvasOverlayMappingRejection, RuntimeSlideCanvasOverlayState)] = [
      (.captureContextMismatch, .captureContextMismatch),
      (
        .surfaceGeometryUnavailableOrMismatched,
        .surfaceGeometryUnavailableOrMismatched
      ),
      (.screenGeometryUnavailable, .screenGeometryUnavailable),
      (.unsupportedSelectionProvenance, .unsupportedSelectionProvenance),
      (.invalidSurfaceGeometry, .invalidSurfaceGeometry),
      (.contentScaleMismatch, .contentScaleMismatch),
      (.invalidCanvasRegion, .invalidCanvasRegion),
      (.canvasOutsideCapturedContent, .canvasOutsideCapturedContent),
      (.invalidQuartzTarget, .invalidQuartzTarget),
      (.noContainingDisplay, .noContainingDisplay),
      (.ambiguousContainingDisplays, .ambiguousContainingDisplays),
      (.invalidAppKitTarget, .invalidAppKitTarget),
    ]

    for (rejection, expected) in expectations {
      #expect(
        RuntimeVerificationSnapshotProjector.slideCanvasOverlayState(
          for: .rejected(rejection)
        ) == expected
      )
    }
  }

  @Test func mapsEveryCanvasInvalidationReasonWithoutCollapsingDeliveryKinds() {
    let expectations: [(SlideCanvasInvalidationReason?, RuntimeSlideCanvasInvalidationReason?)] = [
      (nil, nil),
      (
        .newFrameSurfaceGeometryUnavailableOrMismatched,
        .newFrameSurfaceGeometryUnavailableOrMismatched
      ),
      (
        .idleRepeatSurfaceGeometryUnavailableOrMismatched,
        .idleRepeatSurfaceGeometryUnavailableOrMismatched
      ),
      (.selectionContextMismatch, .selectionContextMismatch),
      (.confirmedFrameRejected, .confirmedFrameRejected),
    ]

    for (reason, expected) in expectations {
      #expect(
        RuntimeVerificationSnapshotProjector.slideCanvasInvalidationReason(for: reason)
          == expected
      )
    }
  }

  @Test func elapsedMillisecondsAreMonotonicAndClampedAtZero() {
    #expect(
      RuntimeVerificationSnapshotProjector.elapsedMilliseconds(
        from: 100,
        to: 100.2519
      ) == 251
    )
    #expect(
      RuntimeVerificationSnapshotProjector.elapsedMilliseconds(
        from: 100,
        to: 99
      ) == 0
    )
  }

  @Test func projectsDefaultFrameSyncContentRevisionAndStrokeCandidateMetadata() {
    let model = AppModel()

    let snapshot = RuntimeVerificationSnapshotProjector.makeSnapshot(
      from: model,
      timestamp: Date(timeIntervalSince1970: 0),
      elapsedMilliseconds: 0,
      screenRecordingPermission: .authorized
    )

    #expect(snapshot.slideIdentityFrameSyncState == .notRequired)
    #expect(snapshot.slideCanvasState == .unavailable)
    #expect(snapshot.slideCanvasOverlayState == .unavailable)
    #expect(snapshot.slideCanvasInvalidationReason == nil)
    #expect(snapshot.contentRevisionCount == model.contentRevisionCount)
    #expect(snapshot.latestContentRevisionEvent == model.latestContentRevisionEvent)
    #expect(snapshot.strokeCandidateRegionCount == 0)
  }
}
