import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import LectureBoardCore
import ScreenCaptureKit

enum PowerPointManagedSlideShowRoleCaptureEvidenceFailure: Error, Equatable, Sendable {
  case malformedLease
  case inactiveLease
  case requestMismatch
  case captureAnchorUnavailable
  case inventoryUnavailable
  case inventoryDrift
  case auxiliaryStreamUnavailable
  case deliveryUnavailable
  case deliveryTimedOut
  case malformedDelivery
  case unsupportedDeliveryStatus
  case deliveryIdentityMismatch
  case deliveryCaptureOperationMismatch
  case deliveryCaptureGenerationMismatch
  case deliveryStreamMemberMismatch
  case deliveryContinuityMismatch
  case deliverySequenceNotIncreasing
  case deliveryCallbackNotIncreasing
  case deliveryCallbackOutOfBounds
  case generatedDisplayTimeInvalid
  case idleWithoutPriorPayload
  case idlePayloadChanged
  case candidateMutationRequiresGeneratedPayload
  case semanticEvidenceUnavailable
  case semanticEvidenceMismatch
  case semanticEvidenceTimeOutOfBounds
  case localClockInvalid
}

/// Raw delivery attestation from one retained ScreenCaptureKit stream member.
///
/// Optional fields deliberately preserve malformed injected evidence for fail-closed validation.
/// Production recorders fill every field only after a usable generated or continuous idle sample.
struct PowerPointManagedSlideShowRoleCaptureDelivery: Equatable, Sendable {
  let identity: PowerPointWindowIdentity?
  let status: ManagedSlideShowRoleWindowDeliveryStatus?
  let captureOperationID: CaptureOperationID?
  let captureGeneration: UInt64?
  let streamMemberToken: String?
  let continuityToken: String?
  let deliverySequence: UInt64?
  let callbackMachAbsoluteTime: UInt64?
  let displayTime: UInt64?
  let fingerprint: FrameFingerprint?
}

protocol PowerPointManagedSlideShowRoleRetainedWindowReference: AnyObject, Sendable {
  var identity: PowerPointWindowIdentity { get }
}

protocol PowerPointManagedSlideShowRoleCaptureDeliverySource: AnyObject, Sendable {
  var retainedIdentity: PowerPointWindowIdentity { get }
  var streamMemberToken: String { get }
  var continuityToken: String { get }

  func start() async throws
  func currentDelivery() async -> PowerPointManagedSlideShowRoleCaptureDelivery?
  func nextDelivery(
    after request: PowerPointManagedSlideShowRoleCaptureDeliveryRequest
  ) async throws -> PowerPointManagedSlideShowRoleCaptureDelivery
  func stop() async
}

struct PowerPointManagedSlideShowRoleCaptureDeliveryRequest: Equatable, Sendable {
  let commandReplyMachAbsoluteTime: UInt64
  let requestStartedMachAbsoluteTime: UInt64
}

protocol PowerPointManagedSlideShowRoleAuxiliaryStreamFactory: Sendable {
  func makeSource(
    for retainedWindow: any PowerPointManagedSlideShowRoleRetainedWindowReference,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64
  ) throws -> any PowerPointManagedSlideShowRoleCaptureDeliverySource
}

protocol PowerPointManagedSlideShowRoleWindowInventoryReading: Sendable {
  func currentPowerPointWindowIdentities(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [PowerPointWindowIdentity]
}

protocol PowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadlineWaiting: Sendable {
  func waitForDeadline() async
}

struct SystemPowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadline:
  PowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadlineWaiting
{
  func waitForDeadline() async {
    try? await Task.sleep(for: .seconds(1))
  }
}

struct PowerPointManagedSlideShowRoleWindowEvidenceSnapshot: Equatable, Sendable {
  let candidateDisplayTime: UInt64?
  let windows: [ManagedSlideShowRoleWindowEvidence]
}

private enum PowerPointManagedSlideShowRoleCaptureEvidenceCleanupOutcome: Sendable {
  case completed
  case deadlineReached
}

private actor PowerPointManagedSlideShowRoleCaptureEvidenceCleanupRace {
  private var outcome: PowerPointManagedSlideShowRoleCaptureEvidenceCleanupOutcome?
  private var continuation:
    CheckedContinuation<PowerPointManagedSlideShowRoleCaptureEvidenceCleanupOutcome, Never>?

  func wait() async -> PowerPointManagedSlideShowRoleCaptureEvidenceCleanupOutcome {
    if let outcome { return outcome }
    return await withCheckedContinuation { continuation = $0 }
  }

  func publish(_ newOutcome: PowerPointManagedSlideShowRoleCaptureEvidenceCleanupOutcome) {
    guard outcome == nil else { return }
    outcome = newOutcome
    continuation?.resume(returning: newOutcome)
    continuation = nil
  }
}

/// Exact-window capture lease used by the Stage B evidence reader.
///
/// The candidate source is the primary stream recorder supplied by `PowerPointWindowCapture`.
/// Auxiliary sources can be made only from the exact `SCWindow` references retained in the same
/// start snapshot. A later shareable-content scan is used solely to prove inventory continuity;
/// its newly returned objects are never selected for capture by numeric window identifier.
actor PowerPointManagedSlideShowRoleCaptureEvidenceLease {
  nonisolated let captureOperationID: CaptureOperationID
  nonisolated let captureGeneration: UInt64
  nonisolated let candidateIdentity: PowerPointWindowIdentity

  private let primarySource: any PowerPointManagedSlideShowRoleCaptureDeliverySource
  private let retainedWindows: [Int: any PowerPointManagedSlideShowRoleRetainedWindowReference]
  private let inventoryReader: any PowerPointManagedSlideShowRoleWindowInventoryReading
  private let auxiliaryFactory: any PowerPointManagedSlideShowRoleAuxiliaryStreamFactory
  private let cleanupDeadline:
    any PowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadlineWaiting

  private var auxiliarySources: [Int: any PowerPointManagedSlideShowRoleCaptureDeliverySource] = [:]
  private var acceptedDeliveries: [Int: PowerPointManagedSlideShowRoleCaptureDelivery] = [:]
  private var issuedCaptureAnchor: ManagedSlideShowRoleChallengeCaptureAnchor?
  private var currentPhase: (ManagedSlideShowRoleChallengePhase, UInt64)?
  private var readInFlight = false
  private var stopped = false
  private var poisoned = false
  private var drainingCleanupTasks: [UUID: Task<Void, Never>] = [:]

  init(
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    candidateIdentity: PowerPointWindowIdentity,
    retainedWindows: [any PowerPointManagedSlideShowRoleRetainedWindowReference],
    primarySource: any PowerPointManagedSlideShowRoleCaptureDeliverySource,
    inventoryReader: any PowerPointManagedSlideShowRoleWindowInventoryReading,
    auxiliaryFactory: any PowerPointManagedSlideShowRoleAuxiliaryStreamFactory,
    cleanupDeadline:
      any PowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadlineWaiting =
      SystemPowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadline()
  ) throws {
    var indexedWindows: [Int: any PowerPointManagedSlideShowRoleRetainedWindowReference] = [:]
    for retainedWindow in retainedWindows {
      let identity = retainedWindow.identity
      guard identity.ownerProcessID == candidateIdentity.ownerProcessID,
        identity.bundleIdentifier == candidateIdentity.bundleIdentifier,
        indexedWindows[Int(identity.windowID)] == nil
      else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
      }
      indexedWindows[Int(identity.windowID)] = retainedWindow
    }
    guard captureOperationID.rawValue > 0, captureGeneration > 0,
      indexedWindows[Int(candidateIdentity.windowID)]?.identity == candidateIdentity,
      primarySource.retainedIdentity == candidateIdentity,
      Self.isValidToken(primarySource.streamMemberToken),
      Self.isValidToken(primarySource.continuityToken)
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
    }

    self.captureOperationID = captureOperationID
    self.captureGeneration = captureGeneration
    self.candidateIdentity = candidateIdentity
    self.retainedWindows = indexedWindows
    self.primarySource = primarySource
    self.inventoryReader = inventoryReader
    self.auxiliaryFactory = auxiliaryFactory
    self.cleanupDeadline = cleanupDeadline
  }

  func captureAnchor() async throws -> ManagedSlideShowRoleChallengeCaptureAnchor {
    guard !stopped, !poisoned, !Task.isCancelled else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
    }
    if let issuedCaptureAnchor { return issuedCaptureAnchor }
    let delivery: PowerPointManagedSlideShowRoleCaptureDelivery
    if let currentDelivery = await primarySource.currentDelivery() {
      delivery = currentDelivery
    } else {
      guard !stopped, !poisoned, !Task.isCancelled else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
      }
      do {
        // This recorder is created for the exact primary stream before that stream starts. Zero is
        // therefore the lower bound for its first attested positive callback, not an invented
        // command time.
        delivery = try await primarySource.nextDelivery(
          after: PowerPointManagedSlideShowRoleCaptureDeliveryRequest(
            commandReplyMachAbsoluteTime: 0,
            requestStartedMachAbsoluteTime: 0
          )
        )
      } catch let failure as PowerPointManagedSlideShowRoleCaptureEvidenceFailure {
        throw failure
      } catch {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.captureAnchorUnavailable
      }
    }
    guard !stopped, !poisoned, !Task.isCancelled else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
    }
    let validated = try validate(
      delivery,
      source: primarySource,
      request: nil,
      prior: nil,
      isCandidate: true,
      firstObservationInPhase: false
    )
    acceptedDeliveries[Int(candidateIdentity.windowID)] = delivery
    let anchor = ManagedSlideShowRoleChallengeCaptureAnchor(
      candidateStreamMemberToken: validated.streamMemberToken,
      candidateContinuityToken: validated.continuityToken,
      minimumCandidateDeliverySequenceExclusive: validated.deliverySequence
    )
    issuedCaptureAnchor = anchor
    return anchor
  }

  func readWindowEvidence(
    for request: PowerPointManagedSlideShowRoleFreshEvidenceRequest
  ) async throws -> PowerPointManagedSlideShowRoleWindowEvidenceSnapshot {
    guard !stopped, !poisoned, !readInFlight else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
    }
    guard request.captureOperationID == captureOperationID.rawValue,
      request.captureGeneration == captureGeneration,
      request.candidateWindowIdentity == managedIdentity(candidateIdentity),
      request.processIdentifier == Int(candidateIdentity.ownerProcessID),
      request.bundleIdentifier == candidateIdentity.bundleIdentifier,
      request.captureAnchor == issuedCaptureAnchor
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.requestMismatch
    }

    readInFlight = true
    defer { readInFlight = false }
    do {
      let currentIdentities: [PowerPointWindowIdentity]
      do {
        currentIdentities = try await inventoryReader.currentPowerPointWindowIdentities(
          processIdentifier: candidateIdentity.ownerProcessID,
          bundleIdentifier: candidateIdentity.bundleIdentifier
        )
      } catch {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inventoryUnavailable
      }
      guard !stopped, !poisoned else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
      }
      let visible = try validateInventory(currentIdentities, phase: request.phase)
      let phaseKey = (request.phase, request.nonce)
      let firstObservationInPhase =
        currentPhase.map {
          $0.0 != phaseKey.0 || $0.1 != phaseKey.1
        } ?? true

      var pending:
        [(
          source: any PowerPointManagedSlideShowRoleCaptureDeliverySource,
          delivery: PowerPointManagedSlideShowRoleCaptureDelivery,
          validated: ValidatedDelivery
        )] = []
      for identity in visible.sorted(by: { $0.windowID < $1.windowID }) {
        let source = try await source(for: identity)
        let delivery: PowerPointManagedSlideShowRoleCaptureDelivery
        do {
          delivery = try await source.nextDelivery(
            after: PowerPointManagedSlideShowRoleCaptureDeliveryRequest(
              commandReplyMachAbsoluteTime: request.minimumDisplayTimeExclusive,
              requestStartedMachAbsoluteTime: request.requestStartedMachAbsoluteTime
            )
          )
        } catch let failure as PowerPointManagedSlideShowRoleCaptureEvidenceFailure {
          throw failure
        } catch {
          throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryUnavailable
        }
        guard !stopped, !poisoned else {
          throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
        }
        let windowID = Int(identity.windowID)
        pending.append(
          (
            source,
            delivery,
            try validate(
              delivery,
              source: source,
              request: request,
              prior: acceptedDeliveries[windowID],
              isCandidate: identity == candidateIdentity,
              firstObservationInPhase: firstObservationInPhase
            )
          )
        )
      }

      var evidence = pending.map { item in
        ManagedSlideShowRoleWindowEvidence(
          identity: managedIdentity(item.validated.identity),
          fingerprint: item.validated.fingerprint,
          isOnScreen: true,
          displayTime: item.validated.displayTime,
          deliveryProvenance: ManagedSlideShowRoleWindowDeliveryProvenance(
            status: item.validated.status,
            captureOperationID: captureOperationID.rawValue,
            captureGeneration: captureGeneration,
            streamMemberToken: item.validated.streamMemberToken,
            continuityToken: item.validated.continuityToken,
            deliverySequence: item.validated.deliverySequence,
            callbackMachAbsoluteTime: item.validated.callbackMachAbsoluteTime
          )
        )
      }
      if !visible.contains(candidateIdentity) {
        evidence.append(
          ManagedSlideShowRoleWindowEvidence(
            identity: managedIdentity(candidateIdentity),
            fingerprint: nil,
            isOnScreen: false,
            displayTime: nil,
            deliveryProvenance: nil
          )
        )
      }
      for item in pending {
        acceptedDeliveries[Int(item.validated.identity.windowID)] = item.delivery
      }
      currentPhase = phaseKey
      evidence.sort { $0.identity.windowID < $1.identity.windowID }
      let candidateDisplayTime = evidence.first {
        $0.identity == managedIdentity(candidateIdentity)
      }?.displayTime
      return PowerPointManagedSlideShowRoleWindowEvidenceSnapshot(
        candidateDisplayTime: candidateDisplayTime,
        windows: evidence
      )
    } catch {
      poisoned = true
      throw error
    }
  }

  /// Stops every source without allowing one noncooperative stop to hold the caller indefinitely.
  /// Late drains remain retained by this lease/task cycle until their exact source finally returns.
  func stop() async {
    guard !stopped else { return }
    stopped = true
    poisoned = true
    let sources = [primarySource] + auxiliarySources.values
    for source in sources {
      let token = UUID()
      let race = PowerPointManagedSlideShowRoleCaptureEvidenceCleanupRace()
      let lease = self
      let task = Task.detached {
        await source.stop()
        await race.publish(.completed)
        await lease.cleanupDidDrain(token: token)
      }
      drainingCleanupTasks[token] = task
      let cleanupDeadline = self.cleanupDeadline
      let deadlineTask = Task.detached {
        await cleanupDeadline.waitForDeadline()
        await race.publish(.deadlineReached)
      }
      _ = await race.wait()
      deadlineTask.cancel()
    }
  }

  private func cleanupDidDrain(token: UUID) {
    drainingCleanupTasks[token] = nil
  }

  private func source(
    for identity: PowerPointWindowIdentity
  ) async throws -> any PowerPointManagedSlideShowRoleCaptureDeliverySource {
    if identity == candidateIdentity { return primarySource }
    let windowID = Int(identity.windowID)
    if let existing = auxiliarySources[windowID] { return existing }
    guard let retainedWindow = retainedWindows[windowID], retainedWindow.identity == identity else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inventoryDrift
    }
    let source: any PowerPointManagedSlideShowRoleCaptureDeliverySource
    do {
      source = try auxiliaryFactory.makeSource(
        for: retainedWindow,
        captureOperationID: captureOperationID,
        captureGeneration: captureGeneration
      )
    } catch {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.auxiliaryStreamUnavailable
    }
    guard source.retainedIdentity == identity,
      Self.isValidToken(source.streamMemberToken),
      Self.isValidToken(source.continuityToken),
      source.streamMemberToken != primarySource.streamMemberToken,
      !auxiliarySources.values.contains(where: {
        $0.streamMemberToken == source.streamMemberToken
      })
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
    }
    // Retain before the first suspension so a timed-out or noncooperative start cannot orphan its
    // exact SCWindow/SCStream handle.
    auxiliarySources[windowID] = source
    do {
      try await source.start()
    } catch {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.auxiliaryStreamUnavailable
    }
    guard !stopped, !poisoned else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
    }
    return source
  }

  private func validateInventory(
    _ identities: [PowerPointWindowIdentity],
    phase: ManagedSlideShowRoleChallengePhase
  ) throws -> Set<PowerPointWindowIdentity> {
    let visible = Set(identities)
    guard visible.count == identities.count,
      identities.allSatisfy({ identity in
        identity.ownerProcessID == candidateIdentity.ownerProcessID
          && identity.bundleIdentifier == candidateIdentity.bundleIdentifier
          && retainedWindows[Int(identity.windowID)]?.identity == identity
      })
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inventoryDrift
    }
    let retained = Set(retainedWindows.values.map(\.identity))
    if phase == .visibilityHidden {
      guard visible == retained || visible == retained.subtracting([candidateIdentity]) else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inventoryDrift
      }
    } else {
      guard visible == retained else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inventoryDrift
      }
    }
    return visible
  }

  private struct ValidatedDelivery {
    let identity: PowerPointWindowIdentity
    let status: ManagedSlideShowRoleWindowDeliveryStatus
    let streamMemberToken: String
    let continuityToken: String
    let deliverySequence: UInt64
    let callbackMachAbsoluteTime: UInt64
    let displayTime: UInt64
    let fingerprint: FrameFingerprint
  }

  private func validate(
    _ delivery: PowerPointManagedSlideShowRoleCaptureDelivery,
    source: any PowerPointManagedSlideShowRoleCaptureDeliverySource,
    request: PowerPointManagedSlideShowRoleFreshEvidenceRequest?,
    prior: PowerPointManagedSlideShowRoleCaptureDelivery?,
    isCandidate: Bool,
    firstObservationInPhase: Bool
  ) throws -> ValidatedDelivery {
    guard let identity = delivery.identity,
      let status = delivery.status,
      let deliveryOperationID = delivery.captureOperationID,
      let deliveryGeneration = delivery.captureGeneration,
      let streamMemberToken = delivery.streamMemberToken,
      let continuityToken = delivery.continuityToken,
      let deliverySequence = delivery.deliverySequence,
      let callbackMachAbsoluteTime = delivery.callbackMachAbsoluteTime,
      let displayTime = delivery.displayTime,
      let fingerprint = delivery.fingerprint,
      deliverySequence > 0,
      callbackMachAbsoluteTime > 0,
      displayTime > 0,
      displayTime <= callbackMachAbsoluteTime,
      fingerprint.isValid,
      Self.isValidToken(streamMemberToken),
      Self.isValidToken(continuityToken)
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedDelivery
    }
    guard status == .generated || status == .idle else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.unsupportedDeliveryStatus
    }
    guard identity == source.retainedIdentity else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryIdentityMismatch
    }
    guard deliveryOperationID == captureOperationID else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure
        .deliveryCaptureOperationMismatch
    }
    guard deliveryGeneration == captureGeneration else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure
        .deliveryCaptureGenerationMismatch
    }
    guard streamMemberToken == source.streamMemberToken else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryStreamMemberMismatch
    }
    guard continuityToken == source.continuityToken else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryContinuityMismatch
    }
    if let request {
      guard callbackMachAbsoluteTime > request.minimumDisplayTimeExclusive,
        callbackMachAbsoluteTime >= request.requestStartedMachAbsoluteTime
      else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryCallbackOutOfBounds
      }
      if isCandidate, firstObservationInPhase, request.phase != .baseline,
        status != .generated
      {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure
          .candidateMutationRequiresGeneratedPayload
      }
    }
    if let prior {
      guard let priorSequence = prior.deliverySequence,
        deliverySequence > priorSequence
      else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure
          .deliverySequenceNotIncreasing
      }
      guard let priorCallback = prior.callbackMachAbsoluteTime,
        callbackMachAbsoluteTime > priorCallback
      else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure
          .deliveryCallbackNotIncreasing
      }
      guard prior.streamMemberToken == streamMemberToken else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryStreamMemberMismatch
      }
      guard prior.continuityToken == continuityToken else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryContinuityMismatch
      }
    }

    switch status {
    case .generated:
      if let request {
        guard displayTime > request.minimumDisplayTimeExclusive,
          displayTime >= request.requestStartedMachAbsoluteTime
        else {
          throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.generatedDisplayTimeInvalid
        }
      }
      if let priorDisplayTime = prior?.displayTime, displayTime <= priorDisplayTime {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.generatedDisplayTimeInvalid
      }
    case .idle:
      // `currentDelivery()` is the primary recorder's already-attested payload. It may be idle at
      // anchor creation because that recorder itself preserves the last generated payload across
      // uninterrupted idle callbacks. An unanchored delivery read still fails closed.
      guard let prior else {
        guard request == nil, isCandidate else {
          throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.idleWithoutPriorPayload
        }
        break
      }
      guard prior.identity == identity, prior.fingerprint == fingerprint,
        prior.displayTime == displayTime
      else {
        throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.idlePayloadChanged
      }
    case .blank, .suspended, .stopped:
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.unsupportedDeliveryStatus
    }

    return ValidatedDelivery(
      identity: identity,
      status: status,
      streamMemberToken: streamMemberToken,
      continuityToken: continuityToken,
      deliverySequence: deliverySequence,
      callbackMachAbsoluteTime: callbackMachAbsoluteTime,
      displayTime: displayTime,
      fingerprint: fingerprint
    )
  }

  private nonisolated static func isValidToken(_ token: String) -> Bool {
    !token.isEmpty && token == token.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private nonisolated func managedIdentity(
    _ identity: PowerPointWindowIdentity
  ) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: Int(identity.windowID),
      processIdentifier: Int(identity.ownerProcessID),
      bundleIdentifier: identity.bundleIdentifier
    )
  }
}

/// Production Stage B reader joining exact-object semantic state to exact-stream visual evidence.
///
/// The broker never discovers or selects a window. It can consume only the primary and retained
/// auxiliary sources owned by its capture lease.
actor PowerPointManagedSlideShowRoleCaptureEvidenceBroker:
  PowerPointManagedSlideShowRoleFreshEvidenceReading
{
  private let lease: PowerPointManagedSlideShowRoleCaptureEvidenceLease
  private let semanticReader: any PowerPointManagedSlideShowRoleSemanticStateReadingClient
  private let machClock: any ManagedSlideShowBindingMachClock
  private let semanticRequestTokenFactory: @Sendable () -> String
  private var issuedSemanticRequestTokens: Set<String> = []

  init(
    lease: PowerPointManagedSlideShowRoleCaptureEvidenceLease,
    semanticReader: any PowerPointManagedSlideShowRoleSemanticStateReadingClient,
    machClock: any ManagedSlideShowBindingMachClock = SystemManagedSlideShowBindingMachClock(),
    semanticRequestTokenFactory: @escaping @Sendable () -> String = {
      UUID().uuidString
    }
  ) {
    self.lease = lease
    self.semanticReader = semanticReader
    self.machClock = machClock
    self.semanticRequestTokenFactory = semanticRequestTokenFactory
  }

  func readFreshEvidence(
    _ request: PowerPointManagedSlideShowRoleFreshEvidenceRequest
  ) async throws -> PowerPointManagedSlideShowRoleFreshEvidence {
    guard request.captureOperationID == lease.captureOperationID.rawValue,
      request.captureGeneration == lease.captureGeneration,
      request.candidateWindowIdentity == managedIdentity(lease.candidateIdentity),
      request.processIdentifier == Int(lease.candidateIdentity.ownerProcessID),
      request.bundleIdentifier == lease.candidateIdentity.bundleIdentifier,
      request.minimumDisplayTimeExclusive > 0,
      request.requestStartedMachAbsoluteTime > request.minimumDisplayTimeExclusive,
      isValidToken(request.freshRequestToken)
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.requestMismatch
    }

    let semanticStartedMachAbsoluteTime = await machClock.now()
    guard semanticStartedMachAbsoluteTime >= request.requestStartedMachAbsoluteTime else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.localClockInvalid
    }
    let semanticToken = semanticRequestTokenFactory()
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidToken(semanticToken), issuedSemanticRequestTokens.insert(semanticToken).inserted
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.semanticEvidenceMismatch
    }
    let semanticRequest = PowerPointManagedSlideShowRoleSemanticStateRequest(
      bindingSessionToken: request.bindingSessionToken,
      slideShowObjectToken: request.slideShowObjectToken,
      processIdentifier: request.processIdentifier,
      bundleIdentifier: request.bundleIdentifier,
      freshRequestToken: semanticToken,
      requestStartedMachAbsoluteTime: semanticStartedMachAbsoluteTime
    )
    let semanticReading: PowerPointManagedSlideShowRoleSemanticStateReading
    do {
      semanticReading = try await semanticReader.readExactRoleSemanticState(semanticRequest)
    } catch {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.semanticEvidenceUnavailable
    }
    let semanticCompletedMachAbsoluteTime = await machClock.now()
    guard semanticCompletedMachAbsoluteTime > semanticStartedMachAbsoluteTime else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.localClockInvalid
    }
    guard semanticReading.request == semanticRequest else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.semanticEvidenceMismatch
    }
    guard semanticReading.acquiredMachAbsoluteTime > semanticStartedMachAbsoluteTime,
      semanticReading.acquiredMachAbsoluteTime <= semanticCompletedMachAbsoluteTime,
      semanticReading.semanticState.slideID > 0,
      semanticReading.semanticState.slideIndex > 0
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure
        .semanticEvidenceTimeOutOfBounds
    }

    let windowSnapshot = try await lease.readWindowEvidence(for: request)
    let evidenceObservedMachAbsoluteTime = await machClock.now()
    let latestCallback =
      windowSnapshot.windows.compactMap {
        $0.deliveryProvenance?.callbackMachAbsoluteTime
      }.max() ?? 0
    guard evidenceObservedMachAbsoluteTime > semanticCompletedMachAbsoluteTime,
      evidenceObservedMachAbsoluteTime >= latestCallback,
      evidenceObservedMachAbsoluteTime > request.minimumDisplayTimeExclusive
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.localClockInvalid
    }

    return PowerPointManagedSlideShowRoleFreshEvidence(
      freshRequestToken: request.freshRequestToken,
      observation: ManagedSlideShowRoleChallengeObservation(
        bindingSessionToken: request.bindingSessionToken,
        slideShowObjectToken: request.slideShowObjectToken,
        processIdentifier: request.processIdentifier,
        bundleIdentifier: request.bundleIdentifier,
        candidateWindowIdentity: request.candidateWindowIdentity,
        captureOperationID: request.captureOperationID,
        captureGeneration: request.captureGeneration,
        phase: request.phase,
        nonce: request.nonce,
        commandReplyMachAbsoluteTime: request.minimumDisplayTimeExclusive,
        evidenceObservedMachAbsoluteTime: evidenceObservedMachAbsoluteTime,
        candidateDisplayTime: windowSnapshot.candidateDisplayTime,
        inventoryIsComplete: true,
        semanticState: semanticReading.semanticState,
        windows: windowSnapshot.windows
      )
    )
  }

  func stop() async {
    await lease.stop()
  }

  private nonisolated func managedIdentity(
    _ identity: PowerPointWindowIdentity
  ) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: Int(identity.windowID),
      processIdentifier: Int(identity.ownerProcessID),
      bundleIdentifier: identity.bundleIdentifier
    )
  }

  private nonisolated func isValidToken(_ token: String) -> Bool {
    !token.isEmpty && token == token.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

final class PowerPointManagedSlideShowRoleScreenCaptureWindowReference:
  PowerPointManagedSlideShowRoleRetainedWindowReference, @unchecked Sendable
{
  let identity: PowerPointWindowIdentity
  let window: SCWindow

  init?(window: SCWindow) {
    guard let application = window.owningApplication,
      let identity = PowerPointWindowIdentity(
        windowID: window.windowID,
        ownerProcessID: application.processID,
        bundleIdentifier: application.bundleIdentifier
      )
    else {
      return nil
    }
    self.identity = identity
    self.window = window
  }
}

struct PowerPointManagedSlideShowRoleScreenCaptureInventoryReader:
  PowerPointManagedSlideShowRoleWindowInventoryReading
{
  func currentPowerPointWindowIdentities(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [PowerPointWindowIdentity] {
    let content = try await SCShareableContent.excludingDesktopWindows(
      true,
      onScreenWindowsOnly: true
    )
    return content.windows.compactMap { window in
      guard let application = window.owningApplication,
        application.processID == processIdentifier,
        application.bundleIdentifier == bundleIdentifier
      else {
        return nil
      }
      return PowerPointWindowIdentity(
        windowID: window.windowID,
        ownerProcessID: application.processID,
        bundleIdentifier: application.bundleIdentifier
      )
    }
  }
}

private struct PowerPointManagedSlideShowRoleCaptureDeliveryWaiter {
  let id: UUID
  let request: PowerPointManagedSlideShowRoleCaptureDeliveryRequest
  let continuation: CheckedContinuation<PowerPointManagedSlideShowRoleCaptureDelivery, any Error>
}

/// Thread-safe recorder shared with the already-running primary `CaptureOutput`.
///
/// It never creates a capture stream. A gap permanently poisons this stream lineage, and each wait
/// has its own finite deadline because Apple does not guarantee periodic idle callbacks.
final class PowerPointManagedSlideShowRoleCaptureDeliveryBuffer:
  PowerPointManagedSlideShowRoleCaptureDeliverySource, @unchecked Sendable
{
  typealias StopAction = @Sendable () async -> Void

  let retainedIdentity: PowerPointWindowIdentity
  let streamMemberToken: String
  let continuityToken: String

  private let captureOperationID: CaptureOperationID
  private let captureGeneration: UInt64
  private let deliveryTimeout: TimeInterval
  private let lock = NSLock()
  private var latestDelivery: PowerPointManagedSlideShowRoleCaptureDelivery?
  private var failure: PowerPointManagedSlideShowRoleCaptureEvidenceFailure?
  private var waiter: PowerPointManagedSlideShowRoleCaptureDeliveryWaiter?
  private var isStopped = false
  private var stopAction: StopAction?

  init(
    identity: PowerPointWindowIdentity,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    streamMemberToken: String,
    continuityToken: String,
    deliveryTimeout: TimeInterval = 1
  ) {
    retainedIdentity = identity
    self.captureOperationID = captureOperationID
    self.captureGeneration = captureGeneration
    self.streamMemberToken = streamMemberToken
    self.continuityToken = continuityToken
    self.deliveryTimeout = min(max(deliveryTimeout, 0.1), 5)
  }

  func start() async throws {}

  func currentDelivery() async -> PowerPointManagedSlideShowRoleCaptureDelivery? {
    lock.withLock { failure == nil && !isStopped ? latestDelivery : nil }
  }

  func nextDelivery(
    after request: PowerPointManagedSlideShowRoleCaptureDeliveryRequest
  ) async throws -> PowerPointManagedSlideShowRoleCaptureDelivery {
    try await withCheckedThrowingContinuation { continuation in
      let waiterID = UUID()
      let immediate: Result<PowerPointManagedSlideShowRoleCaptureDelivery, any Error>? =
        lock.withLock {
          if isStopped {
            return .failure(
              PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
            )
          }
          if let failure { return .failure(failure) }
          if let latestDelivery, Self.isFresh(latestDelivery, for: request) {
            return .success(latestDelivery)
          }
          guard waiter == nil else {
            return .failure(
              PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryUnavailable
            )
          }
          waiter = PowerPointManagedSlideShowRoleCaptureDeliveryWaiter(
            id: waiterID,
            request: request,
            continuation: continuation
          )
          return nil
        }
      if let immediate {
        continuation.resume(with: immediate)
        return
      }
      DispatchQueue.global(qos: .userInitiated).asyncAfter(
        deadline: .now() + deliveryTimeout
      ) { [weak self] in
        self?.expireWaiter(waiterID)
      }
    }
  }

  func installStopAction(_ action: @escaping StopAction) throws {
    let accepted = lock.withLock {
      guard !isStopped, stopAction == nil else { return false }
      stopAction = action
      return true
    }
    guard accepted else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
    }
  }

  func stop() async {
    let stopped = lock.withLock {
      () -> (PowerPointManagedSlideShowRoleCaptureDeliveryWaiter?, StopAction?)? in
      guard !isStopped else { return nil }
      isStopped = true
      let pending = waiter
      waiter = nil
      let action = stopAction
      stopAction = nil
      return (pending, action)
    }
    stopped?.0?.continuation.resume(
      throwing: PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
    )
    if let action = stopped?.1 {
      await action()
    }
  }

  func recordGenerated(
    fingerprint: FrameFingerprint,
    displayTime: UInt64?,
    deliverySequence: UInt64,
    callbackMachAbsoluteTime: UInt64
  ) {
    guard let displayTime else {
      recordGap()
      return
    }
    record(
      PowerPointManagedSlideShowRoleCaptureDelivery(
        identity: retainedIdentity,
        status: .generated,
        captureOperationID: captureOperationID,
        captureGeneration: captureGeneration,
        streamMemberToken: streamMemberToken,
        continuityToken: continuityToken,
        deliverySequence: deliverySequence,
        callbackMachAbsoluteTime: callbackMachAbsoluteTime,
        displayTime: displayTime,
        fingerprint: fingerprint
      )
    )
  }

  func recordIdle(
    deliverySequence: UInt64,
    callbackMachAbsoluteTime: UInt64
  ) {
    let delivery = lock.withLock { () -> PowerPointManagedSlideShowRoleCaptureDelivery? in
      guard failure == nil, !isStopped,
        let latestDelivery,
        let displayTime = latestDelivery.displayTime,
        let fingerprint = latestDelivery.fingerprint
      else {
        return nil
      }
      return PowerPointManagedSlideShowRoleCaptureDelivery(
        identity: retainedIdentity,
        status: .idle,
        captureOperationID: captureOperationID,
        captureGeneration: captureGeneration,
        streamMemberToken: streamMemberToken,
        continuityToken: continuityToken,
        deliverySequence: deliverySequence,
        callbackMachAbsoluteTime: callbackMachAbsoluteTime,
        displayTime: displayTime,
        fingerprint: fingerprint
      )
    }
    guard let delivery else {
      recordGap()
      return
    }
    record(delivery)
  }

  func recordGap() {
    fail(.deliveryUnavailable)
  }

  private func record(_ delivery: PowerPointManagedSlideShowRoleCaptureDelivery) {
    let result = lock.withLock {
      () -> (
        continuation: CheckedContinuation<PowerPointManagedSlideShowRoleCaptureDelivery, any Error>,
        result: Result<PowerPointManagedSlideShowRoleCaptureDelivery, any Error>
      )? in
      guard failure == nil, !isStopped else { return nil }
      if let latestDelivery {
        let newFailure: PowerPointManagedSlideShowRoleCaptureEvidenceFailure?
        if (delivery.deliverySequence ?? 0) <= (latestDelivery.deliverySequence ?? 0) {
          newFailure = .deliverySequenceNotIncreasing
        } else if (delivery.callbackMachAbsoluteTime ?? 0)
          <= (latestDelivery.callbackMachAbsoluteTime ?? 0)
        {
          newFailure = .deliveryCallbackNotIncreasing
        } else {
          newFailure = nil
        }
        if let newFailure {
          failure = newFailure
          guard let continuation = waiter?.continuation else { return nil }
          waiter = nil
          return (continuation, .failure(newFailure))
        }
      }
      latestDelivery = delivery
      guard let waiter, Self.isFresh(delivery, for: waiter.request) else { return nil }
      self.waiter = nil
      return (waiter.continuation, .success(delivery))
    }
    if let result {
      result.continuation.resume(with: result.result)
    }
  }

  private func fail(_ newFailure: PowerPointManagedSlideShowRoleCaptureEvidenceFailure) {
    let pending = lock.withLock { () -> PowerPointManagedSlideShowRoleCaptureDeliveryWaiter? in
      guard failure == nil, !isStopped else { return nil }
      failure = newFailure
      let pending = waiter
      waiter = nil
      return pending
    }
    pending?.continuation.resume(throwing: newFailure)
  }

  private func expireWaiter(_ waiterID: UUID) {
    let pending = lock.withLock { () -> PowerPointManagedSlideShowRoleCaptureDeliveryWaiter? in
      guard waiter?.id == waiterID else { return nil }
      let pending = waiter
      waiter = nil
      return pending
    }
    pending?.continuation.resume(
      throwing: PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryTimedOut
    )
  }

  private static func isFresh(
    _ delivery: PowerPointManagedSlideShowRoleCaptureDelivery,
    for request: PowerPointManagedSlideShowRoleCaptureDeliveryRequest
  ) -> Bool {
    guard let callback = delivery.callbackMachAbsoluteTime else { return false }
    return callback > request.commandReplyMachAbsoluteTime
      && callback >= request.requestStartedMachAbsoluteTime
  }
}

private enum PowerPointManagedSlideShowRoleSCFrameStatusParser {
  static func parse(_ value: Any?) -> ManagedSlideShowRoleWindowDeliveryStatus? {
    guard let value, !isBoolean(value), let rawValue = value as? Int,
      let status = SCFrameStatus(rawValue: rawValue)
    else {
      return nil
    }
    switch status {
    case .complete, .started: return .generated
    case .idle: return .idle
    case .blank: return .blank
    case .suspended: return .suspended
    case .stopped: return .stopped
    @unknown default: return nil
    }
  }

  private static func isBoolean(_ value: Any) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
  }
}

private final class PowerPointManagedSlideShowRoleAuxiliaryCaptureOutput:
  NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable
{
  let sampleHandlerQueue = DispatchQueue(
    label: "io.github.akiyama709.LectureBoardAI.role-evidence-auxiliary",
    qos: .userInitiated
  )

  private let recorder: PowerPointManagedSlideShowRoleCaptureDeliveryBuffer
  private var sequenceNumber: UInt64 = 0

  init(recorder: PowerPointManagedSlideShowRoleCaptureDeliveryBuffer) {
    self.recorder = recorder
  }

  func stream(
    _ stream: SCStream,
    didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .screen, sequenceNumber < UInt64.max else {
      recorder.recordGap()
      return
    }
    sequenceNumber += 1
    let callbackMachAbsoluteTime = mach_absolute_time()
    let attachments = frameAttachments(in: sampleBuffer)
    guard sampleBuffer.isValid,
      let status = PowerPointManagedSlideShowRoleSCFrameStatusParser.parse(
        attachments?[.status]
      )
    else {
      recorder.recordGap()
      return
    }
    switch status {
    case .generated:
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
        let fingerprint = FrameFingerprintSampler.makeFingerprint(from: pixelBuffer)
      else {
        recorder.recordGap()
        return
      }
      recorder.recordGenerated(
        fingerprint: fingerprint,
        displayTime: CaptureFrameDisplayTimeParser.parse(attachments?[.displayTime]),
        deliverySequence: sequenceNumber,
        callbackMachAbsoluteTime: callbackMachAbsoluteTime
      )
    case .idle:
      recorder.recordIdle(
        deliverySequence: sequenceNumber,
        callbackMachAbsoluteTime: callbackMachAbsoluteTime
      )
    case .blank, .suspended, .stopped:
      recorder.recordGap()
    }
  }

  func stream(_ stream: SCStream, didStopWithError error: any Error) {
    recorder.recordGap()
  }

  func streamDidBecomeInactive(_ stream: SCStream) {
    recorder.recordGap()
  }

  private func frameAttachments(
    in sampleBuffer: CMSampleBuffer
  ) -> [SCStreamFrameInfo: Any]? {
    guard
      let attachments = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: false
      ) as? [[SCStreamFrameInfo: Any]]
    else {
      return nil
    }
    return attachments.first
  }
}

private enum PowerPointManagedSlideShowRoleAuxiliaryOperationOutcome: Equatable, Sendable {
  case succeeded
  case failed
  case deadlineReached
}

private actor PowerPointManagedSlideShowRoleAuxiliaryOperationRace {
  private var outcome: PowerPointManagedSlideShowRoleAuxiliaryOperationOutcome?
  private var continuation:
    CheckedContinuation<PowerPointManagedSlideShowRoleAuxiliaryOperationOutcome, Never>?

  func wait() async -> PowerPointManagedSlideShowRoleAuxiliaryOperationOutcome {
    if let outcome { return outcome }
    return await withCheckedContinuation { continuation = $0 }
  }

  func publish(_ newOutcome: PowerPointManagedSlideShowRoleAuxiliaryOperationOutcome) {
    guard outcome == nil else { return }
    outcome = newOutcome
    continuation?.resume(returning: newOutcome)
    continuation = nil
  }
}

private final class PowerPointManagedSlideShowRoleAuxiliaryCaptureSource:
  PowerPointManagedSlideShowRoleCaptureDeliverySource, @unchecked Sendable
{
  let retainedIdentity: PowerPointWindowIdentity
  let streamMemberToken: String
  let continuityToken: String

  private let stream: SCStream
  private let output: PowerPointManagedSlideShowRoleAuxiliaryCaptureOutput
  private let recorder: PowerPointManagedSlideShowRoleCaptureDeliveryBuffer
  private let operationTimeout: Duration
  private let lock = NSLock()
  private var startTask: Task<Bool, Never>?
  private var cleanupTask: Task<Void, Never>?
  private var stopRequested = false

  init(
    retainedWindow: PowerPointManagedSlideShowRoleScreenCaptureWindowReference,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    operationTimeout: Duration = .seconds(1)
  ) throws {
    retainedIdentity = retainedWindow.identity
    streamMemberToken = UUID().uuidString
    continuityToken = UUID().uuidString
    self.operationTimeout = min(max(operationTimeout, .milliseconds(100)), .seconds(5))
    let recorder = PowerPointManagedSlideShowRoleCaptureDeliveryBuffer(
      identity: retainedWindow.identity,
      captureOperationID: captureOperationID,
      captureGeneration: captureGeneration,
      streamMemberToken: streamMemberToken,
      continuityToken: continuityToken
    )
    self.recorder = recorder
    let output = PowerPointManagedSlideShowRoleAuxiliaryCaptureOutput(recorder: recorder)
    self.output = output
    let filter = SCContentFilter(desktopIndependentWindow: retainedWindow.window)
    let configuration = Self.makeConfiguration(for: filter)
    let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
    self.stream = stream
    try stream.addStreamOutput(
      output,
      type: .screen,
      sampleHandlerQueue: output.sampleHandlerQueue
    )
  }

  func start() async throws {
    let task: Task<Bool, Never> = lock.withLock {
      if let startTask { return startTask }
      let stream = self.stream
      let task = Task.detached {
        do {
          try await stream.startCapture()
          return true
        } catch {
          return false
        }
      }
      startTask = task
      return task
    }
    guard !lock.withLock({ stopRequested }) else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.inactiveLease
    }
    let outcome = await boundedOutcome(for: task)
    guard outcome == .succeeded else {
      throw outcome == .deadlineReached
        ? PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryTimedOut
        : PowerPointManagedSlideShowRoleCaptureEvidenceFailure.auxiliaryStreamUnavailable
    }
  }

  func currentDelivery() async -> PowerPointManagedSlideShowRoleCaptureDelivery? {
    await recorder.currentDelivery()
  }

  func nextDelivery(
    after request: PowerPointManagedSlideShowRoleCaptureDeliveryRequest
  ) async throws -> PowerPointManagedSlideShowRoleCaptureDelivery {
    try await recorder.nextDelivery(after: request)
  }

  func stop() async {
    await recorder.stop()
    let cleanup: Task<Void, Never> = lock.withLock {
      stopRequested = true
      if let cleanupTask { return cleanupTask }
      let stream = self.stream
      let output = self.output
      let startTask = self.startTask
      let cleanupTask = Task.detached {
        if let startTask { _ = await startTask.value }
        try? await stream.stopCapture()
        try? stream.removeStreamOutput(output, type: .screen)
      }
      self.cleanupTask = cleanupTask
      return cleanupTask
    }
    let race = PowerPointManagedSlideShowRoleAuxiliaryOperationRace()
    let completion = Task.detached {
      await cleanup.value
      await race.publish(.succeeded)
    }
    let timeout = operationTimeout
    let deadline = Task.detached {
      try? await Task.sleep(for: timeout)
      await race.publish(.deadlineReached)
    }
    _ = await race.wait()
    completion.cancel()
    deadline.cancel()
  }

  private func boundedOutcome(
    for task: Task<Bool, Never>
  ) async -> PowerPointManagedSlideShowRoleAuxiliaryOperationOutcome {
    let race = PowerPointManagedSlideShowRoleAuxiliaryOperationRace()
    let completion = Task.detached {
      await race.publish(await task.value ? .succeeded : .failed)
    }
    let timeout = operationTimeout
    let deadline = Task.detached {
      try? await Task.sleep(for: timeout)
      await race.publish(.deadlineReached)
    }
    let outcome = await race.wait()
    completion.cancel()
    deadline.cancel()
    return outcome
  }

  private static func makeConfiguration(for filter: SCContentFilter) -> SCStreamConfiguration {
    let configuration = SCStreamConfiguration()
    let nativeWidth = max(filter.contentRect.width * CGFloat(filter.pointPixelScale), 2)
    let nativeHeight = max(filter.contentRect.height * CGFloat(filter.pointPixelScale), 2)
    let longestEdge = max(nativeWidth, nativeHeight)
    let scale = min(1, 1920 / longestEdge)
    configuration.width = Int(nativeWidth * scale)
    configuration.height = Int(nativeHeight * scale)
    configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
    configuration.pixelFormat = kCVPixelFormatType_32BGRA
    configuration.queueDepth = 3
    configuration.scalesToFit = true
    configuration.preservesAspectRatio = true
    configuration.showsCursor = false
    configuration.capturesAudio = false
    configuration.ignoreShadowsSingleWindow = true
    return configuration
  }
}

struct PowerPointManagedSlideShowRoleScreenCaptureAuxiliaryStreamFactory:
  PowerPointManagedSlideShowRoleAuxiliaryStreamFactory
{
  func makeSource(
    for retainedWindow: any PowerPointManagedSlideShowRoleRetainedWindowReference,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64
  ) throws -> any PowerPointManagedSlideShowRoleCaptureDeliverySource {
    guard
      let retainedWindow = retainedWindow
        as? PowerPointManagedSlideShowRoleScreenCaptureWindowReference
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
    }
    return try PowerPointManagedSlideShowRoleAuxiliaryCaptureSource(
      retainedWindow: retainedWindow,
      captureOperationID: captureOperationID,
      captureGeneration: captureGeneration
    )
  }
}

struct PowerPointManagedSlideShowRoleScreenCaptureEvidenceLeaseComponents: Sendable {
  let lease: PowerPointManagedSlideShowRoleCaptureEvidenceLease
  let primaryRecorder: PowerPointManagedSlideShowRoleCaptureDeliveryBuffer
}

enum PowerPointManagedSlideShowRoleScreenCaptureEvidenceLeaseFactory {
  static func make(
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64,
    candidateWindow: SCWindow,
    retainedPowerPointWindows: [SCWindow]
  ) throws -> PowerPointManagedSlideShowRoleScreenCaptureEvidenceLeaseComponents {
    guard
      let candidateReference =
        PowerPointManagedSlideShowRoleScreenCaptureWindowReference(window: candidateWindow)
    else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
    }
    let retained = retainedPowerPointWindows.compactMap {
      PowerPointManagedSlideShowRoleScreenCaptureWindowReference(window: $0)
    }.filter {
      $0.identity.ownerProcessID == candidateReference.identity.ownerProcessID
        && $0.identity.bundleIdentifier == candidateReference.identity.bundleIdentifier
    }
    guard retained.filter({ $0.identity == candidateReference.identity }).count == 1 else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.malformedLease
    }
    let primaryRecorder = PowerPointManagedSlideShowRoleCaptureDeliveryBuffer(
      identity: candidateReference.identity,
      captureOperationID: captureOperationID,
      captureGeneration: captureGeneration,
      streamMemberToken: UUID().uuidString,
      continuityToken: UUID().uuidString
    )
    let lease = try PowerPointManagedSlideShowRoleCaptureEvidenceLease(
      captureOperationID: captureOperationID,
      captureGeneration: captureGeneration,
      candidateIdentity: candidateReference.identity,
      retainedWindows: retained,
      primarySource: primaryRecorder,
      inventoryReader: PowerPointManagedSlideShowRoleScreenCaptureInventoryReader(),
      auxiliaryFactory: PowerPointManagedSlideShowRoleScreenCaptureAuxiliaryStreamFactory()
    )
    return PowerPointManagedSlideShowRoleScreenCaptureEvidenceLeaseComponents(
      lease: lease,
      primaryRecorder: primaryRecorder
    )
  }
}
