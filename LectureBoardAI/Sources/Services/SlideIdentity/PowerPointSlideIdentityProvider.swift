import Foundation
import LectureBoardCore

struct PowerPointSlideIdentityObservation: Equatable, Sendable {
  let sequenceNumber: UInt64
  let observedAt: Date
  let targetIdentity: PowerPointWindowIdentity
  let signal: SlideIdentitySignal
}

typealias PowerPointSlideIdentityObservationHandler =
  @Sendable (PowerPointSlideIdentityObservation) -> Void

protocol PowerPointSlideIdentityProviding: Sendable {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async

  func stop(operationID: CaptureOperationID) async
}

/// The fail-closed default used until an exact, independently verified PowerPoint
/// slide-identity adapter is available.
///
/// It sends one metadata-only `.unavailable` observation for each accepted start.
/// It never requests Automation permission, sends Apple events, or retains a
/// presentation path, title, identity, or callback after `start` returns.
actor UnavailablePowerPointSlideIdentityProvider: PowerPointSlideIdentityProviding {
  private var lifecycle = CaptureSessionLifecycle()

  var latestOperationID: CaptureOperationID? {
    lifecycle.latestOperationID
  }

  var activeOperationID: CaptureOperationID? {
    lifecycle.activeSessionID
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async {
    guard lifecycle.acceptStart(operationID) else { return }

    onObservation(
      PowerPointSlideIdentityObservation(
        sequenceNumber: 1,
        observedAt: Date(),
        targetIdentity: identity,
        signal: .unavailable
      )
    )
  }

  func stop(operationID: CaptureOperationID) async {
    _ = lifecycle.acceptStop(operationID)
  }
}
