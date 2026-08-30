import LectureBoardCore

enum RuntimeVerificationPermissionPolicy {
  static func shouldRequestAccess(
    isAuthorized: Bool,
    requestFlagIsPresent: Bool
  ) -> Bool {
    !isAuthorized && requestFlagIsPresent
  }

  static func state(
    isAuthorized: Bool,
    requestWasAttempted _: Bool = false,
    requestReturned _: Bool? = nil
  ) -> ScreenRecordingPermissionState {
    if isAuthorized {
      return .authorized
    }
    return .unknown
  }
}
