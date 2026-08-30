import Testing

@testable import LectureBoard_AI

struct RuntimeVerificationLaunchPolicyTests {
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
