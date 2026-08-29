import AVFoundation
import CoreGraphics
import Speech

@MainActor
final class PermissionService {
  var screenCaptureGranted: Bool {
    CGPreflightScreenCaptureAccess()
  }

  var microphoneGranted: Bool {
    AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
  }

  var speechRecognitionGranted: Bool {
    SFSpeechRecognizer.authorizationStatus() == .authorized
  }

  @discardableResult
  func requestScreenCapture() -> Bool {
    CGRequestScreenCaptureAccess()
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
