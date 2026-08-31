import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct RuntimeVerificationCanvasConfirmationPolicyTests {
  @Test func recordsWhetherCanvasConfirmationWasRuntimeDiagnostic() {
    #expect(
      RuntimeVerificationCanvasConfirmationPolicy.reportMode(for: .currentBehavior)
        == .noneRequested
    )
    #expect(
      RuntimeVerificationCanvasConfirmationPolicy.reportMode(for: .confirmFullFrame)
        == .diagnosticFullFrame
    )
  }

  @Test func leavesEveryNormalRuntimeCanvasStateUnchanged() {
    let statuses: [SlideCanvasStatus] = [
      .unavailable,
      .waitingForFrame,
      .needsConfirmation,
      .selecting,
      .confirmed,
      .invalidated,
    ]

    for status in statuses {
      #expect(
        RuntimeVerificationCanvasConfirmationPolicy.action(
          for: .currentBehavior,
          status: status
        ) == .leaveUnchanged
      )
    }
  }

  @Test func advancesExplicitFullFrameConfirmationWithoutWeakFallbacks() {
    let expectations: [(SlideCanvasStatus, RuntimeVerificationCanvasConfirmationAction)] = [
      (.waitingForFrame, .waitForFrame),
      (.needsConfirmation, .beginSelection),
      (.selecting, .confirmFullFrame),
      (.confirmed, .complete),
      (.unavailable, .failClosed),
      (.invalidated, .failClosed),
    ]

    for (status, expected) in expectations {
      #expect(
        RuntimeVerificationCanvasConfirmationPolicy.action(
          for: .confirmFullFrame,
          status: status
        ) == expected
      )
    }
  }

  @Test func distinguishesNoFrameDeliveryFromOtherConfirmationFailures() {
    #expect(
      RuntimeVerificationCanvasConfirmationPolicy.failureCode(
        for: .waitingForFrame,
        capturedFrameCount: 0
      ) == .captureFrameUnavailable
    )
    #expect(
      RuntimeVerificationCanvasConfirmationPolicy.failureCode(
        for: .waitingForFrame,
        capturedFrameCount: 1
      ) == .slideCanvasConfirmationFailed
    )
    #expect(
      RuntimeVerificationCanvasConfirmationPolicy.failureCode(
        for: .invalidated,
        capturedFrameCount: 0
      ) == .slideCanvasConfirmationFailed
    )
  }
}
