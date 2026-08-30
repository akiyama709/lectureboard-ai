import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

struct PowerPointSlideIdentityProviderTests {
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
