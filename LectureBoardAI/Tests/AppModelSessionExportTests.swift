import CoreGraphics
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct AppModelSessionExportTests {
  @Test func retainsPublicScenesInSlideOrderAndCoalescesRepeatedSlideUpdates() async {
    let model = AppModel(
      permissionService: PermissionService(
        screenCaptureClient: SessionExportAuthorizedPermissionClient()
      ),
      windowCapture: SessionExportNoopCapture()
    )
    model.powerPointWindows = [
      PowerPointWindowDescriptor(
        id: 42,
        title: "Session export test window",
        applicationName: "Microsoft PowerPoint",
        ownerProcessID: 700,
        bundleIdentifier: "com.microsoft.Powerpoint",
        frame: .zero
      )
    ]
    model.selectedPowerPointWindowID = 42

    await model.startWindowCapture()
    #expect(model.captureStatus == .capturing)

    model.boardScene = scene(slideNumber: 1, text: "first")
    model.boardScene = scene(slideNumber: 1, text: "updated")
    model.boardScene = scene(slideNumber: 3, text: "third")
    model.boardScene = scene(slideNumber: 1, text: "revisited")
    #expect(model.lectureSessionScenes.map(\.slideNumber) == [1, 3, 1])
    #expect(model.lectureSessionScenes[0].elements.first?.text == "updated")
    #expect(model.lectureSessionScenes[2].elements.first?.text == "revisited")

    await model.stopWindowCapture()
    #expect(model.lectureSessionScenes.map(\.slideNumber) == [1, 3, 1])
    #expect(model.canExportLectureSession)

    await model.startWindowCapture()
    #expect(model.lectureSessionScenes.isEmpty)
    await model.stopWindowCapture()
  }

  private func scene(slideNumber: Int, text: String) -> BoardScene {
    BoardScene(
      slideNumber: slideNumber,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1),
          text: text
        )
      ]
    )
  }
}

@MainActor
private final class SessionExportAuthorizedPermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }

  func requestAccess() -> Bool { true }
}

private struct SessionExportNoopCapture: PowerPointWindowCapturing {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {}

  func stop(operationID: CaptureOperationID) async {}
}
