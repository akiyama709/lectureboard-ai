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
      slideCanvasState: .confirmed,
      slideCanvasOverlayState: .mapped,
      slideCanvasInvalidationReason: .idleRepeatSurfaceGeometryUnavailableOrMismatched,
      frameCount: 120,
      newFrameCount: 4,
      repeatedFrameCount: 116,
      stableFrameCount: 3,
      slideChangeCount: 2,
      slideIdentityState: .identified,
      slideIdentityFrameSyncState: .timedOut,
      slideIdentitySampleCount: 8,
      slideIdentityContinuityBreakCount: 1,
      contentRevisionCount: 4,
      latestContentRevisionEvent: RuntimeContentRevisionEvent(
        ordinal: 4,
        evidenceStartedMachAbsoluteTime: 9_876_500,
        confirmedMachAbsoluteTime: 9_876_543,
        source: .boundedFreshSample
      ),
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
    let contentRevisionEvent = try #require(
      object["latestContentRevisionEvent"] as? [String: Any]
    )
    #expect(
      Set(contentRevisionEvent.keys) == [
        "ordinal",
        "evidenceStartedMachAbsoluteTime",
        "confirmedMachAbsoluteTime",
        "source",
      ]
    )
    #expect(contentRevisionEvent["ordinal"] as? Int == 4)
    #expect(
      contentRevisionEvent["evidenceStartedMachAbsoluteTime"] as? UInt64 == 9_876_500
    )
    #expect(contentRevisionEvent["confirmedMachAbsoluteTime"] as? UInt64 == 9_876_543)
    #expect(contentRevisionEvent["source"] as? String == "boundedFreshSample")
    #expect(object["strokeCandidateRegionCount"] as? Int == 3)
    #expect(object["slideIdentityState"] as? String == "identified")
    #expect(object["slideIdentityFrameSyncState"] as? String == "timedOut")
    #expect(object["slideIdentitySampleCount"] as? Int == 8)
    #expect(object["slideIdentityContinuityBreakCount"] as? Int == 1)
    #expect(object["slideCanvasState"] as? String == "confirmed")
    #expect(object["slideCanvasOverlayState"] as? String == "mapped")
    #expect(
      object["slideCanvasInvalidationReason"] as? String
        == "idleRepeatSurfaceGeometryUnavailableOrMismatched"
    )
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
      slideCanvasState: .invalidated,
      slideCanvasOverlayState: .ambiguousContainingDisplays,
      slideCanvasInvalidationReason: .selectionContextMismatch,
      frameCount: -1,
      newFrameCount: -2,
      repeatedFrameCount: -3,
      stableFrameCount: -4,
      slideChangeCount: -5,
      slideIdentityState: .interrupted,
      slideIdentityFrameSyncState: .waiting,
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
    #expect(snapshot.slideIdentityFrameSyncState == .waiting)
    #expect(snapshot.slideIdentitySampleCount == 0)
    #expect(snapshot.slideIdentityContinuityBreakCount == 0)
    #expect(snapshot.slideCanvasState == .invalidated)
    #expect(snapshot.slideCanvasOverlayState == .ambiguousContainingDisplays)
    #expect(snapshot.slideCanvasInvalidationReason == .selectionContextMismatch)
    #expect(snapshot.contentRevisionCount == 0)
    #expect(snapshot.latestContentRevisionEvent == nil)
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

  @Test func producerClearsMissingOrMismatchedContentRevisionMetadata() {
    let missing = snapshot(contentRevisionCount: 2, latestContentRevisionEvent: nil)
    let mismatched = snapshot(
      contentRevisionCount: 2,
      latestContentRevisionEvent: RuntimeContentRevisionEvent(
        ordinal: 1,
        evidenceStartedMachAbsoluteTime: 90,
        confirmedMachAbsoluteTime: 100,
        source: .continuousDenseNew
      )
    )
    let zeroWithEvent = snapshot(
      contentRevisionCount: 0,
      latestContentRevisionEvent: RuntimeContentRevisionEvent(
        ordinal: 1,
        evidenceStartedMachAbsoluteTime: 90,
        confirmedMachAbsoluteTime: 100,
        source: .coarseStable
      )
    )
    let zeroEvidenceStart = snapshot(
      contentRevisionCount: 2,
      latestContentRevisionEvent: RuntimeContentRevisionEvent(
        ordinal: 2,
        evidenceStartedMachAbsoluteTime: 0,
        confirmedMachAbsoluteTime: 100,
        source: .boundedFreshSample
      )
    )
    let zeroConfirmation = snapshot(
      contentRevisionCount: 2,
      latestContentRevisionEvent: RuntimeContentRevisionEvent(
        ordinal: 2,
        evidenceStartedMachAbsoluteTime: 100,
        confirmedMachAbsoluteTime: 0,
        source: .boundedFreshSample
      )
    )
    let reversedInterval = snapshot(
      contentRevisionCount: 2,
      latestContentRevisionEvent: RuntimeContentRevisionEvent(
        ordinal: 2,
        evidenceStartedMachAbsoluteTime: 101,
        confirmedMachAbsoluteTime: 100,
        source: .boundedFreshSample
      )
    )

    for value in [
      missing,
      mismatched,
      zeroWithEvent,
      zeroEvidenceStart,
      zeroConfirmation,
      reversedInterval,
    ] {
      #expect(value.contentRevisionCount == 0)
      #expect(value.latestContentRevisionEvent == nil)
    }
  }

  @Test func contentRevisionSourceRawValuesAreStableMetadata() throws {
    let expected: [(RuntimeContentRevisionSource, String)] = [
      (.coarseStable, "coarseStable"),
      (.coarseSignificantVisualChange, "coarseSignificantVisualChange"),
      (.continuousDenseNew, "continuousDenseNew"),
      (.continuousDenseIdleRepeat, "continuousDenseIdleRepeat"),
      (.boundedFreshSample, "boundedFreshSample"),
    ]

    for (source, rawValue) in expected {
      let encoded = try JSONEncoder().encode(source)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
      #expect(try JSONDecoder().decode(RuntimeContentRevisionSource.self, from: encoded) == source)
    }
  }

  @Test func slideCanvasStateRawValuesAreStableMetadata() throws {
    let expected: [(RuntimeSlideCanvasState, String)] = [
      (.unavailable, "unavailable"),
      (.waitingForFrame, "waitingForFrame"),
      (.needsConfirmation, "needsConfirmation"),
      (.selecting, "selecting"),
      (.confirmed, "confirmed"),
      (.invalidated, "invalidated"),
    ]

    for (state, rawValue) in expected {
      let encoded = try JSONEncoder().encode(state)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
      #expect(try JSONDecoder().decode(RuntimeSlideCanvasState.self, from: encoded) == state)
    }
  }

  @Test func slideCanvasOverlayStateRawValuesAreStableMetadata() throws {
    let expected: [(RuntimeSlideCanvasOverlayState, String)] = [
      (.unavailable, "unavailable"),
      (.mapped, "mapped"),
      (.captureContextMismatch, "captureContextMismatch"),
      (
        .surfaceGeometryUnavailableOrMismatched,
        "surfaceGeometryUnavailableOrMismatched"
      ),
      (.screenGeometryUnavailable, "screenGeometryUnavailable"),
      (.unsupportedSelectionProvenance, "unsupportedSelectionProvenance"),
      (.invalidSurfaceGeometry, "invalidSurfaceGeometry"),
      (.contentScaleMismatch, "contentScaleMismatch"),
      (.invalidCanvasRegion, "invalidCanvasRegion"),
      (.canvasOutsideCapturedContent, "canvasOutsideCapturedContent"),
      (.invalidQuartzTarget, "invalidQuartzTarget"),
      (.noContainingDisplay, "noContainingDisplay"),
      (.ambiguousContainingDisplays, "ambiguousContainingDisplays"),
      (.invalidAppKitTarget, "invalidAppKitTarget"),
    ]

    for (state, rawValue) in expected {
      let encoded = try JSONEncoder().encode(state)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
      #expect(
        try JSONDecoder().decode(RuntimeSlideCanvasOverlayState.self, from: encoded)
          == state
      )
    }
  }

  @Test func slideCanvasInvalidationReasonRawValuesAreStableMetadata() throws {
    let expected: [(RuntimeSlideCanvasInvalidationReason, String)] = [
      (
        .newFrameSurfaceGeometryUnavailableOrMismatched,
        "newFrameSurfaceGeometryUnavailableOrMismatched"
      ),
      (
        .idleRepeatSurfaceGeometryUnavailableOrMismatched,
        "idleRepeatSurfaceGeometryUnavailableOrMismatched"
      ),
      (.selectionContextMismatch, "selectionContextMismatch"),
      (.confirmedFrameRejected, "confirmedFrameRejected"),
      (.selectionStartRejected, "selectionStartRejected"),
      (.selectionConfirmationRejected, "selectionConfirmationRejected"),
      (.confirmationLostDuringObservation, "confirmationLostDuringObservation"),
      (.unclassifiedInvalidation, "unclassifiedInvalidation"),
    ]

    for (reason, rawValue) in expected {
      let encoded = try JSONEncoder().encode(reason)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
      #expect(
        try JSONDecoder().decode(RuntimeSlideCanvasInvalidationReason.self, from: encoded)
          == reason
      )
    }
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

  private func snapshot(
    contentRevisionCount: Int,
    latestContentRevisionEvent: RuntimeContentRevisionEvent?
  ) -> RuntimeVerificationSnapshot {
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
      contentRevisionCount: contentRevisionCount,
      latestContentRevisionEvent: latestContentRevisionEvent,
      recognizedTextCount: 0,
      detectedRectangleCount: 0,
      occupiedRegionCount: 0
    )
  }
}
