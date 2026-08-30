import Foundation

public enum RuntimeVerificationRunStatus: String, Codable, Equatable, Sendable {
  /// The scheduled observation run reached its end. This does not assert functional success.
  case completed
  case failed
}

public enum RuntimeVerificationFailureCode: String, Codable, Equatable, Sendable {
  case screenRecordingUnavailable
  case windowNotFound
  case ambiguousWindow
  case captureFailed
  case outputWriteFailed
  case internalFailure

  public var safeReportMessage: String {
    switch self {
    case .screenRecordingUnavailable:
      "Screen Recording access is unavailable."
    case .windowNotFound:
      "No PowerPoint window matched the requested selection."
    case .ambiguousWindow:
      "More than one PowerPoint window matched the requested selection."
    case .captureFailed:
      "PowerPoint window capture failed."
    case .outputWriteFailed:
      "The runtime verification report could not be written."
    case .internalFailure:
      "Runtime verification failed."
    }
  }
}

/// A metadata-only runtime verification record that excludes captured content and window titles.
public struct RuntimeVerificationReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 1

  public let schemaVersion: Int
  public let startedAt: Date
  public let finishedAt: Date
  public let requestedDurationSeconds: TimeInterval
  public let permissionWasRequested: Bool
  public let permissionRequestReturned: Bool?
  public let preflightBefore: ScreenRecordingPermissionState
  public let preflightAfter: ScreenRecordingPermissionState
  public let matchedWindowCount: Int
  public let selectedWindowID: UInt32?
  public let selectedBundleIdentifier: String?
  public let runStatus: RuntimeVerificationRunStatus
  public let failureCode: RuntimeVerificationFailureCode?
  public let failureMessage: String?
  public let snapshots: [RuntimeVerificationSnapshot]

  public init(
    schemaVersion: Int = currentSchemaVersion,
    startedAt: Date,
    finishedAt: Date,
    requestedDurationSeconds: TimeInterval,
    permissionWasRequested: Bool,
    permissionRequestReturned: Bool?,
    preflightBefore: ScreenRecordingPermissionState,
    preflightAfter: ScreenRecordingPermissionState,
    matchedWindowCount: Int,
    selectedWindowID: UInt32?,
    selectedBundleIdentifier: String?,
    runStatus: RuntimeVerificationRunStatus,
    failureCode: RuntimeVerificationFailureCode?,
    untrustedFailureDetail _: String?,
    snapshots: [RuntimeVerificationSnapshot]
  ) {
    let fallbackDate = Date(timeIntervalSince1970: 0)
    let normalizedStartedAt =
      startedAt.timeIntervalSinceReferenceDate.isFinite
      ? startedAt
      : fallbackDate
    let finiteFinishedAt =
      finishedAt.timeIntervalSinceReferenceDate.isFinite
      ? finishedAt
      : normalizedStartedAt

    self.schemaVersion = max(schemaVersion, Self.currentSchemaVersion)
    self.startedAt = normalizedStartedAt
    self.finishedAt = max(finiteFinishedAt, normalizedStartedAt)
    self.requestedDurationSeconds =
      requestedDurationSeconds.isFinite
      ? max(requestedDurationSeconds, 0)
      : 0
    self.permissionWasRequested = permissionWasRequested
    self.permissionRequestReturned = permissionRequestReturned
    self.preflightBefore = preflightBefore
    self.preflightAfter = preflightAfter
    self.matchedWindowCount = max(matchedWindowCount, 0)
    self.selectedWindowID = selectedWindowID
    self.selectedBundleIdentifier = Self.normalizedMetadata(selectedBundleIdentifier)
    self.runStatus = runStatus
    if runStatus == .completed {
      self.failureCode = nil
      self.failureMessage = nil
    } else {
      let resolvedFailureCode = failureCode ?? .internalFailure
      self.failureCode = resolvedFailureCode
      self.failureMessage = resolvedFailureCode.safeReportMessage
    }
    self.snapshots = snapshots
  }

  private static func normalizedMetadata(_ value: String?) -> String? {
    guard let value else { return nil }
    let normalized =
      value
      .replacingOccurrences(of: "\0", with: "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}
