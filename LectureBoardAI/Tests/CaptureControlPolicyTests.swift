import Testing

@testable import LectureBoard_AI

struct CaptureControlPolicyTests {
  @Test func refreshRequiresScreenCaptureAccess() {
    #expect(
      CaptureControlPolicy.canRefreshPowerPointWindows(
        screenCaptureAccessGranted: false
      ) == false
    )
    #expect(
      CaptureControlPolicy.canRefreshPowerPointWindows(
        screenCaptureAccessGranted: true
      )
    )
  }

  @Test func requiresASelectedWindow() {
    #expect(
      CaptureControlPolicy.canStart(
        screenCaptureAccessGranted: true,
        hasSelectedWindow: false,
        captureStatus: .stopped
      ) == false
    )
  }

  @Test func preventsStartWithoutScreenCaptureAccessEvenWhenAWindowIsSelected() {
    #expect(
      CaptureControlPolicy.canStart(
        screenCaptureAccessGranted: false,
        hasSelectedWindow: true,
        captureStatus: .stopped
      ) == false
    )
  }

  @Test(arguments: [AppModel.CaptureStatus.starting, .capturing])
  func preventsOverlappingStarts(_ status: AppModel.CaptureStatus) {
    #expect(
      CaptureControlPolicy.canStart(
        screenCaptureAccessGranted: true,
        hasSelectedWindow: true,
        captureStatus: status
      ) == false
    )
  }

  @Test(arguments: [AppModel.CaptureStatus.stopped, .error("retry")])
  func allowsAStoppedOrFailedCaptureToStart(_ status: AppModel.CaptureStatus) {
    #expect(
      CaptureControlPolicy.canStart(
        screenCaptureAccessGranted: true,
        hasSelectedWindow: true,
        captureStatus: status
      )
    )
  }
}
