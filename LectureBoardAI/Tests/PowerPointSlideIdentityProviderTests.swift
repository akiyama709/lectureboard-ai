import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

private let providerTestPollToken = UUID(
  uuidString: "00000000-0000-0000-0000-000000000001"
)!

struct PowerPointSlideIdentityProviderTests {
  @Test func exactReadingAcceptsOnlyCompletePositiveRuntimeMetadata() throws {
    let identity = try makeIdentity(windowID: 40, ownerProcessID: 700)

    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "session-a",
        slideShowObjectToken: "object-a",
        captureOperationID: CaptureOperationID(rawValue: 1),
        captureGeneration: 7,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 101,
        slideID: 10,
        slideIndex: 2
      ) != nil
    )
    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "",
        slideShowObjectToken: "object-a",
        captureOperationID: CaptureOperationID(rawValue: 1),
        captureGeneration: 7,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 101,
        slideID: 10,
        slideIndex: 2
      ) == nil
    )
    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "session-a",
        slideShowObjectToken: " ",
        captureOperationID: CaptureOperationID(rawValue: 1),
        captureGeneration: 7,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 101,
        slideID: 10,
        slideIndex: 2
      ) == nil
    )
    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "session-a",
        slideShowObjectToken: "object-a",
        captureOperationID: CaptureOperationID(rawValue: 0),
        captureGeneration: 7,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 101,
        slideID: 10,
        slideIndex: 2
      ) == nil
    )
    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "session-a",
        slideShowObjectToken: "object-a",
        captureOperationID: CaptureOperationID(rawValue: 1),
        captureGeneration: 0,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 101,
        slideID: 10,
        slideIndex: 2
      ) == nil
    )
    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "session-a",
        slideShowObjectToken: "object-a",
        captureOperationID: CaptureOperationID(rawValue: 1),
        captureGeneration: 7,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 0,
        slideID: 10,
        slideIndex: 2
      ) == nil
    )
    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "session-a",
        slideShowObjectToken: "object-a",
        captureOperationID: CaptureOperationID(rawValue: 1),
        captureGeneration: 7,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 101,
        slideID: 0,
        slideIndex: 2
      ) == nil
    )
    #expect(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: "session-a",
        slideShowObjectToken: "object-a",
        captureOperationID: CaptureOperationID(rawValue: 1),
        captureGeneration: 7,
        pollToken: providerTestPollToken,
        acquiredMachAbsoluteTime: 101,
        slideID: 10,
        slideIndex: 0
      ) == nil
    )
  }

  @Test func exactProviderAcceptsAReadingBoundToTheExactCaptureTarget() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let reading = try makeReading(
      identity: identity,
      session: "session-a",
      slideID: 10,
      slideIndex: 2
    )
    let binding = try await makeBinding(identity: identity, session: "session-a")
    let reader = ControllableExactSlideIdentityReader(responses: [.success(reading)])
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(reader: reader, pollWaiter: waiter)
    let recorder = SlideIdentityObservationRecorder()
    let operationID = CaptureOperationID(rawValue: 1)

    let startResult = await provider.start(
      operationID: operationID,
      currentCaptureGeneration: 7,
      binding: binding,
      onObservation: recorder.record
    )
    #expect(startResult == .started)
    try await waitUntil { recorder.observations.count == 1 }

    let observation = try #require(recorder.observations.first)
    #expect(observation.sequenceNumber == 1)
    #expect(observation.targetIdentity == identity)
    #expect(observation.signal == .available(reading.sample))
    #expect(await reader.requests.map(\.runtimeBinding) == [binding])
    #expect(await provider.latestOperationID == operationID)
    #expect(await provider.activeOperationID == operationID)

    await provider.stop(operationID: CaptureOperationID(rawValue: 2))
  }

  @Test func immutableMismatchLatchesAndDoesNotRecoverToALaterValidReading() async throws {
    let target = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let otherWindow = try makeIdentity(windowID: 43, ownerProcessID: 700)
    let mismatchedReading = try makeReading(
      identity: otherWindow,
      session: "session-a",
      slideID: 10,
      slideIndex: 2
    )
    let validReading = try makeReading(
      identity: target,
      session: "session-a",
      slideID: 11,
      slideIndex: 3
    )
    let reader = ControllableExactSlideIdentityReader(
      responses: [
        .success(mismatchedReading),
        .success(validReading),
      ]
    )
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(reader: reader, pollWaiter: waiter)
    let recorder = SlideIdentityObservationRecorder()
    let binding = try await makeBinding(identity: target, session: "session-a")

    let startResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 1),
      currentCaptureGeneration: 7,
      binding: binding,
      onObservation: recorder.record
    )
    #expect(startResult == .started)
    try await waitUntil { recorder.observations.count == 1 }

    #expect(recorder.observations.map(\.sequenceNumber) == [1])
    #expect(recorder.observations[0].targetIdentity == target)
    #expect(recorder.observations[0].signal == .unavailable)
    #expect(await provider.firstTerminalReason == .windowIdentityMismatch)
    #expect(await provider.activeOperationID == nil)
    #expect(await provider.hasUndrainedPollingTask == false)
    #expect(await reader.totalReadCount == 1)
    #expect(await reader.maximumConcurrentReadCount == 1)
  }

  @Test func nilAndReaderErrorRemainUnavailableWithoutForgingMetadata() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(identity: identity, session: "session-a")
    let validReading = try makeReading(
      identity: identity,
      session: "session-a",
      acquiredMachAbsoluteTime: 108,
      slideID: 10,
      slideIndex: 2
    )
    let reader = ControllableExactSlideIdentityReader(
      responses: [.success(nil), .failure(.controlledFailure), .success(validReading)]
    )
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: waiter,
      machClock: SequencePowerPointSlideIdentityMachClock(
        times: [101, 103, 104, 106, 107, 109]
      )
    )
    let recorder = SlideIdentityObservationRecorder()

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: binding,
        onObservation: recorder.record
      ) == .started
    )
    try await waitUntil { recorder.observations.count == 1 }
    await waiter.advance()
    try await waitUntil { recorder.observations.count == 2 }
    await waiter.advance()
    try await waitUntil { recorder.observations.count == 3 }

    #expect(
      recorder.observations.map(\.signal) == [
        .unavailable, .unavailable, .available(validReading.sample),
      ])
    #expect(await provider.firstTerminalReason == nil)
    await provider.stop(operationID: CaptureOperationID(rawValue: 2))
  }

  @Test func immutableMismatchTableLatchesTheFirstBoundedReason() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let otherWindow = try makeIdentity(windowID: 43, ownerProcessID: 700)
    let operationID = CaptureOperationID(rawValue: 1)
    let binding = try await makeBinding(
      identity: identity,
      session: "expected-session",
      operationID: operationID,
      freshnessBoundaryMachAbsoluteTime: 100
    )
    let cases:
      [(
        reading: ExactPowerPointSlideIdentityReading,
        responsePreservesToken: Bool,
        reason: ExactPowerPointSlideIdentityProviderTerminalReason
      )] = [
        (
          try makeReading(
            identity: otherWindow, session: "expected-session", slideID: 10, slideIndex: 2),
          false, .windowIdentityMismatch
        ),
        (
          try makeReading(
            identity: identity, session: "other-session", slideID: 10, slideIndex: 2),
          false, .bindingSessionTokenMismatch
        ),
        (
          try makeReading(
            identity: identity,
            session: "expected-session",
            objectToken: "other-object",
            slideID: 10,
            slideIndex: 2
          ),
          false, .slideShowObjectTokenMismatch
        ),
        (
          try makeReading(
            identity: identity,
            session: "expected-session",
            operationID: CaptureOperationID(rawValue: 2),
            slideID: 10,
            slideIndex: 2
          ),
          false, .captureOperationIDMismatch
        ),
        (
          try makeReading(
            identity: identity,
            session: "expected-session",
            captureGeneration: 8,
            slideID: 10,
            slideIndex: 2
          ),
          false, .captureGenerationMismatch
        ),
        (
          try makeReading(
            identity: identity,
            session: "expected-session",
            pollToken: providerTestPollToken,
            slideID: 10,
            slideIndex: 2
          ),
          true, .pollTokenMismatch
        ),
      ]

    for testCase in cases {
      let response: ControllableExactSlideIdentityReader.Response =
        testCase.responsePreservesToken
        ? .exactSuccess(testCase.reading) : .success(testCase.reading)
      let reader = ControllableExactSlideIdentityReader(responses: [response])
      let provider = makeExactProvider(
        reader: reader,
        pollWaiter: ControllableSlideIdentityPollWaiter(),
        machClock: SequencePowerPointSlideIdentityMachClock(times: [101, 103]),
        pollTokenGenerator: SequencePowerPointSlideIdentityPollTokenGenerator(
          tokens: [UUID(uuidString: "00000000-0000-0000-0000-000000000002")!]
        )
      )
      let recorder = SlideIdentityObservationRecorder()

      #expect(
        await provider.start(
          operationID: operationID,
          currentCaptureGeneration: 7,
          binding: binding,
          onObservation: recorder.record
        ) == .started
      )
      try await waitUntil { recorder.observations.count == 1 }

      #expect(recorder.observations[0].signal == .unavailable)
      #expect(await provider.firstTerminalReason == testCase.reason)
      #expect(await reader.totalReadCount == 1)
      #expect(await provider.activeOperationID == nil)
    }
  }

  @Test func reusedReadingIsRejectedByTheFreshPerPollToken() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(
      identity: identity,
      session: "session-a",
      freshnessBoundaryMachAbsoluteTime: 90
    )
    let cachedReading = try makeReading(
      identity: identity,
      session: "session-a",
      acquiredMachAbsoluteTime: 101,
      slideID: 10,
      slideIndex: 2
    )
    let reader = ControllableExactSlideIdentityReader(
      responses: [.exactSuccess(cachedReading), .exactSuccess(cachedReading)]
    )
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: waiter,
      machClock: SequencePowerPointSlideIdentityMachClock(times: [100, 102, 103, 105]),
      pollTokenGenerator: SequencePowerPointSlideIdentityPollTokenGenerator(
        tokens: [
          providerTestPollToken,
          UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        ]
      )
    )
    let recorder = SlideIdentityObservationRecorder()

    let result = await provider.start(
      operationID: CaptureOperationID(rawValue: 1),
      currentCaptureGeneration: 7,
      binding: binding,
      onObservation: recorder.record
    )
    #expect(result == .started)
    try await waitUntil { recorder.observations.count == 1 }
    await waiter.advance()
    try await waitUntil { recorder.observations.count == 2 }

    #expect(recorder.observations[0].signal == .available(cachedReading.sample))
    #expect(recorder.observations[1].signal == .unavailable)
    #expect(await reader.totalReadCount == 2)
    #expect(await provider.firstTerminalReason == .pollTokenMismatch)
    let requests = await reader.requests
    #expect(requests.map(\.pollToken).count == Set(requests.map(\.pollToken)).count)
    #expect(requests.map(\.runtimeBinding) == [binding, binding])
  }

  @Test func acquisitionOutsideTheRequestCompletionIntervalFailsClosed() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(
      identity: identity,
      session: "session-a",
      freshnessBoundaryMachAbsoluteTime: 90
    )
    for acquiredTime: UInt64 in [99, 100, 103] {
      let reading = try makeReading(
        identity: identity,
        session: "session-a",
        acquiredMachAbsoluteTime: acquiredTime,
        slideID: 10,
        slideIndex: 2
      )
      let reader = ControllableExactSlideIdentityReader(responses: [.success(reading)])
      let provider = makeExactProvider(
        reader: reader,
        pollWaiter: ControllableSlideIdentityPollWaiter(),
        machClock: SequencePowerPointSlideIdentityMachClock(times: [100, 102])
      )
      let recorder = SlideIdentityObservationRecorder()

      #expect(
        await provider.start(
          operationID: CaptureOperationID(rawValue: 1),
          currentCaptureGeneration: 7,
          binding: binding,
          onObservation: recorder.record
        ) == .started
      )
      try await waitUntil { recorder.observations.count == 1 }

      #expect(recorder.observations[0].signal == .unavailable)
      #expect(await provider.firstTerminalReason == .invalidAcquisitionClock)
      #expect(await reader.totalReadCount == 1)
      #expect(await provider.activeOperationID == nil)
    }
  }

  @Test func requestClockAtOrBeforeFreshnessBoundaryFailsClosedWithoutReading() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(
      identity: identity,
      session: "session-a",
      freshnessBoundaryMachAbsoluteTime: 90
    )
    let reading = try makeReading(
      identity: identity,
      session: "session-a",
      acquiredMachAbsoluteTime: 100,
      slideID: 10,
      slideIndex: 2
    )

    for invalidRequestTime: UInt64 in [89, 90] {
      let reader = ControllableExactSlideIdentityReader(responses: [.success(reading)])
      let waiter = ControllableSlideIdentityPollWaiter()
      let provider = makeExactProvider(
        reader: reader,
        pollWaiter: waiter,
        machClock: FixedPowerPointSlideIdentityMachClock(time: invalidRequestTime)
      )
      let recorder = SlideIdentityObservationRecorder()

      let result = await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: binding,
        onObservation: recorder.record
      )
      #expect(result == .started)
      try await waitUntil { recorder.observations.count == 1 }

      #expect(recorder.observations[0].signal == .unavailable)
      #expect(await reader.totalReadCount == 0)

      await provider.stop(operationID: CaptureOperationID(rawValue: 2))
    }
  }

  @Test func nonIncreasingNextRequestClockLatchesWithoutASecondRead() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(
      identity: identity,
      session: "session-a",
      freshnessBoundaryMachAbsoluteTime: 90
    )
    let reading = try makeReading(
      identity: identity,
      session: "session-a",
      acquiredMachAbsoluteTime: 101,
      slideID: 10,
      slideIndex: 2
    )
    for invalidNextRequestTime: UInt64 in [103, 102] {
      let reader = ControllableExactSlideIdentityReader(responses: [.success(reading)])
      let waiter = ControllableSlideIdentityPollWaiter()
      let provider = makeExactProvider(
        reader: reader,
        pollWaiter: waiter,
        machClock: SequencePowerPointSlideIdentityMachClock(
          times: [100, 103, invalidNextRequestTime]
        )
      )
      let recorder = SlideIdentityObservationRecorder()

      #expect(
        await provider.start(
          operationID: CaptureOperationID(rawValue: 1),
          currentCaptureGeneration: 7,
          binding: binding,
          onObservation: recorder.record
        ) == .started
      )
      try await waitUntil { recorder.observations.count == 1 }
      await waiter.advance()
      try await waitUntil { recorder.observations.count == 2 }

      #expect(recorder.observations[0].signal == .available(reading.sample))
      #expect(recorder.observations[1].signal == .unavailable)
      #expect(await provider.firstTerminalReason == .invalidRequestClock)
      #expect(await reader.totalReadCount == 1)
      #expect(await provider.activeOperationID == nil)
    }
  }

  @Test func maximumTimestampReadingCannotBeReusedAfterItsCompletionBoundary() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(identity: identity, session: "session-a")
    let reading = try makeReading(
      identity: identity,
      session: "session-a",
      acquiredMachAbsoluteTime: .max,
      slideID: 10,
      slideIndex: 2
    )
    let reader = ControllableExactSlideIdentityReader(
      responses: [.success(reading), .success(reading)]
    )
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: waiter,
      machClock: SequencePowerPointSlideIdentityMachClock(times: [.max - 1, .max, .max])
    )
    let recorder = SlideIdentityObservationRecorder()

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: binding,
        onObservation: recorder.record
      ) == .started
    )
    try await waitUntil { recorder.observations.count == 1 }
    await waiter.advance()
    try await waitUntil { recorder.observations.count == 2 }

    #expect(recorder.observations[0].signal == .available(reading.sample))
    #expect(recorder.observations[1].signal == .unavailable)
    #expect(await provider.firstTerminalReason == .invalidRequestClock)
    #expect(await reader.totalReadCount == 1)
  }

  @Test func replacementIsRejectedUntilANoncooperativeReadActuallyDrains() async throws {
    let firstIdentity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let replacementIdentity = try makeIdentity(windowID: 43, ownerProcessID: 700)
    let firstReading = try makeReading(
      identity: firstIdentity,
      session: "session-a",
      acquiredMachAbsoluteTime: 102,
      slideID: 10,
      slideIndex: 1
    )
    let replacementReading = try makeReading(
      identity: replacementIdentity,
      session: "session-b",
      operationID: CaptureOperationID(rawValue: 5),
      acquiredMachAbsoluteTime: 302,
      slideID: 20,
      slideIndex: 3
    )
    let firstBinding = try await makeBinding(identity: firstIdentity, session: "session-a")
    let replacementBinding = try await makeBinding(
      identity: replacementIdentity,
      session: "session-b",
      operationID: CaptureOperationID(rawValue: 5),
      freshnessBoundaryMachAbsoluteTime: 300
    )
    let reader = ControllableExactSlideIdentityReader()
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: waiter,
      machClock: SequencePowerPointSlideIdentityMachClock(times: [101, 301, 303])
    )
    let firstRecorder = SlideIdentityObservationRecorder()
    let replacementRecorder = SlideIdentityObservationRecorder()

    let firstStartResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 1),
      currentCaptureGeneration: 7,
      binding: firstBinding,
      onObservation: firstRecorder.record
    )
    #expect(firstStartResult == .started)
    try await waitUntil { await reader.totalReadCount == 1 }

    await provider.stop(operationID: CaptureOperationID(rawValue: 2))
    let rejectedReplacement = await provider.start(
      operationID: CaptureOperationID(rawValue: 3),
      currentCaptureGeneration: 7,
      binding: replacementBinding,
      onObservation: replacementRecorder.record
    )
    let secondRejectedReplacement = await provider.start(
      operationID: CaptureOperationID(rawValue: 4),
      currentCaptureGeneration: 7,
      binding: replacementBinding,
      onObservation: replacementRecorder.record
    )

    #expect(rejectedReplacement == .rejectedPriorReadStillDraining)
    #expect(secondRejectedReplacement == .rejectedPriorReadStillDraining)
    #expect(await reader.totalReadCount == 1)
    #expect(await provider.latestOperationID == CaptureOperationID(rawValue: 4))
    #expect(await provider.activeOperationID == nil)

    await reader.resumeOldest(with: .success(firstReading))
    try await waitUntil { await provider.hasUndrainedPollingTask == false }
    #expect(firstRecorder.observations.isEmpty)

    let staleRetryResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 3),
      currentCaptureGeneration: 7,
      binding: replacementBinding,
      onObservation: replacementRecorder.record
    )
    #expect(staleRetryResult == .rejectedStaleOperation)

    await reader.enqueue(.success(replacementReading))
    let replacementStartResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 5),
      currentCaptureGeneration: 7,
      binding: replacementBinding,
      onObservation: replacementRecorder.record
    )
    #expect(replacementStartResult == .started)
    try await waitUntil { replacementRecorder.observations.count == 1 }

    let observation = try #require(replacementRecorder.observations.first)
    #expect(observation.sequenceNumber == 1)
    #expect(observation.targetIdentity == replacementIdentity)
    #expect(observation.signal == .available(replacementReading.sample))
    #expect(await reader.maximumConcurrentReadCount == 1)

    await provider.stop(operationID: CaptureOperationID(rawValue: 6))
  }

  @Test func generationMismatchAdvancesHighWaterAndRejectsOperationNinetyNine() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let mismatchedBinding = try await makeBinding(
      identity: identity,
      session: "session-a",
      operationID: CaptureOperationID(rawValue: 100),
      captureGeneration: 7
    )
    let olderBinding = try await makeBinding(
      identity: identity,
      session: "session-a",
      operationID: CaptureOperationID(rawValue: 99),
      captureGeneration: 8
    )
    let reader = ControllableExactSlideIdentityReader()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: ControllableSlideIdentityPollWaiter()
    )
    let recorder = SlideIdentityObservationRecorder()

    let result = await provider.start(
      operationID: CaptureOperationID(rawValue: 100),
      currentCaptureGeneration: 8,
      binding: mismatchedBinding,
      onObservation: recorder.record
    )
    let olderResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 99),
      currentCaptureGeneration: 8,
      binding: olderBinding,
      onObservation: recorder.record
    )

    #expect(result == .rejectedBindingCaptureGenerationMismatch)
    #expect(olderResult == .rejectedStaleOperation)
    #expect(await reader.totalReadCount == 0)
    #expect(await provider.latestOperationID == CaptureOperationID(rawValue: 100))
    #expect(await provider.activeOperationID == nil)
    #expect(recorder.observations.isEmpty)
  }

  @Test func matchingCurrentCaptureGenerationCanStartAfterANewerOperation() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(
      identity: identity,
      session: "session-a",
      operationID: CaptureOperationID(rawValue: 101),
      captureGeneration: 8
    )
    let provider = makeExactProvider(
      reader: ControllableExactSlideIdentityReader(responses: [.success(nil)]),
      pollWaiter: ControllableSlideIdentityPollWaiter()
    )

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 101),
        currentCaptureGeneration: 8,
        binding: binding,
        onObservation: { _ in }
      ) == .started
    )
    await provider.stop(operationID: CaptureOperationID(rawValue: 102))
  }

  @Test func stopReturnsWithoutTrustingOrWaitingForABlockedExternalReader() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let staleReading = try makeReading(
      identity: identity,
      session: "session-a",
      slideID: 10,
      slideIndex: 1
    )
    let reader = ControllableExactSlideIdentityReader()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: ControllableSlideIdentityPollWaiter()
    )
    let recorder = SlideIdentityObservationRecorder()
    let binding = try await makeBinding(identity: identity, session: "session-a")

    let startResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 1),
      currentCaptureGeneration: 7,
      binding: binding,
      onObservation: recorder.record
    )
    #expect(startResult == .started)
    try await waitUntil { await reader.totalReadCount == 1 }

    await provider.stop(operationID: CaptureOperationID(rawValue: 2))
    #expect(await provider.activeOperationID == nil)
    #expect(recorder.observations.isEmpty)
    #expect(await reader.activeReadCount == 1)

    await reader.resumeOldest(with: .success(staleReading))
    try await waitUntil { await provider.hasUndrainedPollingTask == false }
    #expect(recorder.observations.isEmpty)
  }

  @Test func acceptedStartSequencesAreOrderedAndResetToOne() async throws {
    let firstIdentity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let secondIdentity = try makeIdentity(windowID: 43, ownerProcessID: 701)
    let firstReading = try makeReading(
      identity: firstIdentity,
      session: "session-a",
      acquiredMachAbsoluteTime: 102,
      slideID: 10,
      slideIndex: 1
    )
    let nextFirstReading = try makeReading(
      identity: firstIdentity,
      session: "session-a",
      acquiredMachAbsoluteTime: 105,
      slideID: 11,
      slideIndex: 2
    )
    let secondReading = try makeReading(
      identity: secondIdentity,
      session: "session-b",
      operationID: CaptureOperationID(rawValue: 3),
      acquiredMachAbsoluteTime: 302,
      slideID: 20,
      slideIndex: 1
    )
    let firstBinding = try await makeBinding(identity: firstIdentity, session: "session-a")
    let secondBinding = try await makeBinding(
      identity: secondIdentity,
      session: "session-b",
      operationID: CaptureOperationID(rawValue: 3),
      freshnessBoundaryMachAbsoluteTime: 300
    )
    let reader = ControllableExactSlideIdentityReader(
      responses: [.success(firstReading), .success(nextFirstReading)]
    )
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: waiter,
      machClock: SequencePowerPointSlideIdentityMachClock(
        times: [101, 103, 104, 106, 301, 303]
      )
    )
    let firstRecorder = SlideIdentityObservationRecorder()
    let secondRecorder = SlideIdentityObservationRecorder()

    let firstStartResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 1),
      currentCaptureGeneration: 7,
      binding: firstBinding,
      onObservation: firstRecorder.record
    )
    #expect(firstStartResult == .started)
    try await waitUntil { firstRecorder.observations.count == 1 }
    await waiter.advance()
    try await waitUntil { firstRecorder.observations.count == 2 }
    #expect(firstRecorder.observations.map(\.sequenceNumber) == [1, 2])

    await provider.stop(operationID: CaptureOperationID(rawValue: 2))
    try await waitUntil { await provider.hasUndrainedPollingTask == false }
    await reader.enqueue(.success(secondReading))
    let secondStartResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 3),
      currentCaptureGeneration: 7,
      binding: secondBinding,
      onObservation: secondRecorder.record
    )
    #expect(secondStartResult == .started)
    try await waitUntil { secondRecorder.observations.count == 1 }

    #expect(secondRecorder.observations.map(\.sequenceNumber) == [1])
    #expect(secondRecorder.observations.first?.targetIdentity == secondIdentity)

    await provider.stop(operationID: CaptureOperationID(rawValue: 4))
    try await waitUntil { await provider.hasUndrainedPollingTask == false }
    let staleStartResult = await provider.start(
      operationID: CaptureOperationID(rawValue: 3),
      currentCaptureGeneration: 7,
      binding: secondBinding,
      onObservation: secondRecorder.record
    )
    #expect(staleStartResult == .rejectedStaleOperation)
    #expect(secondRecorder.observations.count == 1)
    #expect(await provider.latestOperationID == CaptureOperationID(rawValue: 4))
    #expect(await provider.activeOperationID == nil)
  }

  @Test func duplicateGeneratedPollTokenTerminatesBeforeASecondReaderCall() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(identity: identity, session: "session-a")
    let firstReading = try makeReading(
      identity: identity,
      session: "session-a",
      acquiredMachAbsoluteTime: 102,
      slideID: 10,
      slideIndex: 1
    )
    let reader = ControllableExactSlideIdentityReader(responses: [.success(firstReading)])
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: waiter,
      machClock: SequencePowerPointSlideIdentityMachClock(times: [101, 103]),
      pollTokenGenerator: SequencePowerPointSlideIdentityPollTokenGenerator(
        tokens: [providerTestPollToken, providerTestPollToken]
      )
    )
    let recorder = SlideIdentityObservationRecorder()

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: binding,
        onObservation: recorder.record
      ) == .started
    )
    try await waitUntil { recorder.observations.count == 1 }
    await waiter.advance()
    try await waitUntil { recorder.observations.count == 2 }

    #expect(await reader.totalReadCount == 1)
    #expect(await provider.firstTerminalReason == .duplicatePollToken)
    #expect(await provider.activeOperationID == nil)
  }

  @Test func naturalWaitFailureClearsTheActiveOperation() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(identity: identity, session: "session-a")
    let reading = try makeReading(
      identity: identity,
      session: "session-a",
      slideID: 10,
      slideIndex: 1
    )
    let provider = makeExactProvider(
      reader: ControllableExactSlideIdentityReader(responses: [.success(reading)]),
      pollWaiter: FailingSlideIdentityPollWaiter()
    )
    let recorder = SlideIdentityObservationRecorder()

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: binding,
        onObservation: recorder.record
      ) == .started
    )
    try await waitUntil { await provider.hasUndrainedPollingTask == false }

    #expect(recorder.observations.map(\.sequenceNumber) == [1, 2])
    #expect(recorder.observations[0].signal == .available(reading.sample))
    #expect(recorder.observations[1].signal == .unavailable)
    #expect(await provider.firstTerminalReason == .pollWaitFailed)
    #expect(await provider.latestOperationID == CaptureOperationID(rawValue: 1))
    #expect(await provider.activeOperationID == nil)
  }

  @Test func sequenceLimitReservesItsFinalNumberForTerminalUnavailable() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let binding = try await makeBinding(identity: identity, session: "session-a")
    let reading = try makeReading(
      identity: identity,
      session: "session-a",
      slideID: 10,
      slideIndex: 1
    )
    let reader = ControllableExactSlideIdentityReader(responses: [.success(reading)])
    let waiter = ControllableSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: reader,
      pollWaiter: waiter,
      terminalSequenceNumber: 2
    )
    let recorder = SlideIdentityObservationRecorder()

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: binding,
        onObservation: recorder.record
      ) == .started
    )
    try await waitUntil { recorder.observations.count == 1 }
    await waiter.advance()
    try await waitUntil { await provider.hasUndrainedPollingTask == false }

    #expect(recorder.observations.map(\.sequenceNumber) == [1, 2])
    #expect(recorder.observations[0].signal == .available(reading.sample))
    #expect(recorder.observations[1].signal == .unavailable)
    #expect(await provider.firstTerminalReason == .sequenceExhausted)
    #expect(await reader.totalReadCount == 1)
    #expect(await provider.activeOperationID == nil)
  }

  @Test func noncooperativeWaiterBlocksReplacementAndCannotEmitAfterStop() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let firstBinding = try await makeBinding(identity: identity, session: "session-a")
    let replacementBinding = try await makeBinding(
      identity: identity,
      session: "session-b",
      operationID: CaptureOperationID(rawValue: 3)
    )
    let reading = try makeReading(
      identity: identity,
      session: "session-a",
      slideID: 10,
      slideIndex: 1
    )
    let waiter = NoncooperativeSlideIdentityPollWaiter()
    let provider = makeExactProvider(
      reader: ControllableExactSlideIdentityReader(responses: [.success(reading)]),
      pollWaiter: waiter
    )
    let recorder = SlideIdentityObservationRecorder()

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: firstBinding,
        onObservation: recorder.record
      ) == .started
    )
    try await waitUntil { await waiter.waitCount == 1 }
    await provider.stop(operationID: CaptureOperationID(rawValue: 2))
    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 3),
        currentCaptureGeneration: 7,
        binding: replacementBinding,
        onObservation: recorder.record
      ) == .rejectedPriorReadStillDraining
    )
    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 4),
        currentCaptureGeneration: 7,
        binding: replacementBinding,
        onObservation: recorder.record
      ) == .rejectedPriorReadStillDraining
    )

    await waiter.resume()
    try await waitUntil { await provider.hasUndrainedPollingTask == false }

    #expect(recorder.observations.count == 1)
    #expect(await provider.latestOperationID == CaptureOperationID(rawValue: 4))
    #expect(await provider.activeOperationID == nil)
  }

  @Test func noncooperativeClockIsRetainedUntilItDrainsWithoutOldCallback() async throws {
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let firstBinding = try await makeBinding(identity: identity, session: "session-a")
    let replacementBinding = try await makeBinding(
      identity: identity,
      session: "session-b",
      operationID: CaptureOperationID(rawValue: 3)
    )
    let clock = NoncooperativePowerPointSlideIdentityMachClock()
    let provider = makeExactProvider(
      reader: ControllableExactSlideIdentityReader(responses: [.success(nil)]),
      pollWaiter: ControllableSlideIdentityPollWaiter(),
      machClock: clock
    )
    let recorder = SlideIdentityObservationRecorder()

    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 1),
        currentCaptureGeneration: 7,
        binding: firstBinding,
        onObservation: recorder.record
      ) == .started
    )
    try await waitUntil { await clock.callCount == 1 }
    await provider.stop(operationID: CaptureOperationID(rawValue: 2))
    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 3),
        currentCaptureGeneration: 7,
        binding: replacementBinding,
        onObservation: recorder.record
      ) == .rejectedPriorReadStillDraining
    )
    #expect(
      await provider.start(
        operationID: CaptureOperationID(rawValue: 4),
        currentCaptureGeneration: 7,
        binding: replacementBinding,
        onObservation: recorder.record
      ) == .rejectedPriorReadStillDraining
    )

    await clock.resume(with: 101)
    try await waitUntil { await provider.hasUndrainedPollingTask == false }

    #expect(recorder.observations.isEmpty)
    #expect(await provider.latestOperationID == CaptureOperationID(rawValue: 4))
    #expect(await provider.activeOperationID == nil)
  }

  @Test func acceptedStartEmitsOneUnavailableObservationForTheExactTarget() async throws {
    let provider = UnavailablePowerPointSlideIdentityProvider()
    let recorder = SlideIdentityObservationRecorder()
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let operationID = CaptureOperationID(rawValue: 1)
    let earliestObservationDate = Date()

    await provider.start(
      operationID: operationID,
      identity: identity,
      onObservation: recorder.record
    )

    let latestObservationDate = Date()
    let observations = recorder.observations
    let observation = try #require(observations.first)
    #expect(observations.count == 1)
    #expect(observation.sequenceNumber == 1)
    #expect(observation.observedAt >= earliestObservationDate)
    #expect(observation.observedAt <= latestObservationDate)
    #expect(observation.targetIdentity == identity)
    #expect(observation.signal == .unavailable)
    #expect(await provider.latestOperationID == operationID)
    #expect(await provider.activeOperationID == operationID)
  }

  @Test func startOlderThanTheLatestStopIsIgnored() async throws {
    let provider = UnavailablePowerPointSlideIdentityProvider()
    let recorder = SlideIdentityObservationRecorder()
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let stopOperationID = CaptureOperationID(rawValue: 2)

    await provider.stop(operationID: stopOperationID)
    await provider.start(
      operationID: CaptureOperationID(rawValue: 1),
      identity: identity,
      onObservation: recorder.record
    )

    #expect(recorder.observations.isEmpty)
    #expect(await provider.latestOperationID == stopOperationID)
    #expect(await provider.activeOperationID == nil)
  }

  @Test func oldStopCannotClearANewerActiveStart() async throws {
    let provider = UnavailablePowerPointSlideIdentityProvider()
    let recorder = SlideIdentityObservationRecorder()
    let firstIdentity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let activeIdentity = try makeIdentity(windowID: 43, ownerProcessID: 700)
    let firstOperationID = CaptureOperationID(rawValue: 1)
    let activeOperationID = CaptureOperationID(rawValue: 3)

    await provider.start(
      operationID: firstOperationID,
      identity: firstIdentity,
      onObservation: recorder.record
    )
    await provider.start(
      operationID: activeOperationID,
      identity: activeIdentity,
      onObservation: recorder.record
    )
    await provider.stop(operationID: CaptureOperationID(rawValue: 2))

    let observations = recorder.observations
    #expect(observations.count == 2)
    #expect(observations.map(\.sequenceNumber) == [1, 1])
    #expect(observations.map(\.targetIdentity) == [firstIdentity, activeIdentity])
    #expect(await provider.latestOperationID == activeOperationID)
    #expect(await provider.activeOperationID == activeOperationID)
  }

  @Test func acceptedStopLeavesNoCallbackThatCanNotifyLater() async throws {
    let provider = UnavailablePowerPointSlideIdentityProvider()
    let recorder = SlideIdentityObservationRecorder()
    let identity = try makeIdentity(windowID: 42, ownerProcessID: 700)
    let startOperationID = CaptureOperationID(rawValue: 1)
    let stopOperationID = CaptureOperationID(rawValue: 2)

    await provider.start(
      operationID: startOperationID,
      identity: identity,
      onObservation: recorder.record
    )
    await provider.stop(operationID: stopOperationID)
    await provider.start(
      operationID: startOperationID,
      identity: identity,
      onObservation: recorder.record
    )
    await Task.yield()

    #expect(recorder.observations.count == 1)
    #expect(await provider.latestOperationID == stopOperationID)
    #expect(await provider.activeOperationID == nil)
  }

  private func makeIdentity(
    windowID: CGWindowID,
    ownerProcessID: pid_t
  ) throws -> PowerPointWindowIdentity {
    try #require(
      PowerPointWindowIdentity(
        windowID: windowID,
        ownerProcessID: ownerProcessID,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      )
    )
  }

  private func makeExactProvider(
    reader: any ExactPowerPointSlideIdentityReadingClient,
    pollWaiter: any PowerPointSlideIdentityPollWaiting,
    machClock: any PowerPointSlideIdentityMachClock =
      IncrementingPowerPointSlideIdentityMachClock(startingAt: 101),
    pollTokenGenerator: any PowerPointSlideIdentityPollTokenGenerating =
      IncrementingPowerPointSlideIdentityPollTokenGenerator(),
    terminalSequenceNumber: UInt64 = .max
  ) -> ExactPowerPointSlideIdentityProvider {
    ExactPowerPointSlideIdentityProvider(
      reader: reader,
      pollWaiter: pollWaiter,
      machClock: machClock,
      pollTokenGenerator: pollTokenGenerator,
      terminalSequenceNumber: terminalSequenceNumber
    )
  }

  private func makeReading(
    identity: PowerPointWindowIdentity,
    session: String,
    objectToken: String = "object-a",
    operationID: CaptureOperationID = CaptureOperationID(rawValue: 1),
    captureGeneration: UInt64 = 7,
    pollToken: UUID = providerTestPollToken,
    acquiredMachAbsoluteTime: UInt64 = 102,
    slideID: Int,
    slideIndex: Int
  ) throws -> ExactPowerPointSlideIdentityReading {
    try #require(
      ExactPowerPointSlideIdentityReading(
        windowIdentity: identity,
        bindingSessionToken: session,
        slideShowObjectToken: objectToken,
        captureOperationID: operationID,
        captureGeneration: captureGeneration,
        pollToken: pollToken,
        acquiredMachAbsoluteTime: acquiredMachAbsoluteTime,
        slideID: slideID,
        slideIndex: slideIndex
      )
    )
  }

  private func makeBinding(
    identity: PowerPointWindowIdentity,
    session: String,
    objectToken: String = "object-a",
    operationID: CaptureOperationID = CaptureOperationID(rawValue: 1),
    captureGeneration: UInt64 = 7,
    freshnessBoundaryMachAbsoluteTime: UInt64 = 100
  ) async throws -> ManagedSlideShowRuntimeBinding {
    let candidate = ManagedSlideShowRuntimeCandidate(
      candidateWindowIdentity: identity,
      bindingSessionToken: session,
      slideShowObjectToken: objectToken
    )
    let result = await ManagedSlideShowRoleChallengeCoordinator(
      client: ProviderBindingRoleChallengeClient(
        freshnessBoundaryMachAbsoluteTime: freshnessBoundaryMachAbsoluteTime
      ),
      nonceGenerator: { 40 }
    ).challenge(
      candidate: candidate,
      captureOperationID: operationID,
      captureGeneration: captureGeneration,
      captureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor(
        candidateStreamMemberToken: "provider-candidate-member",
        candidateContinuityToken: "provider-candidate-continuity",
        minimumCandidateDeliverySequenceExclusive: 79
      )
    )
    switch result {
    case .success(let binding):
      return binding
    case .failure:
      throw PowerPointSlideIdentityProviderTestError.bindingMintFailed
    }
  }

  private func waitUntil(
    _ condition: @escaping @Sendable () async -> Bool
  ) async throws {
    for _ in 0..<200 {
      if await condition() {
        return
      }
      try await Task.sleep(for: .milliseconds(5))
    }
    throw PowerPointSlideIdentityProviderTestError.timedOut
  }
}

private enum PowerPointSlideIdentityProviderTestError: Error, Sendable {
  case bindingMintFailed
  case controlledFailure
  case timedOut
}

private struct FixedPowerPointSlideIdentityMachClock: PowerPointSlideIdentityMachClock {
  let time: UInt64

  func now() async -> UInt64 {
    time
  }
}

private actor IncrementingPowerPointSlideIdentityMachClock:
  PowerPointSlideIdentityMachClock
{
  private var nextTime: UInt64

  init(startingAt: UInt64) {
    nextTime = startingAt
  }

  func now() async -> UInt64 {
    guard nextTime < .max else { return 0 }
    defer { nextTime += 1 }
    return nextTime
  }
}

private actor SequencePowerPointSlideIdentityMachClock: PowerPointSlideIdentityMachClock {
  private var times: [UInt64]

  init(times: [UInt64]) {
    self.times = times
  }

  func now() async -> UInt64 {
    guard !times.isEmpty else { return 0 }
    return times.removeFirst()
  }
}

private actor IncrementingPowerPointSlideIdentityPollTokenGenerator:
  PowerPointSlideIdentityPollTokenGenerating
{
  private var nextValue: UInt64 = 1

  func nextToken() async -> UUID {
    let suffix = String(format: "%012llX", nextValue)
    nextValue &+= 1
    return UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!
  }
}

private actor SequencePowerPointSlideIdentityPollTokenGenerator:
  PowerPointSlideIdentityPollTokenGenerating
{
  private var tokens: [UUID]

  init(tokens: [UUID]) {
    self.tokens = tokens
  }

  func nextToken() async -> UUID {
    guard !tokens.isEmpty else { return providerTestPollToken }
    return tokens.removeFirst()
  }
}

/// Test-only route through the real role-challenge coordinator. Provider tests never mint
/// `ManagedSlideShowRuntimeBinding` directly, preserving the production compile-time boundary.
private struct ProviderBindingRoleChallengeClient: ManagedSlideShowRoleChallengeClient {
  let freshnessBoundaryMachAbsoluteTime: UInt64

  func runVisibilityChallenge(
    _ request: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    .evidence(visibilityTranscript(for: request))
  }

  func runPixelNonceChallenge(
    _: ManagedSlideShowRoleChallengeRequest
  ) async throws -> ManagedSlideShowRoleChallengeClientResult {
    .unavailable
  }

  private func visibilityTranscript(
    for request: ManagedSlideShowRoleChallengeRequest
  ) -> [ManagedSlideShowRoleChallengeObservation] {
    precondition(freshnessBoundaryMachAbsoluteTime >= 90)
    let identity = request.candidate.candidateWindowIdentity
    let candidate = ManagedSlideShowWindowIdentity(
      windowID: Int(identity.windowID),
      processIdentifier: Int(identity.ownerProcessID),
      bundleIdentifier: identity.bundleIdentifier
    )
    let control = ManagedSlideShowWindowIdentity(
      windowID: Int(identity.windowID) == 1 ? 2 : 1,
      processIdentifier: Int(identity.ownerProcessID),
      bundleIdentifier: identity.bundleIdentifier
    )
    let phases: [ManagedSlideShowRoleChallengePhase] = [
      .baseline, .visibilityHidden, .visibilityRestored,
    ]
    let commandTimes = [
      freshnessBoundaryMachAbsoluteTime - 80,
      freshnessBoundaryMachAbsoluteTime - 50,
      freshnessBoundaryMachAbsoluteTime - 20,
    ]

    return phases.enumerated().flatMap { phaseIndex, phase in
      [0, 1].map { repeatIndex in
        let commandTime = commandTimes[phaseIndex]
        let observedTime = commandTime + UInt64((repeatIndex + 1) * 10)
        let candidateIsOnScreen = phase != .visibilityHidden
        return ManagedSlideShowRoleChallengeObservation(
          bindingSessionToken: request.candidate.bindingSessionToken,
          slideShowObjectToken: request.candidate.slideShowObjectToken,
          processIdentifier: Int(identity.ownerProcessID),
          bundleIdentifier: identity.bundleIdentifier,
          candidateWindowIdentity: candidate,
          captureOperationID: request.captureOperationID.rawValue,
          captureGeneration: request.captureGeneration,
          phase: phase,
          nonce: request.challengeNonce + UInt64(phaseIndex),
          commandReplyMachAbsoluteTime: commandTime,
          evidenceObservedMachAbsoluteTime: observedTime,
          candidateDisplayTime: candidateIsOnScreen ? observedTime : nil,
          inventoryIsComplete: true,
          semanticState: ManagedSlideShowRoleSemanticState(
            slideID: 50,
            slideIndex: 3,
            currentViewState: .running,
            presentationSaved: true
          ),
          windows: [
            ManagedSlideShowRoleWindowEvidence(
              identity: control,
              fingerprint: fingerprint(80),
              isOnScreen: true,
              displayTime: observedTime,
              deliveryProvenance: ManagedSlideShowRoleWindowDeliveryProvenance(
                status: .generated,
                captureOperationID: request.captureOperationID.rawValue,
                captureGeneration: request.captureGeneration,
                streamMemberToken: "provider-control-member",
                continuityToken: "provider-control-continuity",
                deliverySequence: request.challengeNonce * 2
                  + UInt64(phaseIndex * 2 + repeatIndex),
                callbackMachAbsoluteTime: observedTime
              )
            ),
            ManagedSlideShowRoleWindowEvidence(
              identity: candidate,
              fingerprint: candidateIsOnScreen ? fingerprint(100) : nil,
              isOnScreen: candidateIsOnScreen,
              displayTime: candidateIsOnScreen ? observedTime : nil,
              deliveryProvenance: candidateIsOnScreen
                ? ManagedSlideShowRoleWindowDeliveryProvenance(
                  status: .generated,
                  captureOperationID: request.captureOperationID.rawValue,
                  captureGeneration: request.captureGeneration,
                  streamMemberToken: request.captureAnchor.candidateStreamMemberToken,
                  continuityToken: request.captureAnchor.candidateContinuityToken,
                  deliverySequence: request.challengeNonce * 2
                    + UInt64(phaseIndex * 2 + repeatIndex),
                  callbackMachAbsoluteTime: observedTime
                )
                : nil
            ),
          ]
        )
      }
    }
  }

  private func fingerprint(_ luminance: UInt8) -> FrameFingerprint {
    FrameFingerprint(
      sampleColumns: 2,
      sampleRows: 2,
      luminance: Array(repeating: luminance, count: 4)
    )
  }
}

private actor ControllableExactSlideIdentityReader:
  ExactPowerPointSlideIdentityReadingClient
{
  enum Response: Sendable {
    case success(ExactPowerPointSlideIdentityReading?)
    case exactSuccess(ExactPowerPointSlideIdentityReading?)
    case failure(PowerPointSlideIdentityProviderTestError)
  }

  private struct SuspendedRead {
    let request: ExactPowerPointSlideIdentityReadRequest
    let continuation: CheckedContinuation<ExactPowerPointSlideIdentityReading?, Error>
  }

  private var responses: [Response]
  private var suspendedReads: [SuspendedRead] = []
  private(set) var totalReadCount = 0
  private(set) var maximumConcurrentReadCount = 0
  private(set) var activeReadCount = 0
  private(set) var requests: [ExactPowerPointSlideIdentityReadRequest] = []

  init(responses: [Response] = []) {
    self.responses = responses
  }

  func readExactSlideIdentity(
    for request: ExactPowerPointSlideIdentityReadRequest
  ) async throws -> ExactPowerPointSlideIdentityReading? {
    totalReadCount += 1
    activeReadCount += 1
    requests.append(request)
    maximumConcurrentReadCount = max(maximumConcurrentReadCount, activeReadCount)
    defer { activeReadCount -= 1 }

    if !responses.isEmpty {
      return try resolve(responses.removeFirst(), request: request)
    }

    return try await withCheckedThrowingContinuation { continuation in
      suspendedReads.append(SuspendedRead(request: request, continuation: continuation))
    }
  }

  func enqueue(_ response: Response) {
    guard !suspendedReads.isEmpty else {
      responses.append(response)
      return
    }
    let suspended = suspendedReads.removeFirst()
    do {
      suspended.continuation.resume(
        returning: try resolve(response, request: suspended.request)
      )
    } catch {
      suspended.continuation.resume(throwing: error)
    }
  }

  func resumeOldest(with response: Response) {
    enqueue(response)
  }

  private func resolve(
    _ response: Response,
    request: ExactPowerPointSlideIdentityReadRequest
  ) throws -> ExactPowerPointSlideIdentityReading? {
    switch response {
    case .success(nil), .exactSuccess(nil):
      return nil
    case .success(let reading?):
      return ExactPowerPointSlideIdentityReading(
        windowIdentity: reading.windowIdentity,
        bindingSessionToken: reading.bindingSessionToken,
        slideShowObjectToken: reading.slideShowObjectToken,
        captureOperationID: reading.captureOperationID,
        captureGeneration: reading.captureGeneration,
        pollToken: request.pollToken,
        acquiredMachAbsoluteTime: reading.acquiredMachAbsoluteTime,
        slideID: reading.slideID,
        slideIndex: reading.slideIndex
      )
    case .exactSuccess(let reading?):
      return reading
    case .failure(let error):
      throw error
    }
  }
}

private actor ControllableSlideIdentityPollWaiter: PowerPointSlideIdentityPollWaiting {
  private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
  private var cancelledWaits: Set<UUID> = []

  func waitUntilNextPoll() async throws {
    let waitID = UUID()
    try Task.checkCancellation()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, Error>) in
        if cancelledWaits.remove(waitID) != nil {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters[waitID] = continuation
        }
      }
    } onCancel: {
      Task { await self.cancel(waitID) }
    }
  }

  func advance() {
    guard let waitID = waiters.keys.first,
      let continuation = waiters.removeValue(forKey: waitID)
    else {
      return
    }
    continuation.resume()
  }

  private func cancel(_ waitID: UUID) {
    if let continuation = waiters.removeValue(forKey: waitID) {
      continuation.resume(throwing: CancellationError())
    } else {
      cancelledWaits.insert(waitID)
    }
  }
}

private struct FailingSlideIdentityPollWaiter: PowerPointSlideIdentityPollWaiting {
  func waitUntilNextPoll() async throws {
    throw PowerPointSlideIdentityProviderTestError.controlledFailure
  }
}

private actor NoncooperativeSlideIdentityPollWaiter: PowerPointSlideIdentityPollWaiting {
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var waitCount = 0

  func waitUntilNextPoll() async throws {
    waitCount += 1
    await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume() {
    continuation?.resume()
    continuation = nil
  }
}

private actor NoncooperativePowerPointSlideIdentityMachClock:
  PowerPointSlideIdentityMachClock
{
  private var continuation: CheckedContinuation<UInt64, Never>?
  private(set) var callCount = 0

  func now() async -> UInt64 {
    callCount += 1
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume(with time: UInt64) {
    continuation?.resume(returning: time)
    continuation = nil
  }
}

private final class SlideIdentityObservationRecorder: @unchecked Sendable {
  private let lock = NSLock()
  private var storage: [PowerPointSlideIdentityObservation] = []

  var observations: [PowerPointSlideIdentityObservation] {
    lock.withLock { storage }
  }

  func record(_ observation: PowerPointSlideIdentityObservation) {
    lock.withLock {
      storage.append(observation)
    }
  }
}
