import AVFoundation
import CoreGraphics
import Speech

@MainActor
protocol ScreenCapturePermissionClient {
  var isAuthorized: Bool { get }

  @discardableResult
  func requestAccess() -> Bool
}

@MainActor
struct SystemScreenCapturePermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool {
    CGPreflightScreenCaptureAccess()
  }

  @discardableResult
  func requestAccess() -> Bool {
    CGRequestScreenCaptureAccess()
  }
}

@MainActor
final class PermissionService {
  private let screenCaptureClient: any ScreenCapturePermissionClient

  init(screenCaptureClient: (any ScreenCapturePermissionClient)? = nil) {
    self.screenCaptureClient =
      screenCaptureClient ?? SystemScreenCapturePermissionClient()
  }

  var screenCaptureAccessGranted: Bool {
    screenCaptureClient.isAuthorized
  }

  var screenCaptureGranted: Bool {
    screenCaptureAccessGranted
  }

  var microphoneGranted: Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
  }

  var speechRecognitionGranted: Bool {
    SFSpeechRecognizer.authorizationStatus() == .authorized
  }

  @discardableResult
  func requestScreenCaptureAccess() -> Bool {
    screenCaptureClient.requestAccess()
  }

  @discardableResult
  func requestScreenCapture() -> Bool {
    requestScreenCaptureAccess()
  }

  func requestMicrophone() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .audio)
  }

  func requestSpeechRecognition() async -> Bool {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }
}
