import Foundation

public enum ManagedSlideShowRoleChallengeMethod: String, Equatable, Sendable {
  case visibility
  case pixelNonce
}

public enum ManagedSlideShowRoleChallengePhase: String, Equatable, Sendable {
  case baseline
  case visibilityHidden
  case visibilityRestored
  case pixelBlack
  case pixelWhite
  case pixelRunningRestored
}

public enum ManagedSlideShowRoleCurrentViewState: String, Equatable, Sendable {
  case running
  case blackScreen
  case whiteScreen
}

/// Runtime-only integral screen geometry reported independently by PowerPoint and ScreenCaptureKit.
public struct ManagedSlideShowWindowGeometry: Equatable, Sendable {
  public let left: Int
  public let top: Int
  public let width: Int
  public let height: Int

  public init(left: Int, top: Int, width: Int, height: Int) {
    self.left = left
    self.top = top
    self.width = width
    self.height = height
  }
}

public struct ManagedSlideShowRoleSemanticState: Equatable, Sendable {
  public let slideID: Int
  public let slideIndex: Int
  public let currentViewState: ManagedSlideShowRoleCurrentViewState
  public let presentationSaved: Bool
  public let windowGeometry: ManagedSlideShowWindowGeometry?

  public init(
    slideID: Int,
    slideIndex: Int,
    currentViewState: ManagedSlideShowRoleCurrentViewState,
    presentationSaved: Bool,
    windowGeometry: ManagedSlideShowWindowGeometry? = nil
  ) {
    self.slideID = slideID
    self.slideIndex = slideIndex
    self.currentViewState = currentViewState
    self.presentationSaved = presentationSaved
    self.windowGeometry = windowGeometry
  }
}

/// Bounded delivery-status evidence supplied by the same capture-stream adapter.
///
/// `complete` and `started` ScreenCaptureKit deliveries are normalized to `generated`. The
/// unavailable cases remain representable as raw injected evidence so both the client boundary
/// and this platform-neutral policy can reject them rather than silently treating them as frames.
public enum ManagedSlideShowRoleWindowDeliveryStatus: String, Equatable, Sendable {
  case generated
  case idle
  case blank
  case suspended
  case stopped
}

/// Runtime-only provenance for one window delivery in a complete challenge inventory.
///
/// Fields are optional because this is raw boundary evidence. A pixel-bearing record must provide
/// every field, nonempty stream-member and continuity tokens, and positive sequence/timestamp
/// values. Only a genuinely off-screen record may omit the entire provenance value.
public struct ManagedSlideShowRoleWindowDeliveryProvenance: Equatable, Sendable {
  public let status: ManagedSlideShowRoleWindowDeliveryStatus?
  public let captureOperationID: UInt64?
  public let captureGeneration: UInt64?
  public let streamMemberToken: String?
  public let continuityToken: String?
  public let deliverySequence: UInt64?
  public let callbackMachAbsoluteTime: UInt64?

  public init(
    status: ManagedSlideShowRoleWindowDeliveryStatus?,
    captureOperationID: UInt64?,
    captureGeneration: UInt64?,
    streamMemberToken: String?,
    continuityToken: String?,
    deliverySequence: UInt64?,
    callbackMachAbsoluteTime: UInt64?
  ) {
    self.status = status
    self.captureOperationID = captureOperationID
    self.captureGeneration = captureGeneration
    self.streamMemberToken = streamMemberToken
    self.continuityToken = continuityToken
    self.deliverySequence = deliverySequence
    self.callbackMachAbsoluteTime = callbackMachAbsoluteTime
  }
}

public struct ManagedSlideShowRoleWindowEvidence: Equatable, Sendable {
  public let identity: ManagedSlideShowWindowIdentity
  /// Present with `displayTime` for captured pixels; both may be absent for an off-screen record.
  public let fingerprint: FrameFingerprint?
  public let isOnScreen: Bool
  /// The ScreenCaptureKit display time for `fingerprint`, never a local or other-window substitute.
  public let displayTime: UInt64?
  /// Same-stream delivery provenance. Only an off-screen record may omit this value.
  public let deliveryProvenance: ManagedSlideShowRoleWindowDeliveryProvenance?
  /// Exact retained `SCWindow` snapshot geometry. Nil preserves the legacy strict role policy.
  public let windowGeometry: ManagedSlideShowWindowGeometry?

  public init(
    identity: ManagedSlideShowWindowIdentity,
    fingerprint: FrameFingerprint?,
    isOnScreen: Bool,
    displayTime: UInt64?,
    deliveryProvenance: ManagedSlideShowRoleWindowDeliveryProvenance?,
    windowGeometry: ManagedSlideShowWindowGeometry? = nil
  ) {
    self.identity = identity
    self.fingerprint = fingerprint
    self.isOnScreen = isOnScreen
    self.displayTime = displayTime
    self.deliveryProvenance = deliveryProvenance
    self.windowGeometry = windowGeometry
  }
}

public struct ManagedSlideShowRoleChallengeTarget: Equatable, Sendable {
  public let bindingSessionToken: String
  public let slideShowObjectToken: String
  public let processIdentifier: Int
  public let bundleIdentifier: String
  public let candidateWindowIdentity: ManagedSlideShowWindowIdentity
  public let captureOperationID: UInt64
  public let captureGeneration: UInt64
  /// Capture-actor-minted anchor for the candidate stream member owned before the challenge.
  public let candidateStreamMemberToken: String
  /// Capture-actor-minted continuity lineage owned before the challenge.
  public let candidateContinuityToken: String
  /// Last candidate delivery sequence accepted before the challenge began.
  public let minimumCandidateDeliverySequenceExclusive: UInt64
  public let challengeNonce: UInt64

  public init(
    bindingSessionToken: String,
    slideShowObjectToken: String,
    processIdentifier: Int,
    bundleIdentifier: String,
    candidateWindowIdentity: ManagedSlideShowWindowIdentity,
    captureOperationID: UInt64,
    captureGeneration: UInt64,
    candidateStreamMemberToken: String,
    candidateContinuityToken: String,
    minimumCandidateDeliverySequenceExclusive: UInt64,
    challengeNonce: UInt64
  ) {
    self.bindingSessionToken = bindingSessionToken
    self.slideShowObjectToken = slideShowObjectToken
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.candidateWindowIdentity = candidateWindowIdentity
    self.captureOperationID = captureOperationID
    self.captureGeneration = captureGeneration
    self.candidateStreamMemberToken = candidateStreamMemberToken
    self.candidateContinuityToken = candidateContinuityToken
    self.minimumCandidateDeliverySequenceExclusive =
      minimumCandidateDeliverySequenceExclusive
    self.challengeNonce = challengeNonce
  }
}

public struct ManagedSlideShowRoleChallengeConfiguration: Equatable, Sendable {
  public let blackLuminanceCeiling: UInt8
  public let whiteLuminanceFloor: UInt8
  public let minimumCoverage: Double

  public init(
    blackLuminanceCeiling: UInt8 = 20,
    whiteLuminanceFloor: UInt8 = 235,
    minimumCoverage: Double = 0.98
  ) {
    self.blackLuminanceCeiling = min(blackLuminanceCeiling, 127)
    self.whiteLuminanceFloor = max(whiteLuminanceFloor, 128)
    if minimumCoverage.isNaN {
      self.minimumCoverage = 1
    } else {
      self.minimumCoverage = min(max(minimumCoverage, 0.5), 1)
    }
  }
}

/// Raw runtime evidence for one post-command ScreenCaptureKit observation.
///
/// These values intentionally do not conform to `Codable`. A live adapter must obtain them from
/// the same capture operation and generation; this policy performs no Apple Event or capture work.
public struct ManagedSlideShowRoleChallengeObservation: Equatable, Sendable {
  public let bindingSessionToken: String
  public let slideShowObjectToken: String
  public let processIdentifier: Int
  public let bundleIdentifier: String
  public let candidateWindowIdentity: ManagedSlideShowWindowIdentity
  public let captureOperationID: UInt64
  public let captureGeneration: UInt64
  public let phase: ManagedSlideShowRoleChallengePhase
  public let nonce: UInt64
  public let commandReplyMachAbsoluteTime: UInt64
  /// Local observation time for the complete inventory, separate from any captured frame time.
  public let evidenceObservedMachAbsoluteTime: UInt64
  /// Exact candidate-frame display time, or nil when hidden evidence contains no candidate frame.
  public let candidateDisplayTime: UInt64?
  public let inventoryIsComplete: Bool
  public let semanticState: ManagedSlideShowRoleSemanticState
  public let windows: [ManagedSlideShowRoleWindowEvidence]

  public init(
    bindingSessionToken: String,
    slideShowObjectToken: String,
    processIdentifier: Int,
    bundleIdentifier: String,
    candidateWindowIdentity: ManagedSlideShowWindowIdentity,
    captureOperationID: UInt64,
    captureGeneration: UInt64,
    phase: ManagedSlideShowRoleChallengePhase,
    nonce: UInt64,
    commandReplyMachAbsoluteTime: UInt64,
    evidenceObservedMachAbsoluteTime: UInt64,
    candidateDisplayTime: UInt64?,
    inventoryIsComplete: Bool,
    semanticState: ManagedSlideShowRoleSemanticState,
    windows: [ManagedSlideShowRoleWindowEvidence]
  ) {
    self.bindingSessionToken = bindingSessionToken
    self.slideShowObjectToken = slideShowObjectToken
    self.processIdentifier = processIdentifier
    self.bundleIdentifier = bundleIdentifier
    self.candidateWindowIdentity = candidateWindowIdentity
    self.captureOperationID = captureOperationID
    self.captureGeneration = captureGeneration
    self.phase = phase
    self.nonce = nonce
    self.commandReplyMachAbsoluteTime = commandReplyMachAbsoluteTime
    self.evidenceObservedMachAbsoluteTime = evidenceObservedMachAbsoluteTime
    self.candidateDisplayTime = candidateDisplayTime
    self.inventoryIsComplete = inventoryIsComplete
    self.semanticState = semanticState
    self.windows = windows
  }
}

public enum ManagedSlideShowRoleChallengeRejection: String, Error, Equatable, Sendable {
  case notStarted
  case startRequiresReset
  case malformedTarget
  case malformedEvidence
  case sessionMismatch
  case objectTokenMismatch
  case processIdentifierMismatch
  case bundleIdentifierMismatch
  case candidateIdentityMismatch
  case captureOperationMismatch
  case captureGenerationMismatch
  case staleEvidenceObservationTime
  case evidenceObservationTimeNotIncreasing
  case missingCandidateDisplayTime
  case unexpectedCandidateDisplayTime
  case staleCandidateDisplayTime
  case candidateDisplayTimeNotIncreasing
  case windowEvidenceStale
  case windowDisplayTimeNotIncreasing
  case windowDeliveryProvenanceMalformed
  case unsupportedWindowDeliveryStatus
  case windowStreamMemberMismatch
  case windowContinuityMismatch
  case windowDeliverySequenceNotIncreasing
  case windowCallbackTimeStale
  case windowCallbackTimeNotIncreasing
  case windowCallbackTimeOutOfBounds
  case idleWindowPayloadChanged
  case candidateMutationRequiresGeneratedPayload
  case incompleteInventory
  case commandReplyTimeNotIncreasing
  case nonceOutOfOrder
  case phaseOutOfOrder
  case inventoryMalformed
  case inventoryChanged
  case windowGeometryMalformed
  case candidateGeometryMismatch
  case windowGeometryChanged
  case otherWindowChanged
  case phaseEvidenceNotRepeatStable
  case semanticStateChanged
  case candidateDidNotRespond
  case wrongVisualSignature
  case restorationFailed
  case tooManyObservations
  case incompleteChallenge
}

public enum ManagedSlideShowRoleChallengeEvent: Equatable, Sendable {
  case started
  case observationAccepted
  case phaseAccepted(ManagedSlideShowRoleChallengePhase)
  case succeeded(freshnessBoundaryMachAbsoluteTime: UInt64)
  case rejected(ManagedSlideShowRoleChallengeRejection)
}

/// Deterministically validates an injected visibility or pixel-nonce role challenge.
///
/// Success proves only that the supplied raw evidence satisfies this contract. Live PowerPoint
/// scripting, exact-window capture, restoration, and generalized behavior remain separate gates.
public struct ManagedSlideShowRoleChallengePolicy: Equatable, Sendable {
  private let configuration: ManagedSlideShowRoleChallengeConfiguration
  private var target: ManagedSlideShowRoleChallengeTarget?
  private var method: ManagedSlideShowRoleChallengeMethod?
  private var observations: [ManagedSlideShowRoleChallengeObservation] = []
  private var baselineInventory: [Int: ManagedSlideShowRoleWindowEvidence] = [:]
  private var initialSemanticState: ManagedSlideShowRoleSemanticState?
  private var usesGeometryDisambiguation = false
  private var latchedRejection: ManagedSlideShowRoleChallengeRejection?
  private var completed = false

  public init(configuration: ManagedSlideShowRoleChallengeConfiguration = .init()) {
    self.configuration = configuration
  }

  @discardableResult
  public mutating func begin(
    target: ManagedSlideShowRoleChallengeTarget,
    method: ManagedSlideShowRoleChallengeMethod
  ) -> ManagedSlideShowRoleChallengeEvent {
    guard self.target == nil, latchedRejection == nil, !completed else {
      return reject(.startRequiresReset)
    }
    guard Self.isValid(target) else { return reject(.malformedTarget) }
    self.target = target
    self.method = method
    return .started
  }

  @discardableResult
  public mutating func ingest(
    _ observation: ManagedSlideShowRoleChallengeObservation
  ) -> ManagedSlideShowRoleChallengeEvent {
    if let latchedRejection { return .rejected(latchedRejection) }
    guard let target, let method else { return .rejected(.notStarted) }
    let phases = Self.phases(for: method, challengeNonce: target.challengeNonce)
    guard observations.count < phases.count * 2 else { return reject(.tooManyObservations) }
    guard Self.isStructurallyValid(observation) else { return reject(.malformedEvidence) }
    guard observation.bindingSessionToken == target.bindingSessionToken else {
      return reject(.sessionMismatch)
    }
    guard observation.slideShowObjectToken == target.slideShowObjectToken else {
      return reject(.objectTokenMismatch)
    }
    guard observation.processIdentifier == target.processIdentifier else {
      return reject(.processIdentifierMismatch)
    }
    guard observation.bundleIdentifier == target.bundleIdentifier else {
      return reject(.bundleIdentifierMismatch)
    }
    guard observation.candidateWindowIdentity == target.candidateWindowIdentity else {
      return reject(.candidateIdentityMismatch)
    }
    guard observation.captureOperationID == target.captureOperationID else {
      return reject(.captureOperationMismatch)
    }
    guard observation.captureGeneration == target.captureGeneration else {
      return reject(.captureGenerationMismatch)
    }
    guard
      observation.evidenceObservedMachAbsoluteTime > observation.commandReplyMachAbsoluteTime
    else {
      return reject(.staleEvidenceObservationTime)
    }
    if let previous = observations.last,
      observation.evidenceObservedMachAbsoluteTime
        <= previous.evidenceObservedMachAbsoluteTime
    {
      return reject(.evidenceObservationTimeNotIncreasing)
    }

    let phaseIndex = observations.count / 2
    let expectedPhase = phases[phaseIndex]
    guard observation.phase == expectedPhase else { return reject(.phaseOutOfOrder) }
    let (expectedNonce, overflow) = target.challengeNonce.addingReportingOverflow(
      UInt64(phaseIndex)
    )
    guard !overflow, observation.nonce == expectedNonce else {
      return reject(.nonceOutOfOrder)
    }
    if observations.count.isMultiple(of: 2), let previous = observations.last,
      observation.commandReplyMachAbsoluteTime <= previous.commandReplyMachAbsoluteTime
    {
      return reject(.commandReplyTimeNotIncreasing)
    }

    guard observation.inventoryIsComplete else { return reject(.incompleteInventory) }
    let candidateMayBeAbsent = method == .visibility && observation.phase == .visibilityHidden
    guard
      let inventory = Self.validatedInventory(
        observation.windows,
        target: target,
        candidateMayBeAbsent: candidateMayBeAbsent
      )
    else {
      return reject(.inventoryMalformed)
    }
    guard
      validateFreshness(
        observation,
        inventory: inventory,
        candidateMayBeAbsent: candidateMayBeAbsent
      )
    else {
      return .rejected(latchedRejection ?? .windowEvidenceStale)
    }
    if observations.isEmpty {
      baselineInventory = inventory
      initialSemanticState = observation.semanticState
      guard configureGeometryDisambiguation(observation, inventory: inventory) else {
        return .rejected(latchedRejection ?? .windowGeometryMalformed)
      }
      guard
        Self.validInitialState(
          observation,
          candidate: inventory[target.candidateWindowIdentity.windowID]
        )
      else {
        return reject(.wrongVisualSignature)
      }
    } else {
      let expectedKeys =
        candidateMayBeAbsent
        ? Set(baselineInventory.keys).subtracting([target.candidateWindowIdentity.windowID])
        : Set(baselineInventory.keys)
      let retainedCandidateKeys = Set(baselineInventory.keys)
      guard
        Set(inventory.keys) == expectedKeys
          || (candidateMayBeAbsent && Set(inventory.keys) == retainedCandidateKeys)
      else { return reject(.inventoryChanged) }
      guard validateStableGeometry(observation, inventory: inventory) else {
        return .rejected(latchedRejection ?? .windowGeometryChanged)
      }
      if usesGeometryDisambiguation, method == .pixelNonce {
        guard validateGeometryDisambiguatedAuxiliaries(observation, inventory: inventory) else {
          return .rejected(latchedRejection ?? .otherWindowChanged)
        }
      } else {
        for (windowID, baseline) in baselineInventory
        where windowID != target.candidateWindowIdentity.windowID {
          guard inventory[windowID].map({ Self.sameVisualEvidence($0, baseline) }) == true else {
            return reject(.otherWindowChanged)
          }
        }
      }
    }

    if observations.count.isMultiple(of: 2) == false, let first = observations.last {
      guard Self.repeatEquivalent(first, observation) else {
        return reject(.phaseEvidenceNotRepeatStable)
      }
    }

    guard
      validatePhase(
        observation,
        candidate: inventory[target.candidateWindowIdentity.windowID],
        method: method
      )
    else {
      return .rejected(latchedRejection ?? .candidateDidNotRespond)
    }

    observations.append(observation)
    return observations.count.isMultiple(of: 2)
      ? .phaseAccepted(expectedPhase)
      : .observationAccepted
  }

  private mutating func configureGeometryDisambiguation(
    _ observation: ManagedSlideShowRoleChallengeObservation,
    inventory: [Int: ManagedSlideShowRoleWindowEvidence]
  ) -> Bool {
    let objectGeometry = observation.semanticState.windowGeometry
    let windowGeometries = inventory.values.map(\.windowGeometry)
    if objectGeometry == nil, windowGeometries.allSatisfy({ $0 == nil }) {
      usesGeometryDisambiguation = false
      return true
    }
    guard let objectGeometry, Self.isValid(objectGeometry),
      windowGeometries.allSatisfy({ $0.map(Self.isValid) == true })
    else { return fail(.windowGeometryMalformed) }
    let matches = inventory.values.filter { $0.windowGeometry == objectGeometry }
    guard matches.count == 1,
      matches.first?.identity == observation.candidateWindowIdentity
    else { return fail(.candidateGeometryMismatch) }
    usesGeometryDisambiguation = true
    return true
  }

  private mutating func validateStableGeometry(
    _ observation: ManagedSlideShowRoleChallengeObservation,
    inventory: [Int: ManagedSlideShowRoleWindowEvidence]
  ) -> Bool {
    guard usesGeometryDisambiguation else {
      guard observation.semanticState.windowGeometry == nil,
        inventory.values.allSatisfy({ $0.windowGeometry == nil })
      else { return fail(.windowGeometryChanged) }
      return true
    }
    guard observation.semanticState.windowGeometry == initialSemanticState?.windowGeometry else {
      return fail(.windowGeometryChanged)
    }
    for (windowID, baseline) in baselineInventory {
      guard inventory[windowID]?.windowGeometry == baseline.windowGeometry else {
        return fail(.windowGeometryChanged)
      }
    }
    return true
  }

  private mutating func validateGeometryDisambiguatedAuxiliaries(
    _ observation: ManagedSlideShowRoleChallengeObservation,
    inventory: [Int: ManagedSlideShowRoleWindowEvidence]
  ) -> Bool {
    guard let target else { return fail(.inventoryMalformed) }
    let otherWindowIDs = baselineInventory.keys.filter {
      $0 != target.candidateWindowIdentity.windowID
    }
    switch observation.phase {
    case .baseline, .pixelRunningRestored:
      for windowID in otherWindowIDs {
        guard let current = inventory[windowID], let baseline = baselineInventory[windowID],
          Self.sameVisualEvidence(current, baseline)
        else {
          return fail(observation.phase == .baseline ? .otherWindowChanged : .restorationFailed)
        }
      }
      return true
    case .pixelBlack, .pixelWhite:
      for windowID in otherWindowIDs {
        guard let current = inventory[windowID], let baseline = baselineInventory[windowID],
          let fingerprint = current.fingerprint,
          current.isOnScreen,
          fingerprint.isValid,
          fingerprint.sampleColumns == baseline.fingerprint?.sampleColumns,
          fingerprint.sampleRows == baseline.fingerprint?.sampleRows
        else { return fail(.otherWindowChanged) }
      }
      let phaseEvidence = observations + [observation]
      guard phaseEvidence.contains(where: { $0.phase == .pixelBlack }),
        phaseEvidence.contains(where: { $0.phase == .pixelWhite })
      else { return true }
      for windowID in otherWindowIDs {
        guard let baseline = baselineInventory[windowID] else {
          return fail(.inventoryMalformed)
        }
        let black = phaseEvidence.last(where: { $0.phase == .pixelBlack })?.windows.first {
          $0.identity.windowID == windowID
        }
        let white = phaseEvidence.last(where: { $0.phase == .pixelWhite })?.windows.first {
          $0.identity.windowID == windowID
        }
        let changed =
          black.map({ !Self.sameVisualEvidence($0, baseline) }) == true
          || white.map({ !Self.sameVisualEvidence($0, baseline) }) == true
        if changed {
          guard let blackFingerprint = black?.fingerprint,
            let whiteFingerprint = white?.fingerprint,
            black?.isOnScreen == true,
            white?.isOnScreen == true,
            hasGeometryBoundPairedCausalSignature(
              black: blackFingerprint,
              white: whiteFingerprint
            )
          else { return fail(.otherWindowChanged) }
        }
      }
      return true
    case .visibilityHidden, .visibilityRestored:
      return fail(.phaseOutOfOrder)
    }
  }

  @discardableResult
  public mutating func finish() -> ManagedSlideShowRoleChallengeEvent {
    if let latchedRejection { return .rejected(latchedRejection) }
    guard let method else { return .rejected(.notStarted) }
    guard let target,
      observations.count == Self.phases(for: method, challengeNonce: target.challengeNonce).count
        * 2,
      let last = observations.last
    else {
      return reject(.incompleteChallenge)
    }
    completed = true
    let latestWindowDisplayTime = last.windows.compactMap(\.displayTime).max() ?? 0
    return .succeeded(
      freshnessBoundaryMachAbsoluteTime: max(
        max(last.evidenceObservedMachAbsoluteTime, last.candidateDisplayTime ?? 0),
        latestWindowDisplayTime
      )
    )
  }

  public mutating func reset() {
    self = Self(configuration: configuration)
  }

  private mutating func validatePhase(
    _ observation: ManagedSlideShowRoleChallengeObservation,
    candidate: ManagedSlideShowRoleWindowEvidence?,
    method: ManagedSlideShowRoleChallengeMethod
  ) -> Bool {
    guard let target, let baseline = baselineInventory[target.candidateWindowIdentity.windowID],
      let initialSemanticState
    else { return fail(.inventoryMalformed) }
    if let candidate, let candidateFingerprint = candidate.fingerprint,
      let baselineFingerprint = baseline.fingerprint
    {
      guard candidateFingerprint.sampleColumns == baselineFingerprint.sampleColumns,
        candidateFingerprint.sampleRows == baselineFingerprint.sampleRows
      else { return fail(.inventoryMalformed) }
    }
    let sameSlide =
      observation.semanticState.slideID == initialSemanticState.slideID
      && observation.semanticState.slideIndex == initialSemanticState.slideIndex
      && observation.semanticState.presentationSaved == initialSemanticState.presentationSaved
    guard sameSlide else { return fail(.semanticStateChanged) }

    switch (method, observation.phase) {
    case (.visibility, .baseline):
      return true
    case (.visibility, .visibilityHidden):
      guard candidate == nil || candidate?.isOnScreen == false,
        observation.semanticState == initialSemanticState
      else {
        return fail(.candidateDidNotRespond)
      }
    case (.visibility, .visibilityRestored):
      guard candidate.map({ Self.sameVisualEvidence($0, baseline) }) == true,
        observation.semanticState == initialSemanticState
      else {
        return fail(.restorationFailed)
      }
    case (.pixelNonce, .baseline):
      return true
    case (.pixelNonce, .pixelBlack):
      guard let candidate, let fingerprint = candidate.fingerprint, candidate.isOnScreen,
        validatePixelTone(fingerprint, as: .black, candidateIdentity: candidate.identity),
        observation.semanticState.currentViewState == .blackScreen
      else {
        return fail(.wrongVisualSignature)
      }
    case (.pixelNonce, .pixelWhite):
      guard let candidate, let fingerprint = candidate.fingerprint else {
        return fail(.inventoryMalformed)
      }
      guard candidate.isOnScreen,
        validatePixelTone(fingerprint, as: .white, candidateIdentity: candidate.identity),
        observation.semanticState.currentViewState == .whiteScreen
      else {
        return fail(.wrongVisualSignature)
      }
    case (.pixelNonce, .pixelRunningRestored):
      guard candidate.map({ Self.sameVisualEvidence($0, baseline) }) == true,
        observation.semanticState == initialSemanticState
      else {
        return fail(.restorationFailed)
      }
    default:
      return fail(.phaseOutOfOrder)
    }
    if method == .pixelNonce,
      observation.phase
        == Self.phases(
          for: .pixelNonce,
          challengeNonce: target.challengeNonce
        )[2]
    {
      let challengeFingerprints =
        observations.compactMap { prior -> FrameFingerprint? in
          guard prior.phase == .pixelBlack || prior.phase == .pixelWhite else { return nil }
          return prior.windows.first { $0.identity == target.candidateWindowIdentity }?.fingerprint
        } + (candidate?.fingerprint.map { [$0] } ?? [])
      guard Set(challengeFingerprints.map(\.luminance)).count >= 2,
        challengeFingerprints.contains(where: { $0 != baseline.fingerprint })
      else { return fail(.candidateDidNotRespond) }
    }
    return true
  }

  private mutating func fail(_ rejection: ManagedSlideShowRoleChallengeRejection) -> Bool {
    _ = reject(rejection)
    return false
  }

  private mutating func validateFreshness(
    _ observation: ManagedSlideShowRoleChallengeObservation,
    inventory: [Int: ManagedSlideShowRoleWindowEvidence],
    candidateMayBeAbsent: Bool
  ) -> Bool {
    guard let target else { return fail(.notStarted) }
    let candidate = inventory[target.candidateWindowIdentity.windowID]
    if candidate == nil {
      guard candidateMayBeAbsent, observation.candidateDisplayTime == nil else {
        return fail(.unexpectedCandidateDisplayTime)
      }
    } else {
      guard observation.candidateDisplayTime == candidate?.displayTime else {
        return fail(
          observation.candidateDisplayTime == nil
            ? .missingCandidateDisplayTime
            : .unexpectedCandidateDisplayTime
        )
      }
      if observation.candidateDisplayTime == nil {
        guard candidate?.isOnScreen == false else { return fail(.missingCandidateDisplayTime) }
      }
    }

    let isFirstObservationInPhase = observations.count.isMultiple(of: 2)
    var seenStreamMemberTokens: Set<String> = []
    for window in observation.windows {
      switch (window.fingerprint, window.displayTime, window.isOnScreen) {
      case (.some(let fingerprint), .some(let displayTime), true):
        guard fingerprint.isValid else { return fail(.inventoryMalformed) }
        guard
          let provenance = window.deliveryProvenance,
          let status = provenance.status,
          let captureOperationID = provenance.captureOperationID,
          let captureGeneration = provenance.captureGeneration,
          let streamMemberToken = provenance.streamMemberToken,
          let continuityToken = provenance.continuityToken,
          let deliverySequence = provenance.deliverySequence,
          let callbackMachAbsoluteTime = provenance.callbackMachAbsoluteTime,
          captureOperationID == observation.captureOperationID,
          captureGeneration == observation.captureGeneration,
          streamMemberToken == streamMemberToken.trimmingCharacters(in: .whitespacesAndNewlines),
          !streamMemberToken.isEmpty,
          continuityToken == continuityToken.trimmingCharacters(in: .whitespacesAndNewlines),
          !continuityToken.isEmpty,
          deliverySequence > 0,
          callbackMachAbsoluteTime > 0,
          displayTime > 0,
          displayTime <= callbackMachAbsoluteTime,
          seenStreamMemberTokens.insert(streamMemberToken).inserted
        else {
          return fail(.windowDeliveryProvenanceMalformed)
        }
        guard status == .generated || status == .idle else {
          return fail(.unsupportedWindowDeliveryStatus)
        }
        guard callbackMachAbsoluteTime > observation.commandReplyMachAbsoluteTime else {
          return fail(.windowCallbackTimeStale)
        }
        guard callbackMachAbsoluteTime <= observation.evidenceObservedMachAbsoluteTime else {
          return fail(.windowCallbackTimeOutOfBounds)
        }

        let previous = observations.reversed().lazy.compactMap { prior in
          prior.windows.first {
            $0.identity == window.identity && $0.fingerprint != nil
          }
        }.first
        if let previous {
          guard
            previous.deliveryProvenance?.streamMemberToken == streamMemberToken
          else { return fail(.windowStreamMemberMismatch) }
          guard previous.deliveryProvenance?.continuityToken == continuityToken else {
            return fail(.windowContinuityMismatch)
          }
          guard
            let previousSequence = previous.deliveryProvenance?.deliverySequence,
            deliverySequence > previousSequence
          else { return fail(.windowDeliverySequenceNotIncreasing) }
          guard
            let previousCallback = previous.deliveryProvenance?.callbackMachAbsoluteTime,
            callbackMachAbsoluteTime > previousCallback
          else { return fail(.windowCallbackTimeNotIncreasing) }
        } else {
          // Apple does not promise a periodic idle callback. A baseline deadline can therefore
          // expire even when the screen is unchanged; that outcome remains fail closed. If a
          // callback does arrive, only a baseline observation may establish its first local latch.
          guard observation.phase == .baseline else {
            return fail(.windowContinuityMismatch)
          }
        }

        let isCandidate = window.identity == target.candidateWindowIdentity
        if isCandidate {
          guard streamMemberToken == target.candidateStreamMemberToken else {
            return fail(.windowStreamMemberMismatch)
          }
          guard continuityToken == target.candidateContinuityToken else {
            return fail(.windowContinuityMismatch)
          }
          guard deliverySequence > target.minimumCandidateDeliverySequenceExclusive else {
            return fail(.windowDeliverySequenceNotIncreasing)
          }
          if isFirstObservationInPhase, observation.phase != .baseline, status != .generated {
            return fail(.candidateMutationRequiresGeneratedPayload)
          }
        }

        switch status {
        case .generated:
          guard displayTime > observation.commandReplyMachAbsoluteTime else {
            return fail(isCandidate ? .staleCandidateDisplayTime : .windowEvidenceStale)
          }
          if let previousDisplayTime = previous?.displayTime,
            displayTime <= previousDisplayTime
          {
            return fail(
              isCandidate
                ? .candidateDisplayTimeNotIncreasing
                : .windowDisplayTimeNotIncreasing
            )
          }
        case .idle:
          if let previous {
            guard previous.fingerprint == fingerprint,
              previous.displayTime == displayTime,
              previous.isOnScreen == window.isOnScreen
            else { return fail(.idleWindowPayloadChanged) }
          }
        case .blank, .suspended, .stopped:
          return fail(.unsupportedWindowDeliveryStatus)
        }
      case (.none, .none, false):
        guard window.deliveryProvenance == nil else {
          return fail(.windowDeliveryProvenanceMalformed)
        }
        break
      default:
        return fail(.inventoryMalformed)
      }
    }
    return true
  }

  private mutating func reject(
    _ rejection: ManagedSlideShowRoleChallengeRejection
  ) -> ManagedSlideShowRoleChallengeEvent {
    if let latchedRejection { return .rejected(latchedRejection) }
    latchedRejection = rejection
    return .rejected(rejection)
  }

  private static func phases(
    for method: ManagedSlideShowRoleChallengeMethod,
    challengeNonce: UInt64
  ) -> [ManagedSlideShowRoleChallengePhase] {
    switch method {
    case .visibility: [.baseline, .visibilityHidden, .visibilityRestored]
    case .pixelNonce:
      challengeNonce.isMultiple(of: 2)
        ? [.baseline, .pixelBlack, .pixelWhite, .pixelRunningRestored]
        : [.baseline, .pixelWhite, .pixelBlack, .pixelRunningRestored]
    }
  }

  private static func isValid(_ target: ManagedSlideShowRoleChallengeTarget) -> Bool {
    !target.bindingSessionToken.isEmpty && !target.slideShowObjectToken.isEmpty
      && target.processIdentifier > 0 && !target.bundleIdentifier.isEmpty
      && target.captureOperationID > 0 && target.captureGeneration > 0
      && target.candidateStreamMemberToken
        == target.candidateStreamMemberToken.trimmingCharacters(in: .whitespacesAndNewlines)
      && !target.candidateStreamMemberToken.isEmpty
      && target.candidateContinuityToken
        == target.candidateContinuityToken.trimmingCharacters(in: .whitespacesAndNewlines)
      && !target.candidateContinuityToken.isEmpty
      && target.minimumCandidateDeliverySequenceExclusive > 0
      && target.minimumCandidateDeliverySequenceExclusive < UInt64.max
      && target.challengeNonce > 0 && target.challengeNonce <= UInt64.max - 3
      && target.candidateWindowIdentity.windowID > 0
      && target.candidateWindowIdentity.processIdentifier == target.processIdentifier
      && target.candidateWindowIdentity.bundleIdentifier == target.bundleIdentifier
  }

  private static func isStructurallyValid(
    _ observation: ManagedSlideShowRoleChallengeObservation
  ) -> Bool {
    !observation.bindingSessionToken.isEmpty && !observation.slideShowObjectToken.isEmpty
      && observation.processIdentifier > 0 && !observation.bundleIdentifier.isEmpty
      && observation.captureOperationID > 0 && observation.captureGeneration > 0
      && observation.commandReplyMachAbsoluteTime > 0
      && observation.evidenceObservedMachAbsoluteTime > 0
      && observation.candidateDisplayTime != 0 && observation.semanticState.slideID > 0
      && observation.semanticState.slideIndex > 0
  }

  private static func isValid(_ geometry: ManagedSlideShowWindowGeometry) -> Bool {
    guard geometry.width > 0, geometry.height > 0 else { return false }
    let (_, horizontalOverflow) = geometry.left.addingReportingOverflow(geometry.width)
    let (_, verticalOverflow) = geometry.top.addingReportingOverflow(geometry.height)
    return !horizontalOverflow && !verticalOverflow
  }

  private static func validatedInventory(
    _ windows: [ManagedSlideShowRoleWindowEvidence],
    target: ManagedSlideShowRoleChallengeTarget,
    candidateMayBeAbsent: Bool
  ) -> [Int: ManagedSlideShowRoleWindowEvidence]? {
    var inventory: [Int: ManagedSlideShowRoleWindowEvidence] = [:]
    for window in windows {
      let identity = window.identity
      guard identity.windowID > 0, identity.processIdentifier == target.processIdentifier,
        identity.bundleIdentifier == target.bundleIdentifier,
        inventory[identity.windowID] == nil
      else { return nil }
      inventory[identity.windowID] = window
    }
    if let candidate = inventory[target.candidateWindowIdentity.windowID] {
      guard candidate.identity == target.candidateWindowIdentity else { return nil }
    } else if !candidateMayBeAbsent {
      return nil
    }
    return inventory
  }

  private static func validInitialState(
    _ observation: ManagedSlideShowRoleChallengeObservation,
    candidate: ManagedSlideShowRoleWindowEvidence?
  ) -> Bool {
    guard let candidate, candidate.isOnScreen,
      candidate.fingerprint?.isValid == true,
      observation.semanticState.currentViewState == .running
    else { return false }
    return true
  }

  private enum PixelTone {
    case black
    case white
  }

  private func classifies(_ fingerprint: FrameFingerprint, as tone: PixelTone) -> Bool {
    guard fingerprint.isValid else { return false }
    let matchingCount = fingerprint.luminance.reduce(into: 0) { count, luminance in
      switch tone {
      case .black where luminance <= configuration.blackLuminanceCeiling:
        count += 1
      case .white where luminance >= configuration.whiteLuminanceFloor:
        count += 1
      default:
        break
      }
    }
    return Double(matchingCount) / Double(fingerprint.luminance.count)
      >= configuration.minimumCoverage
  }

  private func classifiesAtLeastHalf(
    _ fingerprint: FrameFingerprint,
    as tone: PixelTone
  ) -> Bool {
    matchingFraction(fingerprint, as: tone) >= 0.5
  }

  private func matchingFraction(_ fingerprint: FrameFingerprint, as tone: PixelTone) -> Double {
    guard fingerprint.isValid else { return 0 }
    let matchingCount = fingerprint.luminance.reduce(into: 0) { count, luminance in
      switch tone {
      case .black where luminance <= configuration.blackLuminanceCeiling:
        count += 1
      case .white where luminance >= configuration.whiteLuminanceFloor:
        count += 1
      default:
        break
      }
    }
    return Double(matchingCount) / Double(fingerprint.luminance.count)
  }

  private func validatePixelTone(
    _ fingerprint: FrameFingerprint,
    as tone: PixelTone,
    candidateIdentity: ManagedSlideShowWindowIdentity
  ) -> Bool {
    guard usesGeometryDisambiguation else { return classifies(fingerprint, as: tone) }
    let oppositePhase: ManagedSlideShowRoleChallengePhase
    switch tone {
    case .black: oppositePhase = .pixelWhite
    case .white: oppositePhase = .pixelBlack
    }
    guard
      let opposite = observations.last(where: { $0.phase == oppositePhase })?.windows.first(
        where: { $0.identity == candidateIdentity }
      )?.fingerprint
    else { return true }
    switch tone {
    case .black:
      return hasGeometryBoundPairedCausalSignature(black: fingerprint, white: opposite)
    case .white:
      return hasGeometryBoundPairedCausalSignature(black: opposite, white: fingerprint)
    }
  }

  /// Geometry already proves which retained ScreenCaptureKit window belongs to the exact
  /// PowerPoint object. Letterboxing may nevertheless prevent one commanded endpoint from
  /// occupying half of that window. Keep the symmetric endpoint test when both tones are strong;
  /// otherwise require one strong endpoint, a substantial opposite endpoint, and a broad,
  /// overwhelmingly forward response across the exact same sample positions.
  private func hasGeometryBoundPairedCausalSignature(
    black: FrameFingerprint,
    white: FrameFingerprint
  ) -> Bool {
    let blackCoverage = matchingFraction(black, as: .black)
    let whiteCoverage = matchingFraction(white, as: .white)
    guard max(blackCoverage, whiteCoverage) >= 0.5 else { return false }
    if min(blackCoverage, whiteCoverage) >= 0.5 {
      return hasPairedCausalSignature(black: black, white: white)
    }
    guard min(blackCoverage, whiteCoverage) >= 0.25 else { return false }
    return hasPairedDirectionalSignature(black: black, white: white)
  }

  private func hasPairedCausalSignature(
    black: FrameFingerprint,
    white: FrameFingerprint
  ) -> Bool {
    guard black.isValid, white.isValid,
      black.sampleColumns == white.sampleColumns,
      black.sampleRows == white.sampleRows,
      black.luminance.count == white.luminance.count
    else { return false }
    var changedCount = 0
    var matchingChangedCount = 0
    for (blackValue, whiteValue) in zip(black.luminance, white.luminance)
    where blackValue != whiteValue {
      changedCount += 1
      if blackValue <= configuration.blackLuminanceCeiling,
        whiteValue >= configuration.whiteLuminanceFloor
      {
        matchingChangedCount += 1
      }
    }
    guard Double(changedCount) / Double(black.luminance.count) >= 0.5 else { return false }
    return Double(matchingChangedCount) / Double(changedCount) >= configuration.minimumCoverage
  }

  private func hasPairedDirectionalSignature(
    black: FrameFingerprint,
    white: FrameFingerprint
  ) -> Bool {
    guard black.isValid, white.isValid,
      black.sampleColumns == white.sampleColumns,
      black.sampleRows == white.sampleRows,
      black.luminance.count == white.luminance.count
    else { return false }
    var changedCount = 0
    var forwardCount = 0
    for (blackValue, whiteValue) in zip(black.luminance, white.luminance)
    where blackValue != whiteValue {
      changedCount += 1
      if whiteValue > blackValue {
        forwardCount += 1
      }
    }
    guard Double(changedCount) / Double(black.luminance.count) >= 0.5 else { return false }
    return Double(forwardCount) / Double(changedCount) >= configuration.minimumCoverage
  }

  private static func repeatEquivalent(
    _ lhs: ManagedSlideShowRoleChallengeObservation,
    _ rhs: ManagedSlideShowRoleChallengeObservation
  ) -> Bool {
    lhs.bindingSessionToken == rhs.bindingSessionToken
      && lhs.slideShowObjectToken == rhs.slideShowObjectToken
      && lhs.processIdentifier == rhs.processIdentifier
      && lhs.bundleIdentifier == rhs.bundleIdentifier
      && lhs.candidateWindowIdentity == rhs.candidateWindowIdentity
      && lhs.captureOperationID == rhs.captureOperationID
      && lhs.captureGeneration == rhs.captureGeneration
      && lhs.phase == rhs.phase && lhs.nonce == rhs.nonce
      && lhs.commandReplyMachAbsoluteTime == rhs.commandReplyMachAbsoluteTime
      && lhs.inventoryIsComplete == rhs.inventoryIsComplete
      && lhs.semanticState == rhs.semanticState
      && lhs.windows.count == rhs.windows.count
      && lhs.windows.allSatisfy { left in
        rhs.windows.first(where: { $0.identity == left.identity }).map {
          Self.sameVisualEvidence(left, $0)
        } == true
      }
  }

  private static func sameVisualEvidence(
    _ lhs: ManagedSlideShowRoleWindowEvidence,
    _ rhs: ManagedSlideShowRoleWindowEvidence
  ) -> Bool {
    lhs.identity == rhs.identity && lhs.fingerprint == rhs.fingerprint
      && lhs.isOnScreen == rhs.isOnScreen && lhs.windowGeometry == rhs.windowGeometry
  }
}
