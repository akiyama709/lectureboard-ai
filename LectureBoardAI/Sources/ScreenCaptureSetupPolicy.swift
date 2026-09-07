enum ScreenCaptureSetupPolicy {
  enum Event: Equatable {
    case viewAppeared(preflightGranted: Bool)
    case sceneBecameActive(preflightGranted: Bool)
    case refreshButtonPressed(preflightGranted: Bool)
    case permissionButtonPressed
    case permissionRequestCompleted(granted: Bool)
  }

  enum Action: Equatable {
    case none
    case requestScreenCapturePermission
    case refreshPowerPointWindows
    case refreshPowerPointWindowsAfterSceneActivation
  }

  static func showsPermissionButton(preflightGranted: Bool) -> Bool {
    !preflightGranted
  }

  static func enablesWindowRefresh(preflightGranted: Bool) -> Bool {
    preflightGranted
  }

  static func action(for event: Event) -> Action {
    switch event {
    case .viewAppeared(preflightGranted: true):
      .refreshPowerPointWindows
    case .viewAppeared(preflightGranted: false):
      .none
    case .sceneBecameActive(preflightGranted: true):
      .refreshPowerPointWindowsAfterSceneActivation
    case .sceneBecameActive(preflightGranted: false):
      .none
    case .refreshButtonPressed(preflightGranted: true):
      .refreshPowerPointWindows
    case .refreshButtonPressed(preflightGranted: false):
      .none
    case .permissionButtonPressed:
      .requestScreenCapturePermission
    case .permissionRequestCompleted(granted: true):
      .refreshPowerPointWindows
    case .permissionRequestCompleted(granted: false):
      .none
    }
  }
}
