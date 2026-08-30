import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct RuntimeVerificationPermissionPolicyTests {
  @Test func requestsOnlyWhenPreflightFailsAndTheDedicatedFlagIsPresent() {
    #expect(
      RuntimeVerificationPermissionPolicy.shouldRequestAccess(
        isAuthorized: false,
        requestFlagIsPresent: true
      )
    )
    #expect(
      !RuntimeVerificationPermissionPolicy.shouldRequestAccess(
        isAuthorized: true,
        requestFlagIsPresent: true
      )
    )
    #expect(
      !RuntimeVerificationPermissionPolicy.shouldRequestAccess(
        isAuthorized: false,
        requestFlagIsPresent: false
      )
    )
  }

  @Test func doesNotInferDenialFromABooleanRequestResult() {
    #expect(
      RuntimeVerificationPermissionPolicy.state(isAuthorized: false) == .unknown
    )
    #expect(
      RuntimeVerificationPermissionPolicy.state(
        isAuthorized: false,
        requestWasAttempted: true,
        requestReturned: false
      ) == .unknown
    )
    #expect(
      RuntimeVerificationPermissionPolicy.state(
        isAuthorized: true,
        requestWasAttempted: true,
        requestReturned: false
      ) == .authorized
    )
  }
}
