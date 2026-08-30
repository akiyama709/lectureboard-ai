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
    #expect(snapshot.contentRevisionCount == model.contentRevisionCount)
    #expect(snapshot.strokeCandidateRegionCount == 0)
  }
}
