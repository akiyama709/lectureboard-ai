import Combine
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

  @Test func recheckPublishesWithoutRequestingAndReadsLatestPreflight() {
    let client = AppModelScreenCapturePermissionClientSpy()
    let service = PermissionService(screenCaptureClient: client)
    let model = AppModel(permissionService: service)
    var notifications = 0
    let cancellable = model.objectWillChange.sink { _ in notifications += 1 }

    #expect(!service.screenCaptureAccessGranted)
    client.isAuthorizedValue = true
    model.recheckScreenCapturePermission()
    #expect(service.screenCaptureAccessGranted)
    #expect(client.requestCount == 0)

    client.isAuthorizedValue = false
    model.recheckScreenCapturePermission()
    #expect(!service.screenCaptureAccessGranted)
    #expect(client.requestCount == 0)
    #expect(notifications == 2)
    _ = cancellable
  }
}

@MainActor
private final class AppModelScreenCapturePermissionClientSpy: ScreenCapturePermissionClient {
  private(set) var requestCount = 0
  var isAuthorizedValue = false

  var isAuthorized: Bool { isAuthorizedValue }

  func requestAccess() -> Bool {
    requestCount += 1
    return true
  }
}
