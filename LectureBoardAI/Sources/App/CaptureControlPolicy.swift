enum CaptureControlPolicy {
  static func canRefreshPowerPointWindows(
    screenCaptureAccessGranted: Bool
  ) -> Bool {
    screenCaptureAccessGranted
  }

  static func canStart(
    screenCaptureAccessGranted: Bool,
    hasSelectedWindow: Bool,
    captureStatus: AppModel.CaptureStatus
  ) -> Bool {
    guard screenCaptureAccessGranted, hasSelectedWindow else { return false }
    switch captureStatus {
    case .stopped, .error:
      return true
    case .starting, .capturing:
      return false
    }
  }
}
