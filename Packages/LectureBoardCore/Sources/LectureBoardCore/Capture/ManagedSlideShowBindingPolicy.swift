import Foundation

/// Raw, platform-neutral evidence for one exact on-screen window.
///
/// The policy validates all three fields before using the evidence. The type intentionally does
/// not conform to `Codable`: window and process identifiers are runtime-only correlation material.
public struct ManagedSlideShowWindowIdentity: Equatable, Hashable, Sendable {
  public let windowID: Int
  public let processIdentifier: Int
  public let bundleIdentifier: String

  public init(
    windowID: Int,
    processIdentifier: Int,
    bundleIdentifier: String
  ) {
    self.windowID = windowID
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
  }
}

/// PowerPoint scripting evidence observed in the process under correlation.
public struct ManagedSlideShowScriptingEvidence: Equatable, Sendable {
  public let processIdentifier: Int
  public let activePresentationCount: Int
  public let slideShowWindowCount: Int

  public init(
    processIdentifier: Int,
    activePresentationCount: Int,
    slideShowWindowCount: Int
  ) {
    self.processIdentifier = processIdentifier
    self.activePresentationCount = activePresentationCount
    self.slideShowWindowCount = slideShowWindowCount
  }
}

/// One atomic observation used by ``ManagedSlideShowBindingPolicy``.
///
/// `windows` must contain only the exact-window inventory for the frozen PowerPoint process and
/// bundle. Supplying another process or bundle is rejected rather than silently filtered. The
/// fresh-observation token and mach-absolute acquisition time are runtime-only correlation
/// evidence; this type intentionally does not conform to `Codable`.
public struct ManagedSlideShowInventoryObservation: Equatable, Sendable {
  public let bindingSessionToken: String
  public let freshObservationToken: String
  public let observedMachAbsoluteTime: UInt64
  public let scriptingEvidence: ManagedSlideShowScriptingEvidence
  public let windows: [ManagedSlideShowWindowIdentity]

  public init(
    bindingSessionToken: String,
    freshObservationToken: String,
    observedMachAbsoluteTime: UInt64,
    scriptingEvidence: ManagedSlideShowScriptingEvidence,
    windows: [ManagedSlideShowWindowIdentity]
  ) {
    self.bindingSessionToken = bindingSessionToken
    self.freshObservationToken = freshObservationToken
    self.observedMachAbsoluteTime = observedMachAbsoluteTime
    self.scriptingEvidence = scriptingEvidence
    self.windows = windows
  }
}

/// The exact process and bundle frozen for one managed slide-show start attempt.
public struct ManagedSlideShowBindingTarget: Equatable, Sendable {
  public let bindingSessionToken: String
  public let processIdentifier: Int
  public let bundleIdentifier: String

  public init(
    bindingSessionToken: String,
    processIdentifier: Int,
    bundleIdentifier: String
  ) {
    self.bindingSessionToken = bindingSessionToken
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
  }
}

public enum ManagedSlideShowBindingState: String, Equatable, Sendable {
  case idle
  case awaitingSlideShowStart
  case confirmingCandidate
  case candidateConfirmed
  case rejected
}

/// A bounded reason for rejecting candidate-window correlation evidence.
public enum ManagedSlideShowBindingRejection: String, Error, Equatable, Sendable {
  case notStarted
  case startRequiresReset
  case malformedTarget
  case malformedObservationSession
  case observationSessionMismatch
  case malformedFreshObservationToken
  case malformedObservedMachAbsoluteTime
  case reusedFreshObservationToken
  case nonIncreasingObservedMachAbsoluteTime
  case malformedScriptingEvidence
  case scriptingProcessIdentifierMismatch
  case baselineActivePresentationCountNotOne
  case activePresentationCountNotOne
  case baselineSlideShowAlreadyActive
  case multipleScriptingSlideShowWindows
  case malformedWindowIdentity
  case duplicateWindowID
  case wrongWindowProcessIdentifier
  case wrongWindowBundleIdentifier
  case preTransitionInventoryChanged
  case baselineWindowMissing
  case noPreviouslyAbsentWindowID
  case multiplePreviouslyAbsentWindowIDs
  case candidateEvidenceChanged
  case confirmedCandidateEvidenceChanged
}

public enum ManagedSlideShowBindingEvent: Equatable, Sendable {
  case baselineAccepted
  case awaitingSlideShowStart
  case candidateAccepted(ManagedSlideShowWindowIdentity)
  case candidateConfirmed(ManagedSlideShowWindowIdentity)
  case stable(ManagedSlideShowWindowIdentity)
  case rejected(ManagedSlideShowBindingRejection)
}

/// Correlates a managed PowerPoint slide-show start with one exact candidate window.
///
/// The baseline and every post-start observation must show exactly one active presentation. The
/// baseline must also show zero scripting slide-show windows. A post-start observation becomes a
/// candidate only when scripting changes to exactly one slide-show window and the exact-window
/// inventory retains every baseline identity while adding exactly one previously absent ID for
/// the frozen process and bundle. The complete post-start inventory must then repeat unchanged
/// before the correlation is established. Any contradictory evidence latches its first bounded
/// rejection until ``reset()``.
///
/// This is deterministic policy only. It sends no Apple Events and does not establish that a live
/// PowerPoint provider can obtain the required evidence. An absent-then-present `CGWindowID` does
/// not by itself prove the window's PowerPoint role or exclude lifecycle reuse; production use
/// requires additional challenge evidence at a separate boundary.
public struct ManagedSlideShowBindingPolicy: Equatable, Sendable {
  public private(set) var state: ManagedSlideShowBindingState = .idle
  public private(set) var candidateWindowIdentity: ManagedSlideShowWindowIdentity?
  public private(set) var confirmedCandidateWindowIdentity: ManagedSlideShowWindowIdentity?

  private var target: ManagedSlideShowBindingTarget?
  private var baselineInventory: [Int: ManagedSlideShowWindowIdentity] = [:]
  private var candidateInventory: [Int: ManagedSlideShowWindowIdentity] = [:]
  private var usedFreshObservationTokens: Set<String> = []
  private var lastObservedMachAbsoluteTime: UInt64?
  private var latchedRejection: ManagedSlideShowBindingRejection?

  public init() {}

  /// Begins one binding attempt from an atomic pre-start observation.
  @discardableResult
  public mutating func begin(
    target: ManagedSlideShowBindingTarget,
    baseline: ManagedSlideShowInventoryObservation
  ) -> ManagedSlideShowBindingEvent {
    guard state == .idle else {
      return reject(.startRequiresReset)
    }
    guard Self.isValid(target) else {
      return reject(.malformedTarget)
    }
    if let rejection = freshnessRejection(for: baseline) {
      return reject(rejection)
    }
    guard !baseline.bindingSessionToken.isEmpty else {
      return reject(.malformedObservationSession)
    }
    guard baseline.bindingSessionToken == target.bindingSessionToken else {
      return reject(.observationSessionMismatch)
    }
    guard Self.isValid(baseline.scriptingEvidence) else {
      return reject(.malformedScriptingEvidence)
    }
    guard baseline.scriptingEvidence.processIdentifier == target.processIdentifier else {
      return reject(.scriptingProcessIdentifierMismatch)
    }
    guard baseline.scriptingEvidence.activePresentationCount == 1 else {
      return reject(.baselineActivePresentationCountNotOne)
    }
    guard baseline.scriptingEvidence.slideShowWindowCount == 0 else {
      return reject(.baselineSlideShowAlreadyActive)
    }

    let inventoryResult = Self.validatedInventory(baseline.windows, for: target)
    switch inventoryResult {
    case .failure(let rejection):
      return reject(rejection)
    case .success(let inventory):
      self.target = target
      baselineInventory = inventory
      acceptFreshness(of: baseline)
      state = .awaitingSlideShowStart
      return .baselineAccepted
    }
  }

  /// Ingests an atomic observation made after the managed start request.
  @discardableResult
  public mutating func ingest(
    _ observation: ManagedSlideShowInventoryObservation
  ) -> ManagedSlideShowBindingEvent {
    if let latchedRejection {
      return .rejected(latchedRejection)
    }
    guard state != .idle, let target else {
      return .rejected(.notStarted)
    }
    if let rejection = freshnessRejection(for: observation) {
      return reject(rejection)
    }
    guard !observation.bindingSessionToken.isEmpty else {
      return reject(.malformedObservationSession)
    }
    guard observation.bindingSessionToken == target.bindingSessionToken else {
      return reject(.observationSessionMismatch)
    }
    guard Self.isValid(observation.scriptingEvidence) else {
      return reject(.malformedScriptingEvidence)
    }
    guard observation.scriptingEvidence.processIdentifier == target.processIdentifier else {
      return reject(.scriptingProcessIdentifierMismatch)
    }
    guard observation.scriptingEvidence.activePresentationCount == 1 else {
      return reject(.activePresentationCountNotOne)
    }

    let inventoryResult = Self.validatedInventory(observation.windows, for: target)
    let inventory: [Int: ManagedSlideShowWindowIdentity]
    switch inventoryResult {
    case .failure(let rejection):
      return reject(rejection)
    case .success(let validated):
      inventory = validated
    }

    acceptFreshness(of: observation)

    switch state {
    case .idle:
      return .rejected(.notStarted)
    case .awaitingSlideShowStart:
      return ingestWhileAwaitingStart(observation.scriptingEvidence, inventory: inventory)
    case .confirmingCandidate:
      return ingestWhileConfirming(observation.scriptingEvidence, inventory: inventory)
    case .candidateConfirmed:
      return ingestWhileConfirmed(observation.scriptingEvidence, inventory: inventory)
    case .rejected:
      return .rejected(latchedRejection ?? .confirmedCandidateEvidenceChanged)
    }
  }

  public mutating func reset() {
    self = Self()
  }

  private mutating func ingestWhileAwaitingStart(
    _ scriptingEvidence: ManagedSlideShowScriptingEvidence,
    inventory: [Int: ManagedSlideShowWindowIdentity]
  ) -> ManagedSlideShowBindingEvent {
    switch scriptingEvidence.slideShowWindowCount {
    case 0:
      guard inventory == baselineInventory else {
        return reject(.preTransitionInventoryChanged)
      }
      return .awaitingSlideShowStart
    case 1:
      guard baselineIsRetained(in: inventory) else {
        return reject(.baselineWindowMissing)
      }

      let added = inventory.values.filter { baselineInventory[$0.windowID] == nil }
      guard !added.isEmpty else {
        return reject(.noPreviouslyAbsentWindowID)
      }
      guard added.count == 1, let candidate = added.first else {
        return reject(.multiplePreviouslyAbsentWindowIDs)
      }

      candidateWindowIdentity = candidate
      candidateInventory = inventory
      state = .confirmingCandidate
      return .candidateAccepted(candidate)
    default:
      return reject(.multipleScriptingSlideShowWindows)
    }
  }

  private mutating func ingestWhileConfirming(
    _ scriptingEvidence: ManagedSlideShowScriptingEvidence,
    inventory: [Int: ManagedSlideShowWindowIdentity]
  ) -> ManagedSlideShowBindingEvent {
    guard scriptingEvidence.slideShowWindowCount == 1,
      baselineIsRetained(in: inventory),
      inventory == candidateInventory,
      let candidateWindowIdentity
    else {
      return reject(.candidateEvidenceChanged)
    }

    confirmedCandidateWindowIdentity = candidateWindowIdentity
    self.candidateWindowIdentity = nil
    state = .candidateConfirmed
    return .candidateConfirmed(candidateWindowIdentity)
  }

  private mutating func ingestWhileConfirmed(
    _ scriptingEvidence: ManagedSlideShowScriptingEvidence,
    inventory: [Int: ManagedSlideShowWindowIdentity]
  ) -> ManagedSlideShowBindingEvent {
    guard scriptingEvidence.slideShowWindowCount == 1,
      inventory == candidateInventory,
      let confirmedCandidateWindowIdentity
    else {
      return reject(.confirmedCandidateEvidenceChanged)
    }

    return .stable(confirmedCandidateWindowIdentity)
  }

  private func baselineIsRetained(
    in inventory: [Int: ManagedSlideShowWindowIdentity]
  ) -> Bool {
    baselineInventory.allSatisfy { windowID, identity in
      inventory[windowID] == identity
    }
  }

  private mutating func reject(
    _ rejection: ManagedSlideShowBindingRejection
  ) -> ManagedSlideShowBindingEvent {
    if let latchedRejection {
      return .rejected(latchedRejection)
    }
    state = .rejected
    candidateWindowIdentity = nil
    confirmedCandidateWindowIdentity = nil
    candidateInventory = [:]
    latchedRejection = rejection
    return .rejected(rejection)
  }

  private func freshnessRejection(
    for observation: ManagedSlideShowInventoryObservation
  ) -> ManagedSlideShowBindingRejection? {
    guard
      !observation.freshObservationToken.trimmingCharacters(in: .whitespacesAndNewlines)
        .isEmpty
    else {
      return .malformedFreshObservationToken
    }
    guard observation.observedMachAbsoluteTime > 0 else {
      return .malformedObservedMachAbsoluteTime
    }
    guard !usedFreshObservationTokens.contains(observation.freshObservationToken) else {
      return .reusedFreshObservationToken
    }
    if let lastObservedMachAbsoluteTime,
      observation.observedMachAbsoluteTime <= lastObservedMachAbsoluteTime
    {
      return .nonIncreasingObservedMachAbsoluteTime
    }
    return nil
  }

  private mutating func acceptFreshness(
    of observation: ManagedSlideShowInventoryObservation
  ) {
    usedFreshObservationTokens.insert(observation.freshObservationToken)
    lastObservedMachAbsoluteTime = observation.observedMachAbsoluteTime
  }

  private static func isValid(_ target: ManagedSlideShowBindingTarget) -> Bool {
    !target.bindingSessionToken.isEmpty
      && target.processIdentifier > 0
      && !target.bundleIdentifier.isEmpty
  }

  private static func isValid(_ evidence: ManagedSlideShowScriptingEvidence) -> Bool {
    evidence.processIdentifier > 0
      && evidence.activePresentationCount >= 0
      && evidence.slideShowWindowCount >= 0
  }

  private static func validatedInventory(
    _ windows: [ManagedSlideShowWindowIdentity],
    for target: ManagedSlideShowBindingTarget
  ) -> Result<[Int: ManagedSlideShowWindowIdentity], ManagedSlideShowBindingRejection> {
    var inventory: [Int: ManagedSlideShowWindowIdentity] = [:]

    for window in windows {
      guard window.windowID > 0,
        window.processIdentifier > 0,
        !window.bundleIdentifier.isEmpty
      else {
        return .failure(.malformedWindowIdentity)
      }
      guard inventory[window.windowID] == nil else {
        return .failure(.duplicateWindowID)
      }
      guard window.processIdentifier == target.processIdentifier else {
        return .failure(.wrongWindowProcessIdentifier)
      }
      guard window.bundleIdentifier == target.bundleIdentifier else {
        return .failure(.wrongWindowBundleIdentifier)
      }

      inventory[window.windowID] = window
    }

    return .success(inventory)
  }
}
