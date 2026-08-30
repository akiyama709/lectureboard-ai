import AppKit
import Foundation

@MainActor
final class RuntimeVerificationApplicationDelegate: NSObject, NSApplicationDelegate {
  private var launchState = RuntimeVerificationLaunchPolicy.State()
  private var startAction: (@MainActor () async -> Void)?
  private var verificationTask: Task<Void, Never>?

  func configureRuntimeVerification(
    start: @escaping @MainActor () async -> Void
  ) {
    startAction = start
    handle(.runtimeVerificationConfigured)
  }

  func configureInvalidRuntimeVerification(errorDescription: String) {
    configureRuntimeVerification {
      let message = "Invalid runtime verification arguments: \(errorDescription)\n"
      if let data = message.data(using: .utf8) {
        FileHandle.standardError.write(data)
      }
      NSApplication.shared.terminate(nil)
    }
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    handle(.applicationDidFinishLaunching)
  }

  private func handle(_ event: RuntimeVerificationLaunchPolicy.Event) {
    let action = RuntimeVerificationLaunchPolicy.transition(
      state: &launchState,
      event: event
    )
    guard action == .startRuntimeVerification, let startAction else { return }

    self.startAction = nil
    verificationTask = Task {
      await startAction()
    }
  }
}

enum RuntimeVerificationLaunchPolicy {
  struct State: Equatable {
    fileprivate var isRuntimeVerificationConfigured = false
    fileprivate var didFinishApplicationLaunch = false
    fileprivate var didStartRuntimeVerification = false
  }

  enum Event: Equatable {
    case runtimeVerificationConfigured
    case applicationDidFinishLaunching
  }

  enum Action: Equatable {
    case none
    case startRuntimeVerification
  }

  static func transition(state: inout State, event: Event) -> Action {
    switch event {
    case .runtimeVerificationConfigured:
      state.isRuntimeVerificationConfigured = true
    case .applicationDidFinishLaunching:
      state.didFinishApplicationLaunch = true
    }

    guard state.isRuntimeVerificationConfigured,
      state.didFinishApplicationLaunch,
      !state.didStartRuntimeVerification
    else {
      return .none
    }

    state.didStartRuntimeVerification = true
    return .startRuntimeVerification
  }
}
