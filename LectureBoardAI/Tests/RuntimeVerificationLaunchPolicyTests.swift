import AppKit
import Testing

@testable import LectureBoard_AI

struct RuntimeVerificationLaunchPolicyTests {
  @Test @MainActor func terminationWithoutRegisteredCleanupCanProceedImmediately() {
    let delegate = RuntimeVerificationApplicationDelegate()
    let application = TerminationReplyRecorder()

    #expect(delegate.beginApplicationTermination(replying: application) == .terminateNow)
    #expect(application.replies.isEmpty)
  }

  @Test @MainActor func invalidRuntimeArgumentsBypassRegisteredCleanupAndTerminateImmediately() {
    let delegate = RuntimeVerificationApplicationDelegate()
    let application = TerminationReplyRecorder()
    var cleanupCalls = 0
    delegate.configureTerminationCleanup {
      cleanupCalls += 1
      return true
    }
    delegate.configureInvalidRuntimeVerification(errorDescription: "invalidWindowID")

    #expect(delegate.beginApplicationTermination(replying: application) == .terminateNow)
    #expect(cleanupCalls == 0)
    #expect(application.replies.isEmpty)
  }

  @Test @MainActor func validRuntimeVerificationAlsoTerminatesImmediatelyAfterRunnerCleanup() {
    let delegate = RuntimeVerificationApplicationDelegate()
    let application = TerminationReplyRecorder()
    var cleanupCalls = 0
    delegate.configureTerminationCleanup {
      cleanupCalls += 1
      return true
    }
    delegate.configureRuntimeVerification {}

    #expect(delegate.beginApplicationTermination(replying: application) == .terminateNow)
    #expect(cleanupCalls == 0)
    #expect(application.replies.isEmpty)
  }

  @Test @MainActor func terminationIsDeferredUntilCleanupConfirmsSuccess() async throws {
    let delegate = RuntimeVerificationApplicationDelegate()
    let cleanup = ControllableTerminationCleanup()
    let application = TerminationReplyRecorder()
    delegate.configureTerminationCleanup { await cleanup.run() }

    #expect(delegate.beginApplicationTermination(replying: application) == .terminateLater)
    #expect(delegate.beginApplicationTermination(replying: application) == .terminateLater)
    try await waitUntil { cleanup.calls == 1 }
    #expect(application.replies.isEmpty)

    cleanup.resume(with: true)
    try await waitUntil { application.replies == [true] }
    #expect(cleanup.calls == 1)
  }

  @Test @MainActor func failedCleanupCancelsTerminationAndANewQuitRetries() async throws {
    let delegate = RuntimeVerificationApplicationDelegate()
    let cleanup = ScriptedTerminationCleanup(results: [false, true])
    let application = TerminationReplyRecorder()
    delegate.configureTerminationCleanup { await cleanup.run() }

    #expect(delegate.beginApplicationTermination(replying: application) == .terminateLater)
    try await waitUntil { application.replies == [false] }
    #expect(delegate.beginApplicationTermination(replying: application) == .terminateLater)
    try await waitUntil { application.replies == [false, true] }
    #expect(cleanup.calls == 2)
  }

  @Test func startsAfterLaunchWhenConfigurationArrivesFirst() {
    var state = RuntimeVerificationLaunchPolicy.State()

    #expect(
      RuntimeVerificationLaunchPolicy.transition(
        state: &state,
        event: .runtimeVerificationConfigured
      ) == .none
    )
    #expect(
      RuntimeVerificationLaunchPolicy.transition(
        state: &state,
        event: .applicationDidFinishLaunching
      ) == .startRuntimeVerification
    )
  }

  @Test func startsAfterConfigurationWhenLaunchFinishesFirst() {
    var state = RuntimeVerificationLaunchPolicy.State()

    #expect(
      RuntimeVerificationLaunchPolicy.transition(
        state: &state,
        event: .applicationDidFinishLaunching
      ) == .none
    )
    #expect(
      RuntimeVerificationLaunchPolicy.transition(
        state: &state,
        event: .runtimeVerificationConfigured
      ) == .startRuntimeVerification
    )
  }

  @Test func repeatedEventsNeverStartMoreThanOnce() {
    var state = RuntimeVerificationLaunchPolicy.State()
    let events: [RuntimeVerificationLaunchPolicy.Event] = [
      .runtimeVerificationConfigured,
      .runtimeVerificationConfigured,
      .applicationDidFinishLaunching,
      .applicationDidFinishLaunching,
      .runtimeVerificationConfigured,
    ]

    let actions = events.map {
      RuntimeVerificationLaunchPolicy.transition(state: &state, event: $0)
    }

    #expect(actions.filter { $0 == .startRuntimeVerification }.count == 1)
  }

  @Test func standardLaunchNeverStartsRuntimeVerification() {
    var state = RuntimeVerificationLaunchPolicy.State()

    #expect(
      RuntimeVerificationLaunchPolicy.transition(
        state: &state,
        event: .applicationDidFinishLaunching
      ) == .none
    )
    #expect(
      RuntimeVerificationLaunchPolicy.transition(
        state: &state,
        event: .applicationDidFinishLaunching
      ) == .none
    )
  }
}

@MainActor
private final class TerminationReplyRecorder: ApplicationTerminationReplying {
  private(set) var replies: [Bool] = []
  func reply(toApplicationShouldTerminate shouldTerminate: Bool) {
    replies.append(shouldTerminate)
  }
}

@MainActor
private final class ControllableTerminationCleanup {
  private(set) var calls = 0
  private var continuation: CheckedContinuation<Bool, Never>?

  func run() async -> Bool {
    calls += 1
    return await withCheckedContinuation { continuation = $0 }
  }

  func resume(with result: Bool) {
    continuation?.resume(returning: result)
    continuation = nil
  }
}

@MainActor
private final class ScriptedTerminationCleanup {
  private(set) var calls = 0
  private var results: [Bool]
  init(results: [Bool]) { self.results = results }

  func run() async -> Bool {
    calls += 1
    return results.removeFirst()
  }
}

@MainActor
private func waitUntil(
  _ predicate: @escaping @MainActor () -> Bool
) async throws {
  for _ in 0..<200 {
    if predicate() { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for application lifecycle state")
  throw CancellationError()
}
