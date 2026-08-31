import Foundation

public enum RuntimeVerificationRunStatus: String, Codable, Equatable, Sendable {
  /// The scheduled observation run reached its end. This does not assert functional success.
  case completed
  case failed
}

/// Records whether the runtime verifier itself requested slide-canvas
/// confirmation. It deliberately does not infer that a person confirmed a
/// canvas when the verifier only observed existing app state.
public enum RuntimeSlideCanvasConfirmationMode: String, Codable, Equatable, Sendable {
  case noneRequested
  case diagnosticFullFrame
}

public enum RuntimeVerificationFailureCode: String, Codable, Equatable, Sendable {
  case screenRecordingUnavailable
  case windowNotFound
  case ambiguousWindow
  case captureFailed
  case captureFrameUnavailable
  case slideCanvasConfirmationFailed
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
    case .captureFrameUnavailable:
      "No capturable PowerPoint frame was delivered."
    case .slideCanvasConfirmationFailed:
      "The requested slide canvas could not be confirmed."
    case .outputWriteFailed:
      "The runtime verification report could not be written."
    case .internalFailure:
      "Runtime verification failed."
    }
  }
}

/// A metadata-only runtime verification record that excludes captured content and window titles.
public struct RuntimeVerificationReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 9

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
  /// `nil` only when decoding a schema 1 through schema 7 report that did not
  /// record confirmation provenance.
  public let slideCanvasConfirmationMode: RuntimeSlideCanvasConfirmationMode?
  public let runStatus: RuntimeVerificationRunStatus
  public let failureCode: RuntimeVerificationFailureCode?
  public let failureMessage: String?
  /// `nil` for completed runs, non-canvas failures, and decoded schema 1
  /// through schema 8 reports. A current failed canvas-confirmation report
  /// always has one bounded reason.
  public let slideCanvasFailureReason: RuntimeSlideCanvasInvalidationReason?
  public let snapshots: [RuntimeVerificationSnapshot]

  public init(
    schemaVersion _: Int = currentSchemaVersion,
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
    slideCanvasConfirmationMode: RuntimeSlideCanvasConfirmationMode = .noneRequested,
    runStatus: RuntimeVerificationRunStatus,
    failureCode: RuntimeVerificationFailureCode?,
    slideCanvasFailureReason: RuntimeSlideCanvasInvalidationReason? = nil,
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

    // Producers must never label the current payload as a future schema.
    // Decoding older reports still preserves the version encoded in that report.
    self.schemaVersion = Self.currentSchemaVersion
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
    self.slideCanvasConfirmationMode = slideCanvasConfirmationMode
    self.runStatus = runStatus
    if runStatus == .completed {
      self.failureCode = nil
      self.failureMessage = nil
      self.slideCanvasFailureReason = nil
    } else {
      let resolvedFailureCode = failureCode ?? .internalFailure
      self.failureCode = resolvedFailureCode
      self.failureMessage = resolvedFailureCode.safeReportMessage
      self.slideCanvasFailureReason =
        resolvedFailureCode == .slideCanvasConfirmationFailed
        ? slideCanvasFailureReason ?? .unclassifiedInvalidation
        : nil
    }
    self.snapshots = snapshots
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
    startedAt = try container.decode(Date.self, forKey: .startedAt)
    finishedAt = try container.decode(Date.self, forKey: .finishedAt)
    requestedDurationSeconds = try container.decode(
      TimeInterval.self,
      forKey: .requestedDurationSeconds
    )
    permissionWasRequested = try container.decode(
      Bool.self,
      forKey: .permissionWasRequested
    )
    permissionRequestReturned = try container.decodeIfPresent(
      Bool.self,
      forKey: .permissionRequestReturned
    )
    preflightBefore = try container.decode(
      ScreenRecordingPermissionState.self,
      forKey: .preflightBefore
    )
    preflightAfter = try container.decode(
      ScreenRecordingPermissionState.self,
      forKey: .preflightAfter
    )
    matchedWindowCount = try container.decode(Int.self, forKey: .matchedWindowCount)
    selectedWindowID = try container.decodeIfPresent(
      UInt32.self,
      forKey: .selectedWindowID
    )
    selectedBundleIdentifier = try container.decodeIfPresent(
      String.self,
      forKey: .selectedBundleIdentifier
    )
    slideCanvasConfirmationMode = try container.decodeIfPresent(
      RuntimeSlideCanvasConfirmationMode.self,
      forKey: .slideCanvasConfirmationMode
    )
    runStatus = try container.decode(
      RuntimeVerificationRunStatus.self,
      forKey: .runStatus
    )
    failureCode = try container.decodeIfPresent(
      RuntimeVerificationFailureCode.self,
      forKey: .failureCode
    )
    failureMessage = try container.decodeIfPresent(String.self, forKey: .failureMessage)
    snapshots = try container.decode(
      [RuntimeVerificationSnapshot].self,
      forKey: .snapshots
    )

    let decodedCanvasFailureReason = try container.decodeIfPresent(
      RuntimeSlideCanvasInvalidationReason.self,
      forKey: .slideCanvasFailureReason
    )
    if schemaVersion >= 9,
      runStatus == .failed,
      failureCode == .slideCanvasConfirmationFailed
    {
      slideCanvasFailureReason = decodedCanvasFailureReason ?? .unclassifiedInvalidation
    } else {
      slideCanvasFailureReason = nil
    }
  }

  private enum CodingKeys: String, CodingKey {
    case schemaVersion
    case startedAt
    case finishedAt
    case requestedDurationSeconds
    case permissionWasRequested
    case permissionRequestReturned
    case preflightBefore
    case preflightAfter
    case matchedWindowCount
    case selectedWindowID
    case selectedBundleIdentifier
    case slideCanvasConfirmationMode
    case runStatus
    case failureCode
    case failureMessage
    case slideCanvasFailureReason
    case snapshots
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
