import Testing

@testable import LectureBoard_AI

@MainActor
struct PermissionServiceTests {
  @Test
  func readsScreenCaptureStatusWithoutRequestingAccess() {
    let client = ScreenCapturePermissionClientSpy(
      isAuthorized: true,
      requestResult: false
    )
    let service = PermissionService(screenCaptureClient: client)

    #expect(service.screenCaptureAccessGranted)
    #expect(client.authorizationReadCount == 1)
    #expect(client.requestCount == 0)
  }

  @Test
  func requestsOnlyTheInjectedScreenCapturePermission() {
    let client = ScreenCapturePermissionClientSpy(
      isAuthorized: false,
      requestResult: true
    )
    let service = PermissionService(screenCaptureClient: client)

    #expect(service.requestScreenCaptureAccess())
    #expect(client.authorizationReadCount == 0)
    #expect(client.requestCount == 1)
  }

  @Test
  func preservesADeniedScreenCaptureRequestResult() {
    let client = ScreenCapturePermissionClientSpy(
      isAuthorized: false,
      requestResult: false
    )
    let service = PermissionService(screenCaptureClient: client)

    #expect(service.requestScreenCaptureAccess() == false)
    #expect(client.requestCount == 1)
  }
}

@MainActor
private final class ScreenCapturePermissionClientSpy: ScreenCapturePermissionClient {
  private let authorizationResult: Bool
  private let requestResult: Bool

  private(set) var authorizationReadCount = 0
  private(set) var requestCount = 0

  init(isAuthorized: Bool, requestResult: Bool) {
    authorizationResult = isAuthorized
    self.requestResult = requestResult
  }

  var isAuthorized: Bool {
    authorizationReadCount += 1
    return authorizationResult
  }

  func requestAccess() -> Bool {
    requestCount += 1
    return requestResult
  }
}
