import Testing

@testable import LectureBoard_AI

@MainActor
struct AppModelPermissionTests {
  @Test func screenCaptureActionRequestsOnlyScreenCaptureAccess() {
    let client = AppModelScreenCapturePermissionClientSpy()
    let service = PermissionService(screenCaptureClient: client)
    let model = AppModel(permissionService: service)

    #expect(model.requestScreenCapturePermission())
    #expect(client.requestCount == 1)
  }
}

@MainActor
private final class AppModelScreenCapturePermissionClientSpy: ScreenCapturePermissionClient {
  private(set) var requestCount = 0

  var isAuthorized: Bool { false }

  func requestAccess() -> Bool {
    requestCount += 1
    return true
  }
}
