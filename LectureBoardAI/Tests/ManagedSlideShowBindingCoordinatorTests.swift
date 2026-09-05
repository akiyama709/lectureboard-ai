import CoreGraphics
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct ManagedSlideShowBindingCoordinatorTests {
  @Test func candidateCorrelationRequiresTwoStablePostStartObservationsAndOneCommand() async throws
  {
    let frozen = try makeIdentity(windowID: 10)
    let sessionContext = ManagedSlideShowSessionContext(
      bindingSessionToken: "externally-created-session",
      frozenWindowIdentity: frozen
    )
    let baselineWindow = managedIdentity(windowID: 10)
    let slideShowWindow = managedIdentity(windowID: 42)
    let reader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 1, windows: [baselineWindow, slideShowWindow]),
        .observation(count: 1, windows: [slideShowWindow, baselineWindow]),
      ]
    )
    let starter = RecordingManagedSlideShowStarter()
    let waiter = RecordingManagedBindingWaiter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      sessionContext: sessionContext,
      observationReader: reader,
      slideShowStarter: starter,
      pollWaiter: waiter,
      maximumPostStartObservationCount: 5
    )

    let result = await coordinator.correlateCandidate(for: frozen)
    let candidate = try #require(result.success)
    let expectedCandidateIdentity = try makeIdentity(windowID: 42)

    #expect(candidate.candidateWindowIdentity == expectedCandidateIdentity)
    #expect(candidate.bindingSessionToken == sessionContext.bindingSessionToken)
    #expect(candidate.slideShowObjectToken == "object-token")
    let startRequests = await starter.requests
    #expect(startRequests.count == 1)
    #expect(startRequests.first?.frozenWindowIdentity == frozen)
    #expect(
      startRequests.first?.bindingSessionToken == candidate.bindingSessionToken
    )
    #expect(startRequests.first?.requiredActivePresentationCount == 1)
    #expect(startRequests.first?.requiredPreexistingSlideShowWindowCount == 0)
    #expect(await reader.bindingSessionTokens.count == 3)
    #expect(
      await Set(reader.bindingSessionTokens) == Set([candidate.bindingSessionToken])
    )
    #expect(await waiter.waitCount == 1)
  }

  @Test func malformedOrMismatchedExternalContextFailsBeforeAnyClientCall() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let otherFrozen = try makeIdentity(windowID: 11)

    let malformedReader = ScriptedManagedObservationReader(steps: [])
    let malformedStarter = RecordingManagedSlideShowStarter()
    let malformed = ManagedSlideShowBindingCoordinator(
      sessionContext: ManagedSlideShowSessionContext(
        bindingSessionToken: "  ",
        frozenWindowIdentity: frozen
      ),
      observationReader: malformedReader,
      slideShowStarter: malformedStarter
    )
    #expect(
      await malformed.correlateCandidate(for: frozen).failure
        == .malformedSessionContext
    )
    #expect(await malformedReader.readCount == 0)
    #expect(await malformedStarter.requests.isEmpty)

    let mismatchReader = ScriptedManagedObservationReader(steps: [])
    let mismatchStarter = RecordingManagedSlideShowStarter()
    let mismatch = ManagedSlideShowBindingCoordinator(
      sessionContext: ManagedSlideShowSessionContext(
        bindingSessionToken: "outer-session",
        frozenWindowIdentity: frozen
      ),
      observationReader: mismatchReader,
      slideShowStarter: mismatchStarter
    )
    #expect(
      await mismatch.correlateCandidate(for: otherFrozen).failure
        == .sessionContextMismatch
    )
    #expect(await mismatchReader.readCount == 0)
    #expect(await mismatchStarter.requests.isEmpty)
  }

  @Test func correlatedCandidateDoesNotExposeASemanticBindingType() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let addedWindow = managedIdentity(windowID: 42)
    let result = await ManagedSlideShowBindingCoordinator(
      observationReader: ScriptedManagedObservationReader(
        steps: [
          .observation(count: 0, windows: [baselineWindow]),
          .observation(count: 1, windows: [baselineWindow, addedWindow]),
          .observation(count: 1, windows: [baselineWindow, addedWindow]),
        ]
      ),
      slideShowStarter: RecordingManagedSlideShowStarter()
    ).correlateCandidate(for: try makeIdentity(windowID: 10))

    let candidate: ManagedSlideShowRuntimeCandidate = try #require(result.success)
    #expect(candidate.candidateWindowIdentity.windowID == 42)
    // The candidate type deliberately carries no slide role or ID-reuse assertion. A future
    // capture challenge must produce a distinct semantic binding type.
  }

  @Test func baselineMustShowNoScriptingSlideShowAndSendsNoCommandOnRejection() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let reader = ScriptedManagedObservationReader(
      steps: [.observation(count: 1, windows: [baselineWindow])]
    )
    let starter = RecordingManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter,
      pollWaiter: RecordingManagedBindingWaiter()
    )

    let result = await coordinator.correlateCandidate(
      for: try makeIdentity(windowID: 10)
    )

    #expect(
      result.failure
        == .policyRejected(.baselineSlideShowAlreadyActive)
    )
    #expect(await starter.requests.isEmpty)
  }

  @Test func exactlyOneActivePresentationIsRequiredBeforeAndAfterTheCommand() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)
    let slideShowWindow = managedIdentity(windowID: 42)

    for activePresentationCount in [0, 2] {
      let starter = RecordingManagedSlideShowStarter()
      let result = await ManagedSlideShowBindingCoordinator(
        observationReader: ScriptedManagedObservationReader(
          steps: [
            .observation(
              activePresentationCount: activePresentationCount,
              count: 0,
              windows: [baselineWindow]
            )
          ]
        ),
        slideShowStarter: starter
      ).correlateCandidate(for: frozen)

      #expect(
        result.failure
          == .policyRejected(.baselineActivePresentationCountNotOne)
      )
      #expect(await starter.requests.isEmpty)
    }

    let postStarter = RecordingManagedSlideShowStarter()
    let postResult = await ManagedSlideShowBindingCoordinator(
      observationReader: ScriptedManagedObservationReader(
        steps: [
          .observation(count: 0, windows: [baselineWindow]),
          .observation(
            activePresentationCount: 2,
            count: 1,
            windows: [baselineWindow, slideShowWindow]
          ),
        ]
      ),
      slideShowStarter: postStarter
    ).correlateCandidate(for: frozen)

    #expect(
      postResult.failure == .policyRejected(.activePresentationCountNotOne)
    )
    #expect(await postStarter.requests.count == 1)
  }

  @Test func candidateWindowIdentifierMustFitTheNativeExactIdentityRange() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let outOfRange = Int(CGWindowID.max) + 1
    let addedWindow = managedIdentity(windowID: outOfRange)
    let reader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 1, windows: [baselineWindow, addedWindow]),
        .observation(count: 1, windows: [baselineWindow, addedWindow]),
      ]
    )
    let starter = RecordingManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter,
      pollWaiter: RecordingManagedBindingWaiter()
    )

    let result = await coordinator.correlateCandidate(
      for: try makeIdentity(windowID: 10)
    )

    #expect(result.failure == .windowIdentifierOutOfRange)
    #expect(await starter.requests.count == 1)
  }

  @Test func frozenExactWindowMustRemainInTheValidatedBaseline() async throws {
    let reader = ScriptedManagedObservationReader(
      steps: [.observation(count: 0, windows: [managedIdentity(windowID: 11)])]
    )
    let starter = RecordingManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter
    )

    let result = await coordinator.correlateCandidate(
      for: try makeIdentity(windowID: 10)
    )

    #expect(result.failure == .frozenWindowUnavailable)
    #expect(await starter.requests.isEmpty)
  }

  @Test func timeoutUsesABoundedPollBudgetWithoutResendingTheCommand() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let reader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 0, windows: [baselineWindow]),
      ]
    )
    let starter = RecordingManagedSlideShowStarter()
    let waiter = RecordingManagedBindingWaiter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter,
      pollWaiter: waiter,
      maximumPostStartObservationCount: 3
    )

    let result = await coordinator.correlateCandidate(
      for: try makeIdentity(windowID: 10)
    )

    #expect(result.failure == .timedOut)
    #expect(await reader.readCount == 4)
    #expect(await starter.requests.count == 1)
    #expect(await waiter.waitCount == 2)
  }

  @Test(arguments: [0, 1, 2])
  func observationBudgetMinimumStillAllowsCandidateAndRepeat(
    configuredCount: Int
  ) async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let slideShowWindow = managedIdentity(windowID: 42)
    let reader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 1, windows: [baselineWindow, slideShowWindow]),
        .observation(count: 1, windows: [baselineWindow, slideShowWindow]),
      ]
    )
    let result = await ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: RecordingManagedSlideShowStarter(),
      maximumPostStartObservationCount: configuredCount
    ).correlateCandidate(for: try makeIdentity(windowID: 10))

    #expect(result.success != nil)
    #expect(await reader.readCount == 3)
  }

  @Test func observationBudgetIsBoundedAtBothEnds() {
    #expect(ManagedSlideShowBindingCoordinator.boundedPostStartObservationCount(0) == 2)
    #expect(ManagedSlideShowBindingCoordinator.boundedPostStartObservationCount(1) == 2)
    #expect(ManagedSlideShowBindingCoordinator.boundedPostStartObservationCount(2) == 2)
    #expect(ManagedSlideShowBindingCoordinator.boundedPostStartObservationCount(1_000) == 1_000)
    #expect(ManagedSlideShowBindingCoordinator.boundedPostStartObservationCount(1_001) == 1_000)
    #expect(ManagedSlideShowBindingCoordinator.boundedPostStartObservationCount(.max) == 1_000)
  }

  @Test func permissionAndPhaseErrorsAreNormalizedToBoundedFailures() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)

    let permissionReader = ScriptedManagedObservationReader(steps: [.permissionDenied])
    let permissionResult = await ManagedSlideShowBindingCoordinator(
      observationReader: permissionReader,
      slideShowStarter: RecordingManagedSlideShowStarter()
    ).correlateCandidate(for: frozen)
    #expect(permissionResult.failure == .permissionDenied)

    let failedReader = ScriptedManagedObservationReader(steps: [.readFailed])
    let readResult = await ManagedSlideShowBindingCoordinator(
      observationReader: failedReader,
      slideShowStarter: RecordingManagedSlideShowStarter()
    ).correlateCandidate(for: frozen)
    #expect(readResult.failure == .baselineReadFailed)

    let commandStarter = RecordingManagedSlideShowStarter(error: .controlled)
    let commandResult = await ManagedSlideShowBindingCoordinator(
      observationReader: ScriptedManagedObservationReader(
        steps: [.observation(count: 0, windows: [baselineWindow])]
      ),
      slideShowStarter: commandStarter
    ).correlateCandidate(for: frozen)
    #expect(commandResult.failure == .startCommandFailed)
  }

  @Test func malformedAndMismatchedStartReceiptsFailBeforePostStartObservation() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)

    let malformedResult = await ManagedSlideShowBindingCoordinator(
      observationReader: ScriptedManagedObservationReader(
        steps: [.observation(count: 0, windows: [baselineWindow])]
      ),
      slideShowStarter: RecordingManagedSlideShowStarter(
        receiptVariant: .empty
      )
    ).correlateCandidate(for: frozen)
    #expect(malformedResult.failure == .malformedStartReceipt)

    let whitespaceResult = await ManagedSlideShowBindingCoordinator(
      observationReader: ScriptedManagedObservationReader(
        steps: [.observation(count: 0, windows: [baselineWindow])]
      ),
      slideShowStarter: RecordingManagedSlideShowStarter(
        receiptVariant: .whitespaceObjectToken
      )
    ).correlateCandidate(for: frozen)
    #expect(whitespaceResult.failure == .malformedStartReceipt)

    for receiptVariant in [
      ManagedStartReceiptVariant.wrongSession,
      .wrongProcess,
      .wrongBundle,
    ] {
      let reader = ScriptedManagedObservationReader(
        steps: [.observation(count: 0, windows: [baselineWindow])]
      )
      let result = await ManagedSlideShowBindingCoordinator(
        observationReader: reader,
        slideShowStarter: RecordingManagedSlideShowStarter(
          receiptVariant: receiptVariant
        )
      ).correlateCandidate(for: frozen)

      #expect(result.failure == .startReceiptMismatch)
      #expect(await reader.readCount == 1)
    }
  }

  @Test func postStartReadAndWaitErrorsFailClosedWithoutASecondCommand() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)

    let postReader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .readFailed,
      ]
    )
    let postStarter = RecordingManagedSlideShowStarter()
    let postResult = await ManagedSlideShowBindingCoordinator(
      observationReader: postReader,
      slideShowStarter: postStarter
    ).correlateCandidate(for: frozen)
    #expect(postResult.failure == .postStartReadFailed)
    #expect(postResult.recoveryReceipt?.slideShowObjectToken == "object-token")
    #expect(await postStarter.requests.count == 1)

    let waitStarter = RecordingManagedSlideShowStarter()
    let waitResult = await ManagedSlideShowBindingCoordinator(
      observationReader: ScriptedManagedObservationReader(
        steps: [
          .observation(count: 0, windows: [baselineWindow]),
          .observation(count: 0, windows: [baselineWindow]),
        ]
      ),
      slideShowStarter: waitStarter,
      pollWaiter: RecordingManagedBindingWaiter(error: .controlled)
    ).correlateCandidate(for: frozen)
    #expect(waitResult.failure == .pollWaitFailed)
    #expect(waitResult.recoveryReceipt?.slideShowObjectToken == "object-token")
    #expect(await waitStarter.requests.count == 1)
  }

  @Test func possiblyDeliveredStartClassificationsSurviveCoordinatorBoundary() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let frozen = try makeIdentity(windowID: 10)
    let cases:
      [(
        PowerPointManagedSlideShowAppleEventClientFailure,
        ManagedSlideShowBindingCoordinatorFailure
      )] = [
        (.startCommandDeliveryUnknown, .startCommandDeliveryUnknown),
        (
          .startCommandReplyMissingPossiblyDelivered,
          .startCommandReplyMissingPossiblyDelivered
        ),
        (
          .startCommandReplyMalformedPossiblyDelivered,
          .startCommandReplyMalformedPossiblyDelivered
        ),
      ]

    for (clientFailure, expected) in cases {
      let result = await ManagedSlideShowBindingCoordinator(
        observationReader: ScriptedManagedObservationReader(
          steps: [.observation(count: 0, windows: [baselineWindow])]
        ),
        slideShowStarter: PowerPointFailingManagedSlideShowStarter(
          failure: clientFailure
        )
      ).correlateCandidate(for: frozen)

      #expect(result.failure == expected)
      #expect(result.recoveryReceipt == nil)
    }
  }

  @Test func possiblyDeliveredFailureWinsACompetingCallerCancellation() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let frozen = try makeIdentity(windowID: 10)
    let starter = ControllableManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: ScriptedManagedObservationReader(
        steps: [.observation(count: 0, windows: [baselineWindow])]
      ),
      slideShowStarter: starter
    )
    let attempt = Task {
      await coordinator.correlateCandidate(for: frozen)
    }
    try await waitUntil { await starter.requests.count == 1 }

    attempt.cancel()
    await starter.failOldest(.startCommandDeliveryUnknown)

    let result = await attempt.value
    #expect(result.failure == .startCommandDeliveryUnknown)
    #expect(result.recoveryReceipt == nil)
    #expect(await starter.requests.count == 1)
  }

  @Test func deterministicFreshObservationRequestsCanConfirmOneCandidate() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let slideShowWindow = managedIdentity(windowID: 42)
    let reader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 1, windows: [baselineWindow, slideShowWindow]),
        .observation(count: 1, windows: [baselineWindow, slideShowWindow]),
      ]
    )
    let clock = ScriptedManagedSlideShowBindingMachClock([10, 20, 30, 40, 50, 60])
    let result = await ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: RecordingManagedSlideShowStarter(),
      pollWaiter: RecordingManagedBindingWaiter(),
      machClock: clock
    ).correlateCandidate(for: try makeIdentity(windowID: 10))

    #expect(result.success?.candidateWindowIdentity.windowID == 42)
    let requests = await reader.requests
    #expect(requests.map(\.requestStartedMachAbsoluteTime) == [10, 30, 50])
    #expect(Set(requests.map(\.freshObservationToken)).count == 3)
    #expect(await clock.readCount == 6)
  }

  @Test func wrongOrReusedObservationRequestTokensFailClosed() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)
    let slideShowWindow = managedIdentity(windowID: 42)

    let wrongReader = ScriptedManagedObservationReader(
      steps: [
        .observation(
          count: 0,
          freshness: .fixedToken("wrong-request-token"),
          windows: [baselineWindow]
        )
      ]
    )
    let wrongStarter = RecordingManagedSlideShowStarter()
    let wrongResult = await ManagedSlideShowBindingCoordinator(
      observationReader: wrongReader,
      slideShowStarter: wrongStarter,
      machClock: ScriptedManagedSlideShowBindingMachClock([10, 20])
    ).correlateCandidate(for: frozen)

    #expect(wrongResult.failure == .observationRequestTokenMismatch)
    #expect(await wrongStarter.requests.isEmpty)

    let reusedReader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 1, windows: [baselineWindow, slideShowWindow]),
        .observation(
          count: 1,
          freshness: .previousToken,
          windows: [baselineWindow, slideShowWindow]
        ),
      ]
    )
    let reusedStarter = RecordingManagedSlideShowStarter()
    let reusedResult = await ManagedSlideShowBindingCoordinator(
      observationReader: reusedReader,
      slideShowStarter: reusedStarter,
      pollWaiter: RecordingManagedBindingWaiter(),
      machClock: ScriptedManagedSlideShowBindingMachClock([10, 20, 30, 40, 50, 60])
    ).correlateCandidate(for: frozen)

    #expect(reusedResult.failure == .observationRequestTokenMismatch)
    #expect(await reusedReader.readCount == 3)
    #expect(await reusedStarter.requests.count == 1)
  }

  @Test func cachedStaleAndFutureAcquisitionTimesFailClosed() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)
    let slideShowWindow = managedIdentity(windowID: 42)

    for invalidAcquisitionTime in [UInt64(0), 9, 21] {
      let starter = RecordingManagedSlideShowStarter()
      let result = await ManagedSlideShowBindingCoordinator(
        observationReader: ScriptedManagedObservationReader(
          steps: [
            .observation(
              count: 0,
              freshness: .fixedAcquisitionTime(invalidAcquisitionTime),
              windows: [baselineWindow]
            )
          ]
        ),
        slideShowStarter: starter,
        machClock: ScriptedManagedSlideShowBindingMachClock([10, 20])
      ).correlateCandidate(for: frozen)

      #expect(result.failure == .observationAcquisitionTimeOutOfBounds)
      #expect(await starter.requests.isEmpty)
    }

    let cachedReader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 1, windows: [baselineWindow, slideShowWindow]),
        .observation(
          count: 1,
          freshness: .previousAcquisitionTime,
          windows: [baselineWindow, slideShowWindow]
        ),
      ]
    )
    let cachedStarter = RecordingManagedSlideShowStarter()
    let cachedResult = await ManagedSlideShowBindingCoordinator(
      observationReader: cachedReader,
      slideShowStarter: cachedStarter,
      pollWaiter: RecordingManagedBindingWaiter(),
      machClock: ScriptedManagedSlideShowBindingMachClock([10, 20, 30, 40, 50, 60])
    ).correlateCandidate(for: frozen)

    #expect(cachedResult.failure == .observationAcquisitionTimeOutOfBounds)
    #expect(await cachedReader.readCount == 3)
    #expect(await cachedStarter.requests.count == 1)
  }

  @Test func machClockMustProgressStrictlyAcrossEveryObservationBracket() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)

    for times in [[UInt64(0)], [10, 10]] {
      let reader = ScriptedManagedObservationReader(
        steps: [.observation(count: 0, windows: [baselineWindow])]
      )
      let starter = RecordingManagedSlideShowStarter()
      let result = await ManagedSlideShowBindingCoordinator(
        observationReader: reader,
        slideShowStarter: starter,
        machClock: ScriptedManagedSlideShowBindingMachClock(times)
      ).correlateCandidate(for: frozen)

      #expect(result.failure == .observationClockInvalid)
      #expect(await starter.requests.isEmpty)
    }

    let repeatedRequestClockReader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 0, windows: [baselineWindow]),
      ]
    )
    let repeatedRequestClockStarter = RecordingManagedSlideShowStarter()
    let repeatedRequestClockResult = await ManagedSlideShowBindingCoordinator(
      observationReader: repeatedRequestClockReader,
      slideShowStarter: repeatedRequestClockStarter,
      machClock: ScriptedManagedSlideShowBindingMachClock([10, 20, 20])
    ).correlateCandidate(for: frozen)

    #expect(repeatedRequestClockResult.failure == .observationClockInvalid)
    #expect(await repeatedRequestClockReader.readCount == 1)
    #expect(await repeatedRequestClockStarter.requests.count == 1)

    let repeatedCompletionClockReader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 0, windows: [baselineWindow]),
      ]
    )
    let repeatedCompletionClockResult = await ManagedSlideShowBindingCoordinator(
      observationReader: repeatedCompletionClockReader,
      slideShowStarter: RecordingManagedSlideShowStarter(),
      machClock: ScriptedManagedSlideShowBindingMachClock([10, 20, 30, 30])
    ).correlateCandidate(for: frozen)

    #expect(repeatedCompletionClockResult.failure == .observationClockInvalid)
    #expect(await repeatedCompletionClockReader.readCount == 2)
  }

  @Test func explicitCancellationMakesABlockedOldReadUnusable() async throws {
    let reader = ControllableManagedObservationReader()
    let starter = RecordingManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter
    )
    let frozen = try makeIdentity(windowID: 10)

    let attempt = Task { await coordinator.correlateCandidate(for: frozen) }
    try await waitUntil { await reader.readCount == 1 }
    await coordinator.cancelCurrentAttempt()
    await reader.resumeOldest(count: 0, windows: [managedIdentity(windowID: 10)])

    #expect(await attempt.value.failure == .cancelled)
    #expect(await starter.requests.isEmpty)
  }

  @Test func callerTaskCancellationPropagatesBeforeAStartCommand() async throws {
    let reader = ControllableManagedObservationReader()
    let starter = RecordingManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter
    )
    let frozen = try makeIdentity(windowID: 10)

    let attempt = Task { await coordinator.correlateCandidate(for: frozen) }
    try await waitUntil { await reader.readCount == 1 }
    attempt.cancel()
    await reader.resumeOldest(count: 0, windows: [managedIdentity(windowID: 10)])

    #expect(await attempt.value.failure == .cancelled)
    #expect(await starter.requests.isEmpty)
  }

  @Test func blockedNonCooperativeWorkRejectsRebindBeforeAndAfterCancellation() async throws {
    let reader = ControllableManagedObservationReader()
    let starter = RecordingManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter,
      pollWaiter: RecordingManagedBindingWaiter()
    )
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)

    let first = Task { await coordinator.correlateCandidate(for: frozen) }
    try await waitUntil { await reader.readCount == 1 }

    #expect(
      await coordinator.correlateCandidate(for: frozen).failure
        == .priorAttemptStillDraining
    )
    #expect(await reader.readCount == 1)

    await coordinator.cancelCurrentAttempt()
    #expect(
      await coordinator.correlateCandidate(for: frozen).failure
        == .priorAttemptStillDraining
    )
    #expect(await reader.readCount == 1)

    await reader.resumeOldest(count: 0, windows: [baselineWindow])
    #expect(await first.value.failure == .cancelled)
    #expect(await reader.maximumConcurrentReadCount == 1)
    #expect(await starter.requests.isEmpty)
  }

  @Test func cancelledNonCooperativeStarterMustDrainBeforeAnotherAttempt() async throws {
    let baselineWindow = managedIdentity(windowID: 10)
    let reader = ScriptedManagedObservationReader(
      steps: [.observation(count: 0, windows: [baselineWindow])]
    )
    let starter = ControllableManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter
    )
    let frozen = try makeIdentity(windowID: 10)
    let recorder = ManagedCandidateResultRecorder()

    let attempt = Task {
      let result = await coordinator.correlateCandidate(for: frozen)
      await recorder.record(result)
      return result
    }
    try await waitUntil { await starter.requests.count == 1 }
    attempt.cancel()

    #expect(
      await coordinator.correlateCandidate(for: frozen).failure
        == .priorAttemptStillDraining
    )
    #expect(await recorder.result == nil)
    #expect(await starter.requests.count == 1)

    await starter.resumeOldest()
    let cancelledResult = await attempt.value
    #expect(cancelledResult.failure == .cancelled)
    #expect(
      cancelledResult.recoveryReceipt?.slideShowObjectToken
        == "controlled-object-token"
    )
    #expect(await recorder.result?.failure == .cancelled)
    #expect(await reader.readCount == 1)
    #expect(await starter.requests.count == 1)

    let afterDrain = await coordinator.correlateCandidate(for: frozen)
    #expect(afterDrain.failure == .baselineReadFailed)
    #expect(await starter.requests.count == 1)
  }

  @Test func cancelledNonCooperativePostReadCannotConfirmOrSendAnotherCommand() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)
    let slideShowWindow = managedIdentity(windowID: 42)
    let reader = ControllableManagedObservationReader()
    let starter = RecordingManagedSlideShowStarter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter,
      pollWaiter: RecordingManagedBindingWaiter()
    )
    let recorder = ManagedCandidateResultRecorder()

    let attempt = Task {
      let result = await coordinator.correlateCandidate(for: frozen)
      await recorder.record(result)
      return result
    }
    try await waitUntil { await reader.readCount == 1 }
    await reader.resumeOldest(count: 0, windows: [baselineWindow])
    try await waitUntil { await reader.readCount == 2 }
    attempt.cancel()

    #expect(
      await coordinator.correlateCandidate(for: frozen).failure
        == .priorAttemptStillDraining
    )
    #expect(await recorder.result == nil)
    #expect(await starter.requests.count == 1)

    await reader.resumeOldest(
      count: 1,
      windows: [baselineWindow, slideShowWindow]
    )
    let cancelledResult = await attempt.value
    #expect(cancelledResult.failure == .cancelled)
    #expect(
      cancelledResult.recoveryReceipt?.slideShowObjectToken == "object-token"
    )
    #expect(await recorder.result?.failure == .cancelled)
    #expect(await reader.readCount == 2)
    #expect(await starter.requests.count == 1)
  }

  @Test func cancelledNonCooperativeWaiterCannotStartAReplacementChain() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)
    let reader = ScriptedManagedObservationReader(
      steps: [
        .observation(count: 0, windows: [baselineWindow]),
        .observation(count: 0, windows: [baselineWindow]),
      ]
    )
    let starter = RecordingManagedSlideShowStarter()
    let waiter = ControllableManagedBindingWaiter()
    let coordinator = ManagedSlideShowBindingCoordinator(
      observationReader: reader,
      slideShowStarter: starter,
      pollWaiter: waiter
    )
    let recorder = ManagedCandidateResultRecorder()

    let attempt = Task {
      let result = await coordinator.correlateCandidate(for: frozen)
      await recorder.record(result)
      return result
    }
    try await waitUntil { await waiter.waitCount == 1 }
    attempt.cancel()

    #expect(
      await coordinator.correlateCandidate(for: frozen).failure
        == .priorAttemptStillDraining
    )
    #expect(await recorder.result == nil)
    #expect(await reader.readCount == 2)
    #expect(await starter.requests.count == 1)

    await waiter.resumeOldest()
    #expect(await attempt.value.failure == .cancelled)
    #expect(await recorder.result?.failure == .cancelled)
    #expect(await reader.readCount == 2)
    #expect(await starter.requests.count == 1)
  }

  @Test func concretePermissionAndPolicyFailuresSurviveCompetingCancellation() async throws {
    let frozen = try makeIdentity(windowID: 10)
    let baselineWindow = managedIdentity(windowID: 10)

    let permissionReader = ControllableManagedObservationReader()
    let permissionStarter = RecordingManagedSlideShowStarter()
    let permissionCoordinator = ManagedSlideShowBindingCoordinator(
      observationReader: permissionReader,
      slideShowStarter: permissionStarter
    )
    let permissionAttempt = Task {
      await permissionCoordinator.correlateCandidate(for: frozen)
    }
    try await waitUntil { await permissionReader.readCount == 1 }
    permissionAttempt.cancel()
    await permissionReader.failOldest(ManagedSlideShowBindingClientError.permissionDenied)

    #expect(await permissionAttempt.value.failure == .permissionDenied)
    #expect(await permissionStarter.requests.isEmpty)

    let policyReader = ControllableManagedObservationReader()
    let policyStarter = RecordingManagedSlideShowStarter()
    let policyCoordinator = ManagedSlideShowBindingCoordinator(
      observationReader: policyReader,
      slideShowStarter: policyStarter
    )
    let policyAttempt = Task {
      await policyCoordinator.correlateCandidate(for: frozen)
    }
    try await waitUntil { await policyReader.readCount == 1 }
    await policyCoordinator.cancelCurrentAttempt()
    await policyReader.resumeOldest(count: 1, windows: [baselineWindow])

    #expect(
      await policyAttempt.value.failure
        == .policyRejected(.baselineSlideShowAlreadyActive)
    )
    #expect(await policyStarter.requests.isEmpty)
  }

  private func makeIdentity(
    windowID: CGWindowID,
    processIdentifier: pid_t = 700
  ) throws -> PowerPointWindowIdentity {
    try #require(
      PowerPointWindowIdentity(
        windowID: windowID,
        ownerProcessID: processIdentifier,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      )
    )
  }

  private func managedIdentity(
    windowID: Int,
    processIdentifier: Int = 700
  ) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: processIdentifier,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )
  }
}

/// Existing fake scenarios use one explicit, externally created context. The production
/// coordinator has no context-generating convenience initializer.
extension ManagedSlideShowBindingCoordinator {
  fileprivate init(
    observationReader: any ManagedSlideShowCompositeObservationReading,
    slideShowStarter: any ManagedSlideShowStarting,
    pollWaiter: any ManagedSlideShowBindingPollWaiting =
      TaskManagedSlideShowBindingPollWaiter(),
    machClock: any ManagedSlideShowBindingMachClock =
      SystemManagedSlideShowBindingMachClock(),
    maximumPostStartObservationCount: Int = 20
  ) {
    self.init(
      sessionContext: ManagedSlideShowSessionContext(
        bindingSessionToken: "coordinator-fake-session",
        frozenWindowIdentity: PowerPointWindowIdentity(
          windowID: 10,
          ownerProcessID: 700,
          bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
        )!
      ),
      observationReader: observationReader,
      slideShowStarter: slideShowStarter,
      pollWaiter: pollWaiter,
      machClock: machClock,
      maximumPostStartObservationCount: maximumPostStartObservationCount
    )
  }
}

private enum ManagedCoordinatorTestError: Error, Sendable {
  case controlled
}

private enum ManagedStartReceiptVariant: Equatable, Sendable {
  case matching
  case empty
  case whitespaceObjectToken
  case wrongSession
  case wrongProcess
  case wrongBundle
}

private enum ManagedObservationStep: Sendable {
  case observation(
    activePresentationCount: Int = 1,
    count: Int,
    freshness: ManagedObservationFreshness = .matching,
    windows: [ManagedSlideShowWindowIdentity]
  )
  case permissionDenied
  case readFailed
}

private enum ManagedObservationFreshness: Sendable {
  case matching
  case fixedToken(String)
  case previousToken
  case fixedAcquisitionTime(UInt64)
  case previousAcquisitionTime
}

private actor ScriptedManagedObservationReader:
  ManagedSlideShowCompositeObservationReading
{
  private var steps: [ManagedObservationStep]
  private(set) var bindingSessionTokens: [String] = []
  private(set) var requests: [ManagedSlideShowCompositeObservationRequest] = []
  private(set) var readCount = 0
  private var previousFreshObservationToken: String?
  private var previousAcquisitionMachAbsoluteTime: UInt64?

  init(steps: [ManagedObservationStep]) {
    self.steps = steps
  }

  func readCompositeObservation(
    _ request: ManagedSlideShowCompositeObservationRequest
  ) async throws -> ManagedSlideShowInventoryObservation {
    readCount += 1
    bindingSessionTokens.append(request.bindingSessionToken)
    requests.append(request)
    guard !steps.isEmpty else { throw ManagedCoordinatorTestError.controlled }

    switch steps.removeFirst() {
    case .observation(let activePresentationCount, let count, let freshness, let windows):
      let responseFreshObservationToken: String
      let responseAcquisitionMachAbsoluteTime: UInt64
      switch freshness {
      case .matching:
        responseFreshObservationToken = request.freshObservationToken
        responseAcquisitionMachAbsoluteTime = request.requestStartedMachAbsoluteTime
      case .fixedToken(let token):
        responseFreshObservationToken = token
        responseAcquisitionMachAbsoluteTime = request.requestStartedMachAbsoluteTime
      case .previousToken:
        responseFreshObservationToken = previousFreshObservationToken ?? ""
        responseAcquisitionMachAbsoluteTime = request.requestStartedMachAbsoluteTime
      case .fixedAcquisitionTime(let acquiredMachAbsoluteTime):
        responseFreshObservationToken = request.freshObservationToken
        responseAcquisitionMachAbsoluteTime = acquiredMachAbsoluteTime
      case .previousAcquisitionTime:
        responseFreshObservationToken = request.freshObservationToken
        responseAcquisitionMachAbsoluteTime = previousAcquisitionMachAbsoluteTime ?? 0
      }
      previousFreshObservationToken = responseFreshObservationToken
      previousAcquisitionMachAbsoluteTime = responseAcquisitionMachAbsoluteTime

      return ManagedSlideShowInventoryObservation(
        bindingSessionToken: request.bindingSessionToken,
        freshObservationToken: responseFreshObservationToken,
        observedMachAbsoluteTime: responseAcquisitionMachAbsoluteTime,
        scriptingEvidence: ManagedSlideShowScriptingEvidence(
          processIdentifier: Int(request.processIdentifier),
          activePresentationCount: activePresentationCount,
          slideShowWindowCount: count
        ),
        windows: windows
      )
    case .permissionDenied:
      throw ManagedSlideShowBindingClientError.permissionDenied
    case .readFailed:
      throw ManagedCoordinatorTestError.controlled
    }
  }
}

private actor RecordingManagedSlideShowStarter: ManagedSlideShowStarting {
  private let error: ManagedCoordinatorTestError?
  private let receiptVariant: ManagedStartReceiptVariant
  private(set) var requests: [ManagedSlideShowStartRequest] = []

  init(
    error: ManagedCoordinatorTestError? = nil,
    receiptVariant: ManagedStartReceiptVariant = .matching
  ) {
    self.error = error
    self.receiptVariant = receiptVariant
  }

  func startManagedSlideShow(
    _ request: ManagedSlideShowStartRequest
  ) async throws -> ManagedSlideShowStartReceipt {
    requests.append(request)
    if let error { throw error }

    return ManagedSlideShowStartReceipt(
      bindingSessionToken: receiptVariant == .empty
        ? ""
        : receiptVariant == .wrongSession
          ? "wrong-session"
          : request.bindingSessionToken,
      processIdentifier: receiptVariant == .empty
        ? 0
        : receiptVariant == .wrongProcess
          ? request.frozenWindowIdentity.ownerProcessID + 1
          : request.frozenWindowIdentity.ownerProcessID,
      bundleIdentifier: receiptVariant == .empty
        ? ""
        : receiptVariant == .wrongBundle
          ? "wrong.bundle"
          : request.frozenWindowIdentity.bundleIdentifier,
      slideShowObjectToken: receiptVariant == .empty
        ? ""
        : receiptVariant == .whitespaceObjectToken ? "  \n" : "object-token"
    )
  }
}

private actor PowerPointFailingManagedSlideShowStarter: ManagedSlideShowStarting {
  private let failure: PowerPointManagedSlideShowAppleEventClientFailure

  init(failure: PowerPointManagedSlideShowAppleEventClientFailure) {
    self.failure = failure
  }

  func startManagedSlideShow(
    _ request: ManagedSlideShowStartRequest
  ) async throws -> ManagedSlideShowStartReceipt {
    throw failure
  }
}

private actor RecordingManagedBindingWaiter: ManagedSlideShowBindingPollWaiting {
  private let error: ManagedCoordinatorTestError?
  private(set) var waitCount = 0

  init(error: ManagedCoordinatorTestError? = nil) {
    self.error = error
  }

  func waitUntilNextObservation() async throws {
    waitCount += 1
    if let error { throw error }
  }
}

private actor ScriptedManagedSlideShowBindingMachClock:
  ManagedSlideShowBindingMachClock
{
  private var machAbsoluteTimes: [UInt64]
  private(set) var readCount = 0

  init(_ machAbsoluteTimes: [UInt64]) {
    self.machAbsoluteTimes = machAbsoluteTimes
  }

  func now() -> UInt64 {
    readCount += 1
    guard !machAbsoluteTimes.isEmpty else { return 0 }
    return machAbsoluteTimes.removeFirst()
  }
}

private actor ControllableManagedSlideShowStarter: ManagedSlideShowStarting {
  private struct PendingStart: Sendable {
    let request: ManagedSlideShowStartRequest
    let continuation: CheckedContinuation<ManagedSlideShowStartReceipt, any Error>
  }

  private var pendingStarts: [PendingStart] = []
  private(set) var requests: [ManagedSlideShowStartRequest] = []

  func startManagedSlideShow(
    _ request: ManagedSlideShowStartRequest
  ) async throws -> ManagedSlideShowStartReceipt {
    requests.append(request)
    return try await withCheckedThrowingContinuation { continuation in
      pendingStarts.append(PendingStart(request: request, continuation: continuation))
    }
  }

  func resumeOldest() {
    guard !pendingStarts.isEmpty else { return }
    let pending = pendingStarts.removeFirst()
    pending.continuation.resume(
      returning: ManagedSlideShowStartReceipt(
        bindingSessionToken: pending.request.bindingSessionToken,
        processIdentifier: pending.request.frozenWindowIdentity.ownerProcessID,
        bundleIdentifier: pending.request.frozenWindowIdentity.bundleIdentifier,
        slideShowObjectToken: "controlled-object-token"
      )
    )
  }

  func failOldest(_ error: PowerPointManagedSlideShowAppleEventClientFailure) {
    guard !pendingStarts.isEmpty else { return }
    pendingStarts.removeFirst().continuation.resume(throwing: error)
  }
}

private actor ControllableManagedBindingWaiter: ManagedSlideShowBindingPollWaiting {
  private var continuations: [CheckedContinuation<Void, any Error>] = []
  private(set) var waitCount = 0

  func waitUntilNextObservation() async throws {
    waitCount += 1
    try await withCheckedThrowingContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func resumeOldest() {
    guard !continuations.isEmpty else { return }
    continuations.removeFirst().resume()
  }
}

private actor ManagedCandidateResultRecorder {
  private(set) var result: ManagedSlideShowBindingCoordinator.CandidateResult?

  func record(_ result: ManagedSlideShowBindingCoordinator.CandidateResult) {
    self.result = result
  }
}

private actor ControllableManagedObservationReader:
  ManagedSlideShowCompositeObservationReading
{
  private struct Request: Sendable {
    let observationRequest: ManagedSlideShowCompositeObservationRequest
    let continuation: CheckedContinuation<ManagedSlideShowInventoryObservation, any Error>
  }

  private var requests: [Request] = []
  private var activeReadCount = 0
  private(set) var readCount = 0
  private(set) var maximumConcurrentReadCount = 0

  func readCompositeObservation(
    _ request: ManagedSlideShowCompositeObservationRequest
  ) async throws -> ManagedSlideShowInventoryObservation {
    readCount += 1
    activeReadCount += 1
    maximumConcurrentReadCount = max(maximumConcurrentReadCount, activeReadCount)
    defer { activeReadCount -= 1 }

    return try await withCheckedThrowingContinuation { continuation in
      requests.append(
        Request(
          observationRequest: request,
          continuation: continuation
        )
      )
    }
  }

  func resumeOldest(
    activePresentationCount: Int = 1,
    count: Int,
    freshObservationToken: String? = nil,
    observedMachAbsoluteTime: UInt64? = nil,
    windows: [ManagedSlideShowWindowIdentity]
  ) {
    guard !requests.isEmpty else { return }
    let request = requests.removeFirst()
    request.continuation.resume(
      returning: ManagedSlideShowInventoryObservation(
        bindingSessionToken: request.observationRequest.bindingSessionToken,
        freshObservationToken: freshObservationToken
          ?? request.observationRequest.freshObservationToken,
        observedMachAbsoluteTime: observedMachAbsoluteTime
          ?? request.observationRequest.requestStartedMachAbsoluteTime,
        scriptingEvidence: ManagedSlideShowScriptingEvidence(
          processIdentifier: Int(request.observationRequest.processIdentifier),
          activePresentationCount: activePresentationCount,
          slideShowWindowCount: count
        ),
        windows: windows
      )
    )
  }

  func failOldest(_ error: ManagedSlideShowBindingClientError) {
    guard !requests.isEmpty else { return }
    requests.removeFirst().continuation.resume(throwing: error)
  }
}

extension Result where Failure == ManagedSlideShowBindingFailure {
  fileprivate var success: Success? {
    guard case .success(let value) = self else { return nil }
    return value
  }

  fileprivate var failure: ManagedSlideShowBindingCoordinatorFailure? {
    guard case .failure(let value) = self else { return nil }
    return value.reason
  }

  fileprivate var recoveryReceipt: ManagedSlideShowStartReceipt? {
    guard case .failure(let value) = self else { return nil }
    return value.recoveryReceipt
  }
}

private func waitUntil(
  maxYields: Int = 10_000,
  _ predicate: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<maxYields {
    if await predicate() { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for deterministic async state")
}
