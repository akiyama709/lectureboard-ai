import Foundation
import Testing

@testable import LectureBoardCore

struct RuntimeVerificationSnapshotTests {
  @Test func roundTripsMetadataThroughJSON() throws {
    let snapshot = RuntimeVerificationSnapshot(
      timestamp: Date(timeIntervalSince1970: 1_788_045_600),
      elapsedMilliseconds: 1_250,
      screenRecordingPermission: .authorized,
      captureState: .capturing,
      visionState: .completed,
      frameCount: 120,
      newFrameCount: 4,
      repeatedFrameCount: 116,
      stableFrameCount: 3,
      slideChangeCount: 2,
      slideIdentityState: .identified,
      slideIdentitySampleCount: 8,
      slideIdentityContinuityBreakCount: 1,
      contentRevisionCount: 4,
      recognizedTextCount: 7,
      detectedRectangleCount: 2,
      strokeCandidateRegionCount: 3,
      occupiedRegionCount: 5,
      lastNewFrameAt: Date(timeIntervalSince1970: 1_788_045_599),
      latestDifferenceFromStableFrame: 0.42
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(RuntimeVerificationSnapshot.self, from: data)

    #expect(decoded == snapshot)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["image"] == nil)
    #expect(object["recognizedText"] == nil)
    #expect(object["title"] == nil)
    #expect(object["contentRevisionCount"] as? Int == 4)
    #expect(object["strokeCandidateRegionCount"] as? Int == 3)
    #expect(object["slideIdentityState"] as? String == "identified")
    #expect(object["slideIdentitySampleCount"] as? Int == 8)
    #expect(object["slideIdentityContinuityBreakCount"] as? Int == 1)
    #expect(object["slideID"] == nil)
    #expect(object["slideIndex"] == nil)
    #expect(object["presentationSessionToken"] == nil)
  }

  @Test func normalizesInvalidCountersAndMeasurements() {
    let snapshot = RuntimeVerificationSnapshot(
      timestamp: Date(timeIntervalSince1970: 0),
      elapsedMilliseconds: -9,
      screenRecordingPermission: .unknown,
      captureState: .idle,
      visionState: .idle,
      frameCount: -1,
      newFrameCount: -2,
      repeatedFrameCount: -3,
      stableFrameCount: -4,
      slideChangeCount: -5,
      slideIdentityState: .interrupted,
      slideIdentitySampleCount: -6,
      slideIdentityContinuityBreakCount: -7,
      contentRevisionCount: -6,
      recognizedTextCount: -6,
      detectedRectangleCount: -7,
      strokeCandidateRegionCount: -8,
      occupiedRegionCount: -8,
      lastNewFrameAt: Date(timeIntervalSince1970: .infinity),
      latestDifferenceFromStableFrame: .nan
    )

    #expect(snapshot.frameCount == 0)
    #expect(snapshot.elapsedMilliseconds == 0)
    #expect(snapshot.newFrameCount == 0)
    #expect(snapshot.repeatedFrameCount == 0)
    #expect(snapshot.stableFrameCount == 0)
    #expect(snapshot.slideChangeCount == 0)
    #expect(snapshot.slideIdentityState == .interrupted)
    #expect(snapshot.slideIdentitySampleCount == 0)
    #expect(snapshot.slideIdentityContinuityBreakCount == 0)
    #expect(snapshot.contentRevisionCount == 0)
    #expect(snapshot.recognizedTextCount == 0)
    #expect(snapshot.detectedRectangleCount == 0)
    #expect(snapshot.strokeCandidateRegionCount == 0)
    #expect(snapshot.occupiedRegionCount == 0)
    #expect(snapshot.lastNewFrameAt == nil)
    #expect(snapshot.latestDifferenceFromStableFrame == nil)
  }

  @Test func clampsFiniteDifferenceToNormalizedRange() {
    let low = snapshot(difference: -0.1)
    let high = snapshot(difference: 1.1)

    #expect(low.latestDifferenceFromStableFrame == 0)
    #expect(high.latestDifferenceFromStableFrame == 1)
  }

  private func snapshot(difference: Double) -> RuntimeVerificationSnapshot {
    RuntimeVerificationSnapshot(
      timestamp: Date(timeIntervalSince1970: 0),
      elapsedMilliseconds: 0,
      screenRecordingPermission: .authorized,
      captureState: .capturing,
      visionState: .completed,
      frameCount: 0,
      newFrameCount: 0,
      repeatedFrameCount: 0,
      stableFrameCount: 0,
      slideChangeCount: 0,
      recognizedTextCount: 0,
      detectedRectangleCount: 0,
      occupiedRegionCount: 0,
      latestDifferenceFromStableFrame: difference
    )
  }
}
