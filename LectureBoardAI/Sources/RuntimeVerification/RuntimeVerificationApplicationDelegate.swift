import AppKit
import Foundation

@MainActor
protocol ApplicationTerminationReplying: AnyObject {
  func reply(toApplicationShouldTerminate shouldTerminate: Bool)
}

extension NSApplication: ApplicationTerminationReplying {}

@MainActor
final class RuntimeVerificationApplicationDelegate: NSObject, NSApplicationDelegate {
  private var launchState = RuntimeVerificationLaunchPolicy.State()
  private var startAction: (@MainActor () async -> Void)?
  private var verificationTask: Task<Void, Never>?
  private var terminationCleanup: (@MainActor () async -> Bool)?
  private var terminationTask: Task<Void, Never>?
  private var runtimeVerificationRequiresImmediateTermination = false

  func configureTerminationCleanup(
    _ cleanup: @escaping @MainActor () async -> Bool
  ) {
    terminationCleanup = cleanup
  }

  func configureRuntimeVerification(
    start: @escaping @MainActor () async -> Void
  ) {
    // Runtime verification owns its complete bounded stop before it calls `terminate`. AppKit's
    // nested termination event loop can prevent a new MainActor Swift task from running, so this
    // command-line mode must not enter the standard interactive-app `.terminateLater` handshake.
    runtimeVerificationRequiresImmediateTermination = true
    startAction = start
    handle(.runtimeVerificationConfigured)
  }

  func configureInvalidRuntimeVerification(errorDescription: String) {
    // Argument validation fails before a managed PowerPoint transaction can exist.  Route this
    // launch-only diagnostic directly through AppKit termination; waiting for the ordinary app
    // cleanup handshake can leave the command-line smoke process alive indefinitely.
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

  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    beginApplicationTermination(replying: sender)
  }

  /// AppKit permits asynchronous shutdown only through `.terminateLater`.  A second quit while
  /// exact cleanup is already running joins that handshake; it never starts a second PowerPoint
  /// exit.  If rollback cannot be confirmed, replying `false` keeps this process (and therefore
  /// the exact-object receipt) alive for a later explicit retry.
  func beginApplicationTermination(
    replying application: any ApplicationTerminationReplying
  ) -> NSApplication.TerminateReply {
    guard !runtimeVerificationRequiresImmediateTermination else {
      return .terminateNow
    }
    guard let terminationCleanup else { return .terminateNow }
    guard terminationTask == nil else { return .terminateLater }

    terminationTask = Task { @MainActor [weak self, weak application] in
      let safeToTerminate = await terminationCleanup()
      guard let self else { return }
      self.terminationTask = nil
      application?.reply(toApplicationShouldTerminate: safeToTerminate)
    }
    return .terminateLater
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
