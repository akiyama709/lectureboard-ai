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

/// Identifies the bounded lifecycle observation that ended capture without
/// retaining an error domain, localized description, or other untrusted data.
public enum RuntimeCaptureFailureSource: String, Codable, Equatable, Sendable {
  case sampleStatusStopped
  case delegateStoppedWithKnownSCError
  case delegateStoppedWithUnknownSCError
  case delegateStoppedWithUnknownError
  case delegateBecameInactive
  case startFailedWithKnownSCError
  case startFailedWithUnknownSCError
  case startFailedWithUnknownError
  case unclassifiedCaptureFailure

  fileprivate var requiresSCStreamErrorCode: Bool {
    switch self {
    case .delegateStoppedWithKnownSCError, .startFailedWithKnownSCError:
      true
    default:
      false
    }
  }
}

/// A privacy-bounded representation of the public ScreenCaptureKit stream
/// error codes known to the SDK used to build the producer.
public enum RuntimeSCStreamErrorCode: String, Codable, Equatable, Sendable {
  case userDeclined
  case failedToStart
  case missingEntitlements
  case failedApplicationConnectionInvalid
  case failedApplicationConnectionInterrupted
  case failedNoMatchingApplicationContext
  case attemptToStartStreamState
  case attemptToStopStreamState
  case attemptToUpdateFilterState
  case attemptToConfigState
  case internalError
  case invalidParameter
  case noWindowList
  case noDisplayList
  case noCaptureSource
  case removingStream
  case userStopped
  case failedToStartAudioCapture
  case failedToStopAudioCapture
  case failedToStartMicrophoneCapture
  case systemStoppedStream
}

/// A metadata-only runtime verification record that excludes captured content and window titles.
public struct RuntimeVerificationReport: Codable, Equatable, Sendable {
  public static let currentSchemaVersion = 10

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
  /// `nil` for completed runs, non-capture failures, and decoded schema 1
  /// through schema 9 reports. A current failed capture report always has one
  /// bounded source.
  public let captureFailureSource: RuntimeCaptureFailureSource?
  /// Present only when `captureFailureSource` identifies a known
  /// ScreenCaptureKit error. Raw numeric codes are never retained.
  public let captureSCStreamErrorCode: RuntimeSCStreamErrorCode?
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
    captureFailureSource: RuntimeCaptureFailureSource? = nil,
    captureSCStreamErrorCode: RuntimeSCStreamErrorCode? = nil,
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
      self.captureFailureSource = nil
      self.captureSCStreamErrorCode = nil
      self.slideCanvasFailureReason = nil
    } else {
      let resolvedFailureCode = failureCode ?? .internalFailure
      self.failureCode = resolvedFailureCode
      self.failureMessage = resolvedFailureCode.safeReportMessage
      if resolvedFailureCode == .captureFailed {
        let captureFailureTelemetry = Self.normalizedCaptureFailureTelemetry(
          source: captureFailureSource,
          code: captureSCStreamErrorCode
        )
        self.captureFailureSource = captureFailureTelemetry.source
        self.captureSCStreamErrorCode = captureFailureTelemetry.code
      } else {
        self.captureFailureSource = nil
        self.captureSCStreamErrorCode = nil
      }
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
    if schemaVersion >= 10,
      runStatus == .failed,
      failureCode == .captureFailed
    {
      var malformedTelemetry = false
      let decodedCaptureFailureSource: RuntimeCaptureFailureSource?
      do {
        decodedCaptureFailureSource = try container.decodeIfPresent(
          RuntimeCaptureFailureSource.self,
          forKey: .captureFailureSource
        )
      } catch {
        malformedTelemetry = true
        decodedCaptureFailureSource = nil
      }
      let decodedCaptureSCStreamErrorCode: RuntimeSCStreamErrorCode?
      do {
        decodedCaptureSCStreamErrorCode = try container.decodeIfPresent(
          RuntimeSCStreamErrorCode.self,
          forKey: .captureSCStreamErrorCode
        )
      } catch {
        malformedTelemetry = true
        decodedCaptureSCStreamErrorCode = nil
      }
      if malformedTelemetry {
        captureFailureSource = .unclassifiedCaptureFailure
        captureSCStreamErrorCode = nil
      } else {
        let captureFailureTelemetry = Self.normalizedCaptureFailureTelemetry(
          source: decodedCaptureFailureSource,
          code: decodedCaptureSCStreamErrorCode
        )
        captureFailureSource = captureFailureTelemetry.source
        captureSCStreamErrorCode = captureFailureTelemetry.code
      }
    } else {
      captureFailureSource = nil
      captureSCStreamErrorCode = nil
    }
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
    case captureFailureSource
    case captureSCStreamErrorCode
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

  private static func normalizedCaptureFailureTelemetry(
    source: RuntimeCaptureFailureSource?,
    code: RuntimeSCStreamErrorCode?
  ) -> (source: RuntimeCaptureFailureSource, code: RuntimeSCStreamErrorCode?) {
    guard let source else {
      return (.unclassifiedCaptureFailure, nil)
    }

    if source.requiresSCStreamErrorCode {
      guard let code else {
        return (.unclassifiedCaptureFailure, nil)
      }
      return (source, code)
    }

    guard code == nil else {
      return (.unclassifiedCaptureFailure, nil)
    }
    return (source, nil)
  }
}
