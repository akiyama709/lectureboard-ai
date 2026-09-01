import Foundation
import Testing

@testable import LectureBoardCore

struct RuntimeVerificationReportTests {
  @Test func roundTripsMetadataThroughJSON() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: true,
      permissionRequestReturned: true,
      preflightBefore: .notDetermined,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      slideCanvasConfirmationMode: .diagnosticFullFrame,
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: data)

    #expect(decoded == report)
    #expect(decoded.schemaVersion == RuntimeVerificationReport.currentSchemaVersion)
    #expect(decoded.slideCanvasConfirmationMode == .diagnosticFullFrame)
    #expect(decoded.snapshots[0].latestContentRevisionEvent?.ordinal == 2)
    #expect(
      decoded.snapshots[0].latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime
        == 12_300
    )
    #expect(
      decoded.snapshots[0].latestContentRevisionEvent?.confirmedMachAbsoluteTime == 12_345
    )
    #expect(decoded.snapshots[0].latestContentRevisionEvent?.source == .continuousDenseNew)
  }

  @Test func normalizesInvalidNumericAndMetadataValues() {
    let report = RuntimeVerificationReport(
      schemaVersion: -1,
      startedAt: Date(timeIntervalSince1970: .infinity),
      finishedAt: Date(timeIntervalSince1970: -.infinity),
      requestedDurationSeconds: .nan,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .unknown,
      preflightAfter: .unknown,
      matchedWindowCount: -2,
      selectedWindowID: nil,
      selectedBundleIdentifier: "  \0  ",
      runStatus: .failed,
      failureCode: nil,
      untrustedFailureDetail: "  capture ended unexpectedly  ",
      snapshots: []
    )

    #expect(report.schemaVersion == RuntimeVerificationReport.currentSchemaVersion)
    #expect(report.startedAt == Date(timeIntervalSince1970: 0))
    #expect(report.finishedAt == report.startedAt)
    #expect(report.requestedDurationSeconds == 0)
    #expect(report.matchedWindowCount == 0)
    #expect(report.selectedBundleIdentifier == nil)
    #expect(report.failureCode == .internalFailure)
    #expect(report.failureMessage == "Runtime verification failed.")
  }

  @Test func producerAlwaysLabelsPayloadWithTheCurrentSchema() {
    let report = RuntimeVerificationReport(
      schemaVersion: RuntimeVerificationReport.currentSchemaVersion + 100,
      startedAt: Date(timeIntervalSince1970: 1),
      finishedAt: Date(timeIntervalSince1970: 2),
      requestedDurationSeconds: 1,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: []
    )

    #expect(RuntimeVerificationReport.currentSchemaVersion == 11)
    #expect(report.schemaVersion == RuntimeVerificationReport.currentSchemaVersion)
  }

  @Test func roundTripsBoundedCaptureFailureTelemetry() throws {
    let report = makeFailedCaptureReport(
      source: .delegateStoppedWithKnownSCError,
      code: .systemStoppedStream
    )

    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: data)

    #expect(decoded == report)
    #expect(decoded.schemaVersion == 11)
    #expect(decoded.captureFailureSource == .delegateStoppedWithKnownSCError)
    #expect(decoded.captureSCStreamErrorCode == .systemStoppedStream)
    #expect(
      decoded.failureMessage == RuntimeVerificationFailureCode.captureFailed.safeReportMessage
    )
  }

  @Test func decodesSchemaTwoWithoutRelabelingItsLegacyCounterSemantics() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 2
    object.removeValue(forKey: "slideCanvasConfirmationMode")
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0]["stableFrameCount"] = 6
    snapshots[0]["slideChangeCount"] = 5
    snapshots[0]["contentRevisionCount"] = 2
    snapshots[0].removeValue(forKey: "slideIdentityState")
    snapshots[0].removeValue(forKey: "slideIdentityFrameSyncState")
    snapshots[0].removeValue(forKey: "slideIdentitySampleCount")
    snapshots[0].removeValue(forKey: "slideIdentityContinuityBreakCount")
    snapshots[0].removeValue(forKey: "slideCanvasState")
    snapshots[0].removeValue(forKey: "slideCanvasOverlayState")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 2)
    #expect(decoded.slideCanvasConfirmationMode == nil)
    #expect(decoded.snapshots[0].stableFrameCount == 6)
    #expect(decoded.snapshots[0].slideChangeCount == 5)
    #expect(decoded.snapshots[0].contentRevisionCount == 2)
    #expect(decoded.snapshots[0].slideIdentityState == .unavailable)
    #expect(decoded.snapshots[0].slideIdentityFrameSyncState == .notRequired)
    #expect(decoded.snapshots[0].slideIdentitySampleCount == 0)
    #expect(decoded.snapshots[0].slideIdentityContinuityBreakCount == 0)
    #expect(decoded.snapshots[0].slideCanvasState == .unavailable)
    #expect(decoded.snapshots[0].slideCanvasOverlayState == .unavailable)
  }

  @Test func decodesSchemaThreeWithoutSlideIdentityMetadata() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 3
    object.removeValue(forKey: "slideCanvasConfirmationMode")
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0].removeValue(forKey: "slideIdentityState")
    snapshots[0].removeValue(forKey: "slideIdentityFrameSyncState")
    snapshots[0].removeValue(forKey: "slideIdentitySampleCount")
    snapshots[0].removeValue(forKey: "slideIdentityContinuityBreakCount")
    snapshots[0].removeValue(forKey: "slideCanvasState")
    snapshots[0].removeValue(forKey: "slideCanvasOverlayState")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 3)
    #expect(decoded.slideCanvasConfirmationMode == nil)
    #expect(decoded.snapshots[0].slideIdentityState == .unavailable)
    #expect(decoded.snapshots[0].slideIdentityFrameSyncState == .notRequired)
    #expect(decoded.snapshots[0].slideIdentitySampleCount == 0)
    #expect(decoded.snapshots[0].slideIdentityContinuityBreakCount == 0)
    #expect(decoded.snapshots[0].slideCanvasState == .unavailable)
    #expect(decoded.snapshots[0].slideCanvasOverlayState == .unavailable)
  }

  @Test func decodesSchemaFourWithoutFrameSyncMetadata() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 4
    object.removeValue(forKey: "slideCanvasConfirmationMode")
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0].removeValue(forKey: "slideIdentityFrameSyncState")
    snapshots[0].removeValue(forKey: "slideCanvasState")
    snapshots[0].removeValue(forKey: "slideCanvasOverlayState")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 4)
    #expect(decoded.slideCanvasConfirmationMode == nil)
    #expect(decoded.snapshots[0].slideIdentityState == .identified)
    #expect(decoded.snapshots[0].slideIdentityFrameSyncState == .notRequired)
    #expect(decoded.snapshots[0].slideIdentitySampleCount == 12)
    #expect(decoded.snapshots[0].slideIdentityContinuityBreakCount == 1)
    #expect(decoded.snapshots[0].slideCanvasState == .unavailable)
    #expect(decoded.snapshots[0].slideCanvasOverlayState == .unavailable)
  }

  @Test func decodesSchemaFiveWithoutSlideCanvasMetadata() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 5
    object.removeValue(forKey: "slideCanvasConfirmationMode")
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0].removeValue(forKey: "slideCanvasState")
    snapshots[0].removeValue(forKey: "slideCanvasOverlayState")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 5)
    #expect(decoded.slideCanvasConfirmationMode == nil)
    #expect(decoded.snapshots[0].slideIdentityState == .identified)
    #expect(decoded.snapshots[0].slideIdentityFrameSyncState == .waiting)
    #expect(decoded.snapshots[0].slideCanvasState == .unavailable)
    #expect(decoded.snapshots[0].slideCanvasOverlayState == .unavailable)
  }

  @Test func decodesSchemaSixWithoutSlideCanvasOverlayMetadata() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 6
    object.removeValue(forKey: "slideCanvasConfirmationMode")
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0].removeValue(forKey: "slideCanvasOverlayState")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 6)
    #expect(decoded.slideCanvasConfirmationMode == nil)
    #expect(decoded.snapshots[0].slideCanvasState == .confirmed)
    #expect(decoded.snapshots[0].slideCanvasOverlayState == .unavailable)
  }

  @Test func decodesSchemaSevenWithoutCanvasConfirmationProvenance() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      slideCanvasConfirmationMode: .diagnosticFullFrame,
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 7
    object.removeValue(forKey: "slideCanvasConfirmationMode")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 7)
    #expect(decoded.slideCanvasConfirmationMode == nil)
    #expect(decoded.snapshots[0].slideCanvasState == .confirmed)
    #expect(decoded.snapshots[0].slideCanvasOverlayState == .mapped)
  }

  @Test func decodesSchemaOneThroughEightWithoutCanvasFailureMetadata() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .failed,
      failureCode: .slideCanvasConfirmationFailed,
      slideCanvasFailureReason: .selectionConfirmationRejected,
      untrustedFailureDetail: nil,
      snapshots: [
        snapshot(
          invalidationReason: .newFrameSurfaceGeometryUnavailableOrMismatched
        )
      ]
    )

    let encoded = try JSONEncoder().encode(report)
    let currentObject = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )

    for schemaVersion in 1...8 {
      var legacyObject = currentObject
      legacyObject["schemaVersion"] = schemaVersion
      legacyObject.removeValue(forKey: "slideCanvasFailureReason")
      var snapshots = try #require(legacyObject["snapshots"] as? [[String: Any]])
      snapshots[0].removeValue(forKey: "slideCanvasInvalidationReason")
      legacyObject["snapshots"] = snapshots

      let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
      let decoded = try JSONDecoder().decode(
        RuntimeVerificationReport.self,
        from: legacyData
      )

      #expect(decoded.schemaVersion == schemaVersion)
      #expect(decoded.slideCanvasFailureReason == nil)
      #expect(decoded.snapshots[0].slideCanvasInvalidationReason == nil)
    }
  }

  @Test func decodesSchemaOneThroughNineWithoutCaptureFailureMetadata() throws {
    let report = makeFailedCaptureReport(
      source: .delegateStoppedWithKnownSCError,
      code: .userStopped
    )
    let encoded = try JSONEncoder().encode(report)
    let currentObject = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )

    for schemaVersion in 1...9 {
      var legacyObjectWithoutFields = currentObject
      legacyObjectWithoutFields["schemaVersion"] = schemaVersion
      legacyObjectWithoutFields.removeValue(forKey: "captureFailureSource")
      legacyObjectWithoutFields.removeValue(forKey: "captureSCStreamErrorCode")

      let legacyDataWithoutFields = try JSONSerialization.data(
        withJSONObject: legacyObjectWithoutFields
      )
      let decodedWithoutFields = try JSONDecoder().decode(
        RuntimeVerificationReport.self,
        from: legacyDataWithoutFields
      )
      #expect(decodedWithoutFields.schemaVersion == schemaVersion)
      #expect(decodedWithoutFields.captureFailureSource == nil)
      #expect(decodedWithoutFields.captureSCStreamErrorCode == nil)

      var legacyObjectWithInjectedFields = currentObject
      legacyObjectWithInjectedFields["schemaVersion"] = schemaVersion
      let legacyDataWithInjectedFields = try JSONSerialization.data(
        withJSONObject: legacyObjectWithInjectedFields
      )
      let decodedWithInjectedFields = try JSONDecoder().decode(
        RuntimeVerificationReport.self,
        from: legacyDataWithInjectedFields
      )
      #expect(decodedWithInjectedFields.schemaVersion == schemaVersion)
      #expect(decodedWithInjectedFields.captureFailureSource == nil)
      #expect(decodedWithInjectedFields.captureSCStreamErrorCode == nil)
    }
  }

  @Test func decodesSchemaOneSnapshotsWithoutNewMetadataCounters() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 1
    object.removeValue(forKey: "slideCanvasConfirmationMode")
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0].removeValue(forKey: "contentRevisionCount")
    snapshots[0].removeValue(forKey: "strokeCandidateRegionCount")
    snapshots[0].removeValue(forKey: "slideIdentityState")
    snapshots[0].removeValue(forKey: "slideIdentityFrameSyncState")
    snapshots[0].removeValue(forKey: "slideIdentitySampleCount")
    snapshots[0].removeValue(forKey: "slideIdentityContinuityBreakCount")
    snapshots[0].removeValue(forKey: "slideCanvasState")
    snapshots[0].removeValue(forKey: "slideCanvasOverlayState")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 1)
    #expect(decoded.slideCanvasConfirmationMode == nil)
    #expect(decoded.snapshots[0].contentRevisionCount == 0)
    #expect(decoded.snapshots[0].strokeCandidateRegionCount == 0)
    #expect(decoded.snapshots[0].slideIdentityState == .unavailable)
    #expect(decoded.snapshots[0].slideIdentityFrameSyncState == .notRequired)
    #expect(decoded.snapshots[0].slideIdentitySampleCount == 0)
    #expect(decoded.snapshots[0].slideIdentityContinuityBreakCount == 0)
    #expect(decoded.snapshots[0].slideCanvasState == .unavailable)
    #expect(decoded.snapshots[0].slideCanvasOverlayState == .unavailable)
  }

  @Test func decodesSchemaTenWithoutContentRevisionEventMetadata() throws {
    let encoded = try JSONEncoder().encode(
      RuntimeVerificationReport(
        startedAt: Date(timeIntervalSince1970: 1_788_045_600),
        finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
        requestedDurationSeconds: 12,
        permissionWasRequested: false,
        permissionRequestReturned: nil,
        preflightBefore: .authorized,
        preflightAfter: .authorized,
        matchedWindowCount: 1,
        selectedWindowID: 42,
        selectedBundleIdentifier: "com.microsoft.Powerpoint",
        runStatus: .completed,
        failureCode: nil,
        untrustedFailureDetail: nil,
        snapshots: [snapshot()]
      )
    )
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object["schemaVersion"] = 10
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0].removeValue(forKey: "latestContentRevisionEvent")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 10)
    #expect(decoded.snapshots[0].contentRevisionCount == 2)
    #expect(decoded.snapshots[0].latestContentRevisionEvent == nil)
  }

  @Test func schemaTenIgnoresInjectedMalformedContentRevisionEventMetadata() throws {
    var object = try currentReportJSONObject()
    object["schemaVersion"] = 10
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0]["latestContentRevisionEvent"] = [
      "ordinal": "PRIVATE_INVALID_ORDINAL",
      "evidenceStartedMachAbsoluteTime": -1,
      "confirmedMachAbsoluteTime": "PRIVATE_INVALID_CONFIRMATION",
      "source": "PRIVATE_UNKNOWN_SOURCE",
    ]
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 10)
    #expect(decoded.snapshots[0].contentRevisionCount == 2)
    #expect(decoded.snapshots[0].latestContentRevisionEvent == nil)
  }

  @Test func schemaElevenRejectsMissingOrInconsistentContentRevisionMetadata() throws {
    let currentObject = try currentReportJSONObject()

    var missingEventObject = currentObject
    var missingEventSnapshots = try #require(
      missingEventObject["snapshots"] as? [[String: Any]]
    )
    missingEventSnapshots[0].removeValue(forKey: "latestContentRevisionEvent")
    missingEventObject["snapshots"] = missingEventSnapshots

    var missingCountObject = currentObject
    var missingCountSnapshots = try #require(
      missingCountObject["snapshots"] as? [[String: Any]]
    )
    missingCountSnapshots[0].removeValue(forKey: "contentRevisionCount")
    missingCountObject["snapshots"] = missingCountSnapshots

    var negativeCountWithoutEventObject = currentObject
    var negativeCountWithoutEventSnapshots = try #require(
      negativeCountWithoutEventObject["snapshots"] as? [[String: Any]]
    )
    negativeCountWithoutEventSnapshots[0]["contentRevisionCount"] = -1
    negativeCountWithoutEventSnapshots[0].removeValue(
      forKey: "latestContentRevisionEvent"
    )
    negativeCountWithoutEventObject["snapshots"] = negativeCountWithoutEventSnapshots

    var zeroCountWithEventObject = currentObject
    var zeroCountWithEventSnapshots = try #require(
      zeroCountWithEventObject["snapshots"] as? [[String: Any]]
    )
    zeroCountWithEventSnapshots[0]["contentRevisionCount"] = 0
    zeroCountWithEventObject["snapshots"] = zeroCountWithEventSnapshots

    var mismatchedOrdinalObject = currentObject
    var mismatchedOrdinalSnapshots = try #require(
      mismatchedOrdinalObject["snapshots"] as? [[String: Any]]
    )
    var mismatchedEvent = try #require(
      mismatchedOrdinalSnapshots[0]["latestContentRevisionEvent"] as? [String: Any]
    )
    mismatchedEvent["ordinal"] = 1
    mismatchedOrdinalSnapshots[0]["latestContentRevisionEvent"] = mismatchedEvent
    mismatchedOrdinalObject["snapshots"] = mismatchedOrdinalSnapshots

    var unknownSourceObject = currentObject
    var unknownSourceSnapshots = try #require(
      unknownSourceObject["snapshots"] as? [[String: Any]]
    )
    var unknownSourceEvent = try #require(
      unknownSourceSnapshots[0]["latestContentRevisionEvent"] as? [String: Any]
    )
    unknownSourceEvent["source"] = "futurePrivateSource"
    unknownSourceSnapshots[0]["latestContentRevisionEvent"] = unknownSourceEvent
    unknownSourceObject["snapshots"] = unknownSourceSnapshots

    var zeroEvidenceStartObject = currentObject
    var zeroEvidenceStartSnapshots = try #require(
      zeroEvidenceStartObject["snapshots"] as? [[String: Any]]
    )
    var zeroEvidenceStartEvent = try #require(
      zeroEvidenceStartSnapshots[0]["latestContentRevisionEvent"] as? [String: Any]
    )
    zeroEvidenceStartEvent["evidenceStartedMachAbsoluteTime"] = 0
    zeroEvidenceStartSnapshots[0]["latestContentRevisionEvent"] = zeroEvidenceStartEvent
    zeroEvidenceStartObject["snapshots"] = zeroEvidenceStartSnapshots

    var zeroConfirmationObject = currentObject
    var zeroConfirmationSnapshots = try #require(
      zeroConfirmationObject["snapshots"] as? [[String: Any]]
    )
    var zeroConfirmationEvent = try #require(
      zeroConfirmationSnapshots[0]["latestContentRevisionEvent"] as? [String: Any]
    )
    zeroConfirmationEvent["confirmedMachAbsoluteTime"] = 0
    zeroConfirmationSnapshots[0]["latestContentRevisionEvent"] = zeroConfirmationEvent
    zeroConfirmationObject["snapshots"] = zeroConfirmationSnapshots

    var reversedIntervalObject = currentObject
    var reversedIntervalSnapshots = try #require(
      reversedIntervalObject["snapshots"] as? [[String: Any]]
    )
    var reversedIntervalEvent = try #require(
      reversedIntervalSnapshots[0]["latestContentRevisionEvent"] as? [String: Any]
    )
    reversedIntervalEvent["evidenceStartedMachAbsoluteTime"] = 12_346
    reversedIntervalEvent["confirmedMachAbsoluteTime"] = 12_345
    reversedIntervalSnapshots[0]["latestContentRevisionEvent"] = reversedIntervalEvent
    reversedIntervalObject["snapshots"] = reversedIntervalSnapshots

    for invalidObject in [
      missingEventObject,
      missingCountObject,
      negativeCountWithoutEventObject,
      zeroCountWithEventObject,
      mismatchedOrdinalObject,
      unknownSourceObject,
      zeroEvidenceStartObject,
      zeroConfirmationObject,
      reversedIntervalObject,
    ] {
      let invalidData = try JSONSerialization.data(withJSONObject: invalidObject)
      #expect(throws: DecodingError.self) {
        try JSONDecoder().decode(RuntimeVerificationReport.self, from: invalidData)
      }
    }
  }

  @Test func clampsFinishTimeAndClearsFailureFromCompletedRun() {
    let startedAt = Date(timeIntervalSince1970: 100)
    let report = RuntimeVerificationReport(
      startedAt: startedAt,
      finishedAt: Date(timeIntervalSince1970: 90),
      requestedDurationSeconds: -4,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .denied,
      preflightAfter: .denied,
      matchedWindowCount: 0,
      selectedWindowID: nil,
      selectedBundleIdentifier: nil,
      runStatus: .completed,
      failureCode: .captureFailed,
      captureFailureSource: .delegateStoppedWithKnownSCError,
      captureSCStreamErrorCode: .userStopped,
      slideCanvasFailureReason: .confirmedFrameRejected,
      untrustedFailureDetail: "not retained",
      snapshots: []
    )

    #expect(report.finishedAt == startedAt)
    #expect(report.requestedDurationSeconds == 0)
    #expect(report.failureCode == nil)
    #expect(report.failureMessage == nil)
    #expect(report.captureFailureSource == nil)
    #expect(report.captureSCStreamErrorCode == nil)
    #expect(report.slideCanvasFailureReason == nil)
  }

  @Test func failedCaptureReportsAlwaysUseBoundedConsistentTelemetry() {
    let explicitKnown = makeFailedCaptureReport(
      source: .delegateStoppedWithKnownSCError,
      code: .failedApplicationConnectionInterrupted
    )
    let explicitUnknown = makeFailedCaptureReport(
      source: .delegateStoppedWithUnknownError,
      code: nil
    )
    let missing = makeFailedCaptureReport(source: nil, code: nil)
    let knownWithoutCode = makeFailedCaptureReport(
      source: .delegateStoppedWithKnownSCError,
      code: nil
    )
    let unknownWithCode = makeFailedCaptureReport(
      source: .delegateStoppedWithUnknownError,
      code: .internalError
    )
    let unrelated = makeFailedCanvasReport(
      slideCanvasFailureReason: .confirmedFrameRejected
    )

    #expect(explicitKnown.captureFailureSource == .delegateStoppedWithKnownSCError)
    #expect(explicitKnown.captureSCStreamErrorCode == .failedApplicationConnectionInterrupted)
    #expect(explicitUnknown.captureFailureSource == .delegateStoppedWithUnknownError)
    #expect(explicitUnknown.captureSCStreamErrorCode == nil)
    #expect(missing.captureFailureSource == .unclassifiedCaptureFailure)
    #expect(missing.captureSCStreamErrorCode == nil)
    #expect(knownWithoutCode.captureFailureSource == .unclassifiedCaptureFailure)
    #expect(knownWithoutCode.captureSCStreamErrorCode == nil)
    #expect(unknownWithCode.captureFailureSource == .unclassifiedCaptureFailure)
    #expect(unknownWithCode.captureSCStreamErrorCode == nil)
    #expect(unrelated.captureFailureSource == nil)
    #expect(unrelated.captureSCStreamErrorCode == nil)
  }

  @Test func decodesCurrentCaptureFailureWithoutTelemetryAsUnclassified() throws {
    let report = makeFailedCaptureReport(
      source: .sampleStatusStopped,
      code: nil
    )
    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "captureFailureSource")

    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(
      RuntimeVerificationReport.self,
      from: data
    )

    #expect(decoded.schemaVersion == 11)
    #expect(decoded.failureCode == .captureFailed)
    #expect(decoded.captureFailureSource == .unclassifiedCaptureFailure)
    #expect(decoded.captureSCStreamErrorCode == nil)
  }

  @Test func decodesInconsistentCurrentCaptureTelemetryAsUnclassified() throws {
    let knownWithoutCode = try decodedCaptureReport(
      source: RuntimeCaptureFailureSource.delegateStoppedWithKnownSCError.rawValue,
      code: nil
    )
    let unknownWithCode = try decodedCaptureReport(
      source: RuntimeCaptureFailureSource.delegateStoppedWithUnknownError.rawValue,
      code: RuntimeSCStreamErrorCode.userStopped.rawValue
    )

    #expect(knownWithoutCode.captureFailureSource == .unclassifiedCaptureFailure)
    #expect(knownWithoutCode.captureSCStreamErrorCode == nil)
    #expect(unknownWithCode.captureFailureSource == .unclassifiedCaptureFailure)
    #expect(unknownWithCode.captureSCStreamErrorCode == nil)
  }

  @Test func ignoresMalformedCaptureTelemetryWhenItDoesNotApply() throws {
    let report = makeFailedCaptureReport(
      source: .delegateStoppedWithKnownSCError,
      code: .userStopped
    )
    let encoded = try JSONEncoder().encode(report)
    let currentObject = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )

    var legacyObject = currentObject
    legacyObject["schemaVersion"] = 9
    legacyObject["captureFailureSource"] = ["future": "PRIVATE_LEGACY_SENTINEL"]
    legacyObject["captureSCStreamErrorCode"] = 9_999

    var completedObject = currentObject
    completedObject["runStatus"] = RuntimeVerificationRunStatus.completed.rawValue
    completedObject["captureFailureSource"] = "futureCompletedSource"
    completedObject["captureSCStreamErrorCode"] = ["private": "PRIVATE_COMPLETED_SENTINEL"]

    var nonCaptureFailureObject = currentObject
    nonCaptureFailureObject["failureCode"] = RuntimeVerificationFailureCode.windowNotFound.rawValue
    nonCaptureFailureObject["captureFailureSource"] = ["future": "PRIVATE_FAILURE_SENTINEL"]
    nonCaptureFailureObject["captureSCStreamErrorCode"] = false

    for object in [legacyObject, completedObject, nonCaptureFailureObject] {
      let data = try JSONSerialization.data(withJSONObject: object)
      let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: data)
      #expect(decoded.captureFailureSource == nil)
      #expect(decoded.captureSCStreamErrorCode == nil)
    }
  }

  @Test func malformedCurrentCaptureTelemetryNormalizesWithoutRetainingIt() throws {
    let report = makeFailedCaptureReport(source: .sampleStatusStopped, code: nil)
    let encoded = try JSONEncoder().encode(report)
    let currentObject = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )

    var malformedSourceObject = currentObject
    malformedSourceObject["captureFailureSource"] = "futurePrivateSource"
    malformedSourceObject["captureSCStreamErrorCode"] = ["private": "PRIVATE_CODE_SENTINEL"]

    var malformedCodeObject = currentObject
    malformedCodeObject["captureFailureSource"] =
      RuntimeCaptureFailureSource.sampleStatusStopped.rawValue
    malformedCodeObject["captureSCStreamErrorCode"] = ["private": "PRIVATE_TYPE_SENTINEL"]

    for object in [malformedSourceObject, malformedCodeObject] {
      let data = try JSONSerialization.data(withJSONObject: object)
      let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: data)
      let reencoded = try JSONEncoder().encode(decoded)
      let reencodedText = try #require(String(data: reencoded, encoding: .utf8))

      #expect(decoded.captureFailureSource == .unclassifiedCaptureFailure)
      #expect(decoded.captureSCStreamErrorCode == nil)
      #expect(!reencodedText.contains("PRIVATE_"))
      #expect(!reencodedText.contains("futurePrivateSource"))
    }
  }

  @Test func captureFailureNormalizationCoversEverySourceRule() {
    let codeRequiredSources: [RuntimeCaptureFailureSource] = [
      .delegateStoppedWithKnownSCError,
      .startFailedWithKnownSCError,
    ]
    let codeForbiddenSources: [RuntimeCaptureFailureSource] = [
      .sampleStatusStopped,
      .delegateStoppedWithUnknownSCError,
      .delegateStoppedWithUnknownError,
      .delegateBecameInactive,
      .startFailedWithUnknownSCError,
      .startFailedWithUnknownError,
      .unclassifiedCaptureFailure,
    ]

    for source in codeRequiredSources {
      let consistent = makeFailedCaptureReport(source: source, code: .systemStoppedStream)
      let missingCode = makeFailedCaptureReport(source: source, code: nil)
      #expect(consistent.captureFailureSource == source)
      #expect(consistent.captureSCStreamErrorCode == .systemStoppedStream)
      #expect(missingCode.captureFailureSource == .unclassifiedCaptureFailure)
      #expect(missingCode.captureSCStreamErrorCode == nil)
    }

    for source in codeForbiddenSources {
      let consistent = makeFailedCaptureReport(source: source, code: nil)
      let unexpectedCode = makeFailedCaptureReport(source: source, code: .systemStoppedStream)
      #expect(consistent.captureFailureSource == source)
      #expect(consistent.captureSCStreamErrorCode == nil)
      #expect(unexpectedCode.captureFailureSource == .unclassifiedCaptureFailure)
      #expect(unexpectedCode.captureSCStreamErrorCode == nil)
    }
  }

  @Test func failedCanvasReportsAlwaysUseABoundedFailureReason() {
    let explicit = makeFailedCanvasReport(
      slideCanvasFailureReason: .idleRepeatSurfaceGeometryUnavailableOrMismatched
    )
    let fallback = makeFailedCanvasReport(slideCanvasFailureReason: nil)
    let unrelated = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 1),
      requestedDurationSeconds: 1,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 7,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .failed,
      failureCode: .captureFailed,
      slideCanvasFailureReason: .confirmedFrameRejected,
      untrustedFailureDetail: nil,
      snapshots: []
    )

    #expect(
      explicit.slideCanvasFailureReason
        == .idleRepeatSurfaceGeometryUnavailableOrMismatched
    )
    #expect(fallback.slideCanvasFailureReason == .unclassifiedInvalidation)
    #expect(unrelated.slideCanvasFailureReason == nil)
  }

  @Test func decodesCurrentCanvasFailureWithoutReasonAsUnclassified() throws {
    let report = makeFailedCanvasReport(
      slideCanvasFailureReason: .confirmedFrameRejected
    )
    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "slideCanvasFailureReason")

    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(
      RuntimeVerificationReport.self,
      from: data
    )

    #expect(decoded.schemaVersion == RuntimeVerificationReport.currentSchemaVersion)
    #expect(decoded.failureCode == .slideCanvasConfirmationFailed)
    #expect(decoded.slideCanvasFailureReason == .unclassifiedInvalidation)
  }

  @Test func encodedReportExcludesCapturedContentKeys() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 1),
      requestedDurationSeconds: 1,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 7,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let data = try JSONEncoder().encode(report)
    let object = try JSONSerialization.jsonObject(with: data)
    let forbiddenKeys: Set<String> = [
      "image",
      "imageData",
      "ocrText",
      "recognizedText",
      "region",
      "regions",
      "occupiedRegions",
      "windowTitle",
      "targetWindowTitleSubstring",
      "slideID",
      "slideIdentifier",
      "slideIndex",
      "slidePath",
      "presentationPath",
      "presentationToken",
      "presentationSessionIdentifier",
      "presentationSessionToken",
      "displayID",
      "displayIdentifier",
      "screenRect",
      "contentRect",
      "scaleFactor",
      "contentScale",
      "canvasRegion",
      "targetRect",
      "errorDomain",
      "rawErrorCode",
      "localizedDescription",
      "userInfo",
      "underlyingError",
      "x",
      "y",
      "width",
      "height",
    ]

    #expect(allKeys(in: object).isDisjoint(with: forbiddenKeys))
  }

  @Test func encodesExactMetadataShapeWithCountersOnlyInsideSnapshots() throws {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 1),
      requestedDurationSeconds: 1,
      permissionWasRequested: true,
      permissionRequestReturned: true,
      preflightBefore: .notDetermined,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 7,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .failed,
      failureCode: .slideCanvasConfirmationFailed,
      slideCanvasFailureReason: .selectionConfirmationRejected,
      untrustedFailureDetail: nil,
      snapshots: [snapshot(invalidationReason: .confirmedFrameRejected)]
    )

    let data = try JSONEncoder().encode(report)
    let root = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let snapshots = try #require(root["snapshots"] as? [[String: Any]])
    let encodedSnapshot = try #require(snapshots.first)

    #expect(
      Set(root.keys) == [
        "schemaVersion",
        "startedAt",
        "finishedAt",
        "requestedDurationSeconds",
        "permissionWasRequested",
        "permissionRequestReturned",
        "preflightBefore",
        "preflightAfter",
        "matchedWindowCount",
        "selectedWindowID",
        "selectedBundleIdentifier",
        "slideCanvasConfirmationMode",
        "runStatus",
        "failureCode",
        "failureMessage",
        "slideCanvasFailureReason",
        "snapshots",
      ]
    )
    #expect(
      Set(encodedSnapshot.keys) == [
        "timestamp",
        "elapsedMilliseconds",
        "screenRecordingPermission",
        "captureState",
        "visionState",
        "slideCanvasState",
        "slideCanvasOverlayState",
        "slideCanvasInvalidationReason",
        "frameCount",
        "newFrameCount",
        "repeatedFrameCount",
        "stableFrameCount",
        "slideChangeCount",
        "slideIdentityState",
        "slideIdentityFrameSyncState",
        "slideIdentitySampleCount",
        "slideIdentityContinuityBreakCount",
        "contentRevisionCount",
        "latestContentRevisionEvent",
        "recognizedTextCount",
        "detectedRectangleCount",
        "strokeCandidateRegionCount",
        "occupiedRegionCount",
        "lastNewFrameAt",
        "latestDifferenceFromStableFrame",
      ]
    )
    #expect(root["contentRevisionCount"] == nil)
    #expect(root["strokeCandidateRegionCount"] == nil)
    #expect(root["slideCanvasConfirmationMode"] as? String == "noneRequested")
    #expect(
      root["slideCanvasFailureReason"] as? String == "selectionConfirmationRejected"
    )
    #expect(root["captureFailureSource"] == nil)
    #expect(root["captureSCStreamErrorCode"] == nil)
    #expect(encodedSnapshot["contentRevisionCount"] as? Int == 2)
    let contentRevisionEvent = try #require(
      encodedSnapshot["latestContentRevisionEvent"] as? [String: Any]
    )
    #expect(
      Set(contentRevisionEvent.keys) == [
        "ordinal",
        "evidenceStartedMachAbsoluteTime",
        "confirmedMachAbsoluteTime",
        "source",
      ]
    )
    #expect(contentRevisionEvent["ordinal"] as? Int == 2)
    #expect(
      contentRevisionEvent["evidenceStartedMachAbsoluteTime"] as? UInt64 == 12_300
    )
    #expect(contentRevisionEvent["confirmedMachAbsoluteTime"] as? UInt64 == 12_345)
    #expect(contentRevisionEvent["source"] as? String == "continuousDenseNew")
    #expect(encodedSnapshot["strokeCandidateRegionCount"] as? Int == 1)
    #expect(encodedSnapshot["slideIdentityState"] as? String == "identified")
    #expect(encodedSnapshot["slideIdentityFrameSyncState"] as? String == "waiting")
    #expect(encodedSnapshot["slideIdentitySampleCount"] as? Int == 12)
    #expect(encodedSnapshot["slideIdentityContinuityBreakCount"] as? Int == 1)
    #expect(encodedSnapshot["slideCanvasState"] as? String == "confirmed")
    #expect(encodedSnapshot["slideCanvasOverlayState"] as? String == "mapped")
    #expect(
      encodedSnapshot["slideCanvasInvalidationReason"] as? String
        == "confirmedFrameRejected"
    )
  }

  @Test func encodesExactBoundedCaptureFailureMetadataShape() throws {
    let report = makeFailedCaptureReport(
      source: .delegateStoppedWithKnownSCError,
      code: .systemStoppedStream,
      untrustedFailureDetail:
        "SCStreamErrorDomain=-3821 /Users/person/Documents/Unpublished Lecture.pptx"
    )

    let data = try JSONEncoder().encode(report)
    let root = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let encodedText = try #require(String(data: data, encoding: .utf8))

    #expect(
      Set(root.keys) == [
        "schemaVersion",
        "startedAt",
        "finishedAt",
        "requestedDurationSeconds",
        "permissionWasRequested",
        "preflightBefore",
        "preflightAfter",
        "matchedWindowCount",
        "selectedWindowID",
        "selectedBundleIdentifier",
        "slideCanvasConfirmationMode",
        "runStatus",
        "failureCode",
        "failureMessage",
        "captureFailureSource",
        "captureSCStreamErrorCode",
        "snapshots",
      ]
    )
    #expect(root["captureFailureSource"] as? String == "delegateStoppedWithKnownSCError")
    #expect(root["captureSCStreamErrorCode"] as? String == "systemStoppedStream")
    #expect(root["slideCanvasFailureReason"] == nil)
    #expect(!encodedText.contains("SCStreamErrorDomain"))
    #expect(!encodedText.contains("-3821"))
    #expect(!encodedText.contains("Unpublished Lecture.pptx"))
  }

  @Test func canvasConfirmationModeRawValuesAreStableMetadata() throws {
    let expected: [(RuntimeSlideCanvasConfirmationMode, String)] = [
      (.noneRequested, "noneRequested"),
      (.diagnosticFullFrame, "diagnosticFullFrame"),
    ]

    for (mode, rawValue) in expected {
      let encoded = try JSONEncoder().encode(mode)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
      #expect(
        try JSONDecoder().decode(RuntimeSlideCanvasConfirmationMode.self, from: encoded)
          == mode
      )
    }
  }

  @Test func captureFailureSourceRawValuesAreStableBoundedMetadata() throws {
    let expected: [(RuntimeCaptureFailureSource, String)] = [
      (.sampleStatusStopped, "sampleStatusStopped"),
      (.delegateStoppedWithKnownSCError, "delegateStoppedWithKnownSCError"),
      (.delegateStoppedWithUnknownSCError, "delegateStoppedWithUnknownSCError"),
      (.delegateStoppedWithUnknownError, "delegateStoppedWithUnknownError"),
      (.delegateBecameInactive, "delegateBecameInactive"),
      (.startFailedWithKnownSCError, "startFailedWithKnownSCError"),
      (.startFailedWithUnknownSCError, "startFailedWithUnknownSCError"),
      (.startFailedWithUnknownError, "startFailedWithUnknownError"),
      (.unclassifiedCaptureFailure, "unclassifiedCaptureFailure"),
    ]

    for (source, rawValue) in expected {
      let encoded = try JSONEncoder().encode(source)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
      #expect(
        try JSONDecoder().decode(RuntimeCaptureFailureSource.self, from: encoded)
          == source
      )
    }
  }

  @Test func scStreamErrorCodeRawValuesAreStableBoundedMetadata() throws {
    let expected: [(RuntimeSCStreamErrorCode, String)] = [
      (.userDeclined, "userDeclined"),
      (.failedToStart, "failedToStart"),
      (.missingEntitlements, "missingEntitlements"),
      (.failedApplicationConnectionInvalid, "failedApplicationConnectionInvalid"),
      (.failedApplicationConnectionInterrupted, "failedApplicationConnectionInterrupted"),
      (.failedNoMatchingApplicationContext, "failedNoMatchingApplicationContext"),
      (.attemptToStartStreamState, "attemptToStartStreamState"),
      (.attemptToStopStreamState, "attemptToStopStreamState"),
      (.attemptToUpdateFilterState, "attemptToUpdateFilterState"),
      (.attemptToConfigState, "attemptToConfigState"),
      (.internalError, "internalError"),
      (.invalidParameter, "invalidParameter"),
      (.noWindowList, "noWindowList"),
      (.noDisplayList, "noDisplayList"),
      (.noCaptureSource, "noCaptureSource"),
      (.removingStream, "removingStream"),
      (.userStopped, "userStopped"),
      (.failedToStartAudioCapture, "failedToStartAudioCapture"),
      (.failedToStopAudioCapture, "failedToStopAudioCapture"),
      (.failedToStartMicrophoneCapture, "failedToStartMicrophoneCapture"),
      (.systemStoppedStream, "systemStoppedStream"),
    ]

    for (code, rawValue) in expected {
      let encoded = try JSONEncoder().encode(code)
      #expect(String(decoding: encoded, as: UTF8.self) == "\"\(rawValue)\"")
      #expect(
        try JSONDecoder().decode(RuntimeSCStreamErrorCode.self, from: encoded) == code
      )
    }
  }

  @Test func replacesUntrustedFailureDetailsWithFixedSafeMessages() throws {
    let sensitiveSentinel =
      "PRIVATE_WINDOW_TITLE /Users/person/Documents/Unpublished Lecture.pptx"
    let expectedMessages: [(RuntimeVerificationFailureCode, String)] = [
      (.screenRecordingUnavailable, "Screen Recording access is unavailable."),
      (.windowNotFound, "No PowerPoint window matched the requested selection."),
      (
        .ambiguousWindow,
        "More than one PowerPoint window matched the requested selection."
      ),
      (.captureFailed, "PowerPoint window capture failed."),
      (
        .captureFrameUnavailable,
        "No capturable PowerPoint frame was delivered."
      ),
      (
        .slideCanvasConfirmationFailed,
        "The requested slide canvas could not be confirmed."
      ),
      (.outputWriteFailed, "The runtime verification report could not be written."),
      (.internalFailure, "Runtime verification failed."),
    ]

    for (failureCode, expectedMessage) in expectedMessages {
      let report = RuntimeVerificationReport(
        startedAt: Date(timeIntervalSince1970: 0),
        finishedAt: Date(timeIntervalSince1970: 1),
        requestedDurationSeconds: 1,
        permissionWasRequested: false,
        permissionRequestReturned: nil,
        preflightBefore: .authorized,
        preflightAfter: .authorized,
        matchedWindowCount: 1,
        selectedWindowID: 7,
        selectedBundleIdentifier: "com.microsoft.Powerpoint",
        runStatus: .failed,
        failureCode: failureCode,
        untrustedFailureDetail: sensitiveSentinel,
        snapshots: []
      )

      #expect(report.failureMessage == expectedMessage)
      #expect(report.failureMessage == failureCode.safeReportMessage)

      let encoded = try JSONEncoder().encode(report)
      let encodedText = try #require(String(data: encoded, encoding: .utf8))
      #expect(!encodedText.contains(sensitiveSentinel))
      #expect(encodedText.contains(expectedMessage))
    }
  }

  private func snapshot(
    invalidationReason: RuntimeSlideCanvasInvalidationReason? = nil
  ) -> RuntimeVerificationSnapshot {
    RuntimeVerificationSnapshot(
      timestamp: Date(timeIntervalSince1970: 1_788_045_601),
      elapsedMilliseconds: 1_000,
      screenRecordingPermission: .authorized,
      captureState: .capturing,
      visionState: .completed,
      slideCanvasState: .confirmed,
      slideCanvasOverlayState: .mapped,
      slideCanvasInvalidationReason: invalidationReason,
      frameCount: 10,
      newFrameCount: 1,
      repeatedFrameCount: 9,
      stableFrameCount: 1,
      slideChangeCount: 0,
      slideIdentityState: .identified,
      slideIdentityFrameSyncState: .waiting,
      slideIdentitySampleCount: 12,
      slideIdentityContinuityBreakCount: 1,
      contentRevisionCount: 2,
      latestContentRevisionEvent: RuntimeContentRevisionEvent(
        ordinal: 2,
        evidenceStartedMachAbsoluteTime: 12_300,
        confirmedMachAbsoluteTime: 12_345,
        source: .continuousDenseNew
      ),
      recognizedTextCount: 3,
      detectedRectangleCount: 2,
      strokeCandidateRegionCount: 1,
      occupiedRegionCount: 4,
      lastNewFrameAt: Date(timeIntervalSince1970: 1_788_045_601),
      latestDifferenceFromStableFrame: 0
    )
  }

  private func currentReportJSONObject() throws -> [String: Any] {
    let report = RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 1_788_045_600),
      finishedAt: Date(timeIntervalSince1970: 1_788_045_612),
      requestedDurationSeconds: 12,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 42,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )
    let encoded = try JSONEncoder().encode(report)
    return try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
  }

  private func makeFailedCanvasReport(
    slideCanvasFailureReason: RuntimeSlideCanvasInvalidationReason?
  ) -> RuntimeVerificationReport {
    RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 1),
      requestedDurationSeconds: 1,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 7,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .failed,
      failureCode: .slideCanvasConfirmationFailed,
      slideCanvasFailureReason: slideCanvasFailureReason,
      untrustedFailureDetail: nil,
      snapshots: []
    )
  }

  private func makeFailedCaptureReport(
    source: RuntimeCaptureFailureSource?,
    code: RuntimeSCStreamErrorCode?,
    untrustedFailureDetail: String? = nil
  ) -> RuntimeVerificationReport {
    RuntimeVerificationReport(
      startedAt: Date(timeIntervalSince1970: 0),
      finishedAt: Date(timeIntervalSince1970: 1),
      requestedDurationSeconds: 1,
      permissionWasRequested: false,
      permissionRequestReturned: nil,
      preflightBefore: .authorized,
      preflightAfter: .authorized,
      matchedWindowCount: 1,
      selectedWindowID: 7,
      selectedBundleIdentifier: "com.microsoft.Powerpoint",
      runStatus: .failed,
      failureCode: .captureFailed,
      captureFailureSource: source,
      captureSCStreamErrorCode: code,
      untrustedFailureDetail: untrustedFailureDetail,
      snapshots: []
    )
  }

  private func decodedCaptureReport(
    source: String?,
    code: String?
  ) throws -> RuntimeVerificationReport {
    let report = makeFailedCaptureReport(
      source: .sampleStatusStopped,
      code: nil
    )
    let encoded = try JSONEncoder().encode(report)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    if let source {
      object["captureFailureSource"] = source
    } else {
      object.removeValue(forKey: "captureFailureSource")
    }
    if let code {
      object["captureSCStreamErrorCode"] = code
    } else {
      object.removeValue(forKey: "captureSCStreamErrorCode")
    }
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(RuntimeVerificationReport.self, from: data)
  }

  private func allKeys(in value: Any) -> Set<String> {
    if let dictionary = value as? [String: Any] {
      return dictionary.reduce(into: Set(dictionary.keys)) { keys, element in
        keys.formUnion(allKeys(in: element.value))
      }
    }
    if let array = value as? [Any] {
      return array.reduce(into: []) { keys, element in
        keys.formUnion(allKeys(in: element))
      }
    }
    return []
  }
}
