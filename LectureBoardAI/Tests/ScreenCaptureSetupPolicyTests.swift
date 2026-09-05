import Testing

@testable import LectureBoard_AI

struct ScreenCaptureSetupPolicyTests {
  @Test func permissionButtonIsShownOnlyWhilePreflightIsDenied() {
    #expect(ScreenCaptureSetupPolicy.showsPermissionButton(preflightGranted: false))
    #expect(!ScreenCaptureSetupPolicy.showsPermissionButton(preflightGranted: true))
  }

  @Test func windowRefreshIsEnabledOnlyAfterPreflightSucceeds() {
    #expect(!ScreenCaptureSetupPolicy.enablesWindowRefresh(preflightGranted: false))
    #expect(ScreenCaptureSetupPolicy.enablesWindowRefresh(preflightGranted: true))
  }

  @Test func refreshesOnAppearanceWhenPreflightIsGranted() {
    #expect(
      ScreenCaptureSetupPolicy.action(
        for: .viewAppeared(preflightGranted: true)
      ) == .refreshPowerPointWindows
    )
  }

  @Test func doesNothingOnAppearanceWhenPreflightIsNotGranted() {
    #expect(
      ScreenCaptureSetupPolicy.action(
        for: .viewAppeared(preflightGranted: false)
      ) == .none
    )
  }

  @Test func manualRefreshScansWhenPreflightIsGranted() {
    #expect(
      ScreenCaptureSetupPolicy.action(
        for: .refreshButtonPressed(preflightGranted: true)
      ) == .refreshPowerPointWindows
    )
  }

  @Test func manualRefreshDoesNothingWhenPreflightIsNotGranted() {
    #expect(
      ScreenCaptureSetupPolicy.action(
        for: .refreshButtonPressed(preflightGranted: false)
      ) == .none
    )
  }

  @Test func onlyThePermissionButtonStartsAPermissionRequest() {
    #expect(
      ScreenCaptureSetupPolicy.action(for: .permissionButtonPressed)
        == .requestScreenCapturePermission
    )
  }

  @Test func refreshesAfterAPermissionRequestSucceeds() {
    #expect(
      ScreenCaptureSetupPolicy.action(
        for: .permissionRequestCompleted(granted: true)
      ) == .refreshPowerPointWindows
    )
  }

  @Test func doesNothingAfterAPermissionRequestFails() {
    #expect(
      ScreenCaptureSetupPolicy.action(
        for: .permissionRequestCompleted(granted: false)
      ) == .none
    )
  }
}
