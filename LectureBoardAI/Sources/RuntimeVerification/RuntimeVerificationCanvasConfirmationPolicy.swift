import LectureBoardCore

enum RuntimeVerificationCanvasConfirmationAction: Equatable, Sendable {
  case leaveUnchanged
  case waitForFrame
  case beginSelection
  case confirmFullFrame
  case complete
  case failClosed
}

/// Keeps the diagnostic full-frame confirmation path explicit and separate
/// from the app's normal user-confirmed canvas workflow.
enum RuntimeVerificationCanvasConfirmationPolicy {
  static func reportMode(
    for selection: RuntimeVerificationCanvasSelection
  ) -> RuntimeSlideCanvasConfirmationMode {
    switch selection {
    case .currentBehavior:
      return .noneRequested
    case .confirmFullFrame:
      return .diagnosticFullFrame
    }
  }

  static func action(
    for selection: RuntimeVerificationCanvasSelection,
    status: SlideCanvasStatus
  ) -> RuntimeVerificationCanvasConfirmationAction {
    guard selection == .confirmFullFrame else {
      return .leaveUnchanged
    }

    switch status {
    case .waitingForFrame:
      return .waitForFrame
    case .needsConfirmation:
      return .beginSelection
    case .selecting:
      return .confirmFullFrame
    case .confirmed:
      return .complete
    case .unavailable, .invalidated:
      return .failClosed
    }
  }

  static func failureCode(
    for status: SlideCanvasStatus,
    capturedFrameCount: Int
  ) -> RuntimeVerificationFailureCode {
    if status == .waitingForFrame, capturedFrameCount == 0 {
      return .captureFrameUnavailable
    }
    return .slideCanvasConfirmationFailed
  }
}
