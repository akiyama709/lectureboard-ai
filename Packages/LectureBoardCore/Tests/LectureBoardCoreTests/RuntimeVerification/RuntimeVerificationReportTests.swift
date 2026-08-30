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
      runStatus: .completed,
      failureCode: nil,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
    )

    let data = try JSONEncoder().encode(report)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: data)

    #expect(decoded == report)
    #expect(decoded.schemaVersion == RuntimeVerificationReport.currentSchemaVersion)
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

    #expect(RuntimeVerificationReport.currentSchemaVersion == 3)
    #expect(report.schemaVersion == RuntimeVerificationReport.currentSchemaVersion)
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
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0]["stableFrameCount"] = 6
    snapshots[0]["slideChangeCount"] = 5
    snapshots[0]["contentRevisionCount"] = 2
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 2)
    #expect(decoded.snapshots[0].stableFrameCount == 6)
    #expect(decoded.snapshots[0].slideChangeCount == 5)
    #expect(decoded.snapshots[0].contentRevisionCount == 2)
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
    var snapshots = try #require(object["snapshots"] as? [[String: Any]])
    snapshots[0].removeValue(forKey: "contentRevisionCount")
    snapshots[0].removeValue(forKey: "strokeCandidateRegionCount")
    object["snapshots"] = snapshots

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(RuntimeVerificationReport.self, from: legacyData)

    #expect(decoded.schemaVersion == 1)
    #expect(decoded.snapshots[0].contentRevisionCount == 0)
    #expect(decoded.snapshots[0].strokeCandidateRegionCount == 0)
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
      untrustedFailureDetail: "not retained",
      snapshots: []
    )

    #expect(report.finishedAt == startedAt)
    #expect(report.requestedDurationSeconds == 0)
    #expect(report.failureCode == nil)
    #expect(report.failureMessage == nil)
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
      failureCode: .captureFailed,
      untrustedFailureDetail: nil,
      snapshots: [snapshot()]
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
        "runStatus",
        "failureCode",
        "failureMessage",
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
        "frameCount",
        "newFrameCount",
        "repeatedFrameCount",
        "stableFrameCount",
        "slideChangeCount",
        "contentRevisionCount",
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
    #expect(encodedSnapshot["contentRevisionCount"] as? Int == 2)
    #expect(encodedSnapshot["strokeCandidateRegionCount"] as? Int == 1)
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

  private func snapshot() -> RuntimeVerificationSnapshot {
    RuntimeVerificationSnapshot(
      timestamp: Date(timeIntervalSince1970: 1_788_045_601),
      elapsedMilliseconds: 1_000,
      screenRecordingPermission: .authorized,
      captureState: .capturing,
      visionState: .completed,
      frameCount: 10,
      newFrameCount: 1,
      repeatedFrameCount: 9,
      stableFrameCount: 1,
      slideChangeCount: 0,
      contentRevisionCount: 2,
      recognizedTextCount: 3,
      detectedRectangleCount: 2,
      strokeCandidateRegionCount: 1,
      occupiedRegionCount: 4,
      lastNewFrameAt: Date(timeIntervalSince1970: 1_788_045_601),
      latestDifferenceFromStableFrame: 0
    )
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
