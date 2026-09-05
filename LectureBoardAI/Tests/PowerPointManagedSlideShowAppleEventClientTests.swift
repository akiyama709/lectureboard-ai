import ApplicationServices
import Darwin
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

/// Fake-boundary tests only. No test sends an Apple Event, queries Automation permission, scans a
/// real window, or launches PowerPoint.
@MainActor
struct PowerPointManagedSlideShowAppleEventClientTests {
  private let session = "managed-session"
  private let processIdentifier: pid_t = 700
  private let bundleIdentifier = PowerPointWindowIdentity.expectedBundleIdentifier

  @Test func baselineStartAndPostStartInventoryRetainExactReturnedObject() async throws {
    let permission = ScriptedManagedPermissionChecker(states: [.authorized])
    let identity = ScriptedManagedProcessIdentityReader(
      identity: exactProcessIdentity()
    )
    let inventory = ScriptedManagedWindowInventoryReader(
      windows: [managedWindow(100)]
    )
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0
    )
    let clock = ScriptedManagedClientMachClock([20, 40])
    let client = makeClient(
      permission: permission,
      identity: identity,
      inventory: inventory,
      sender: sender,
      clock: clock,
      objectToken: "opaque-object-one"
    )

    let baseline = try await client.readCompositeObservation(
      observationRequest(startedAt: 10, freshToken: "baseline-fresh")
    )
    #expect(baseline.bindingSessionToken == session)
    #expect(baseline.freshObservationToken == "baseline-fresh")
    #expect(baseline.observedMachAbsoluteTime == 20)
    #expect(baseline.scriptingEvidence.activePresentationCount == 1)
    #expect(baseline.scriptingEvidence.slideShowWindowCount == 0)
    #expect(baseline.windows == [managedWindow(100)])

    let receipt = try await client.startManagedSlideShow(startRequest())
    #expect(receipt.bindingSessionToken == session)
    #expect(receipt.processIdentifier == processIdentifier)
    #expect(receipt.bundleIdentifier == bundleIdentifier)
    #expect(receipt.slideShowObjectToken == "opaque-object-one")
    #expect(sender.runSlideShowSendCount == 1)
    #expect(
      sender.lastSendOptionsRawValue
        == PowerPointAppleEventDescriptorCodec.sendOptions.rawValue
    )
    #expect(
      await client.ownsRetainedSlideShowObject(
        bindingSessionToken: session,
        slideShowObjectToken: receipt.slideShowObjectToken
      )
    )

    await inventory.setWindows([managedWindow(100), managedWindow(200)])
    let postStart = try await client.readCompositeObservation(
      observationRequest(startedAt: 30, freshToken: "post-start-fresh")
    )
    #expect(postStart.observedMachAbsoluteTime == 40)
    #expect(postStart.scriptingEvidence.activePresentationCount == 1)
    #expect(postStart.scriptingEvidence.slideShowWindowCount == 1)
    #expect(postStart.windows == [managedWindow(100), managedWindow(200)])
    #expect(Set(sender.targetProcessIdentifiers) == [processIdentifier])
  }

  @Test func managedStartRequiresReadOnlyWindowedShowTypeBeforeSendingRun() async throws {
    for type in [
      PowerPointSlideShowType.speaker.rawValue,
      PowerPointSlideShowType.kiosk.rawValue,
      PowerPointSlideShowType.presenter.rawValue,
    ] {
      let sender = FakeManagedAppleEventSender(showTypeCode: type)
      let client = makeClient(sender: sender)
      await #expect(
        throws: PowerPointManagedSlideShowAppleEventClientFailure.unsupportedSlideShowType
      ) {
        try await client.startManagedSlideShow(self.startRequest())
      }
      #expect(sender.runSlideShowSendCount == 0)
    }

    for unavailable in [nil, OSType(0x00D5_00FF)] {
      let sender = FakeManagedAppleEventSender(showTypeCode: unavailable)
      let client = makeClient(sender: sender)
      await #expect(
        throws: PowerPointManagedSlideShowAppleEventClientFailure.slideShowTypeUnavailable
      ) {
        try await client.startManagedSlideShow(self.startRequest())
      }
      #expect(sender.runSlideShowSendCount == 0)
    }

    let malformedSender = FakeManagedAppleEventSender(showTypeMalformed: true)
    let malformedClient = makeClient(sender: malformedSender)
    await #expect(
      throws: PowerPointManagedSlideShowAppleEventClientFailure.slideShowTypeUnavailable
    ) {
      try await malformedClient.startManagedSlideShow(self.startRequest())
    }
    #expect(malformedSender.runSlideShowSendCount == 0)
  }

  @Test func retainedReturnedObjectDrivesRoleCommandsAndStableSemanticReads() async throws {
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0,
      exactSlideID: 50,
      exactSlideIndex: 3
    )
    let client = makeClient(
      sender: sender,
      clock: ScriptedManagedClientMachClock([100, 110, 120, 130, 140, 150, 200]),
      objectToken: "role-object"
    )
    let receipt = try await client.startManagedSlideShow(startRequest())

    let visibility = try await client.readCapability(
      roleCapabilityRequest(
        receipt: receipt,
        capability: .visibility,
        token: "visibility-capability"
      )
    )
    #expect(visibility.state == .available)
    let pixel = try await client.readCapability(
      roleCapabilityRequest(
        receipt: receipt,
        capability: .pixelNonce,
        token: "pixel-capability"
      )
    )
    #expect(pixel.state == .available)

    _ = try await client.perform(
      roleCommandRequest(
        receipt: receipt,
        phaseNonce: 40,
        command: .establishBaseline,
        token: "baseline-command"
      )
    )
    _ = try await client.perform(
      roleCommandRequest(
        receipt: receipt,
        phaseNonce: 41,
        command: .setVisibility(false),
        token: "hidden-command"
      )
    )
    _ = try await client.perform(
      roleCommandRequest(
        receipt: receipt,
        phaseNonce: 42,
        command: .setVisibility(true),
        token: "visible-command"
      )
    )
    _ = try await client.perform(
      roleCommandRequest(
        receipt: receipt,
        phaseNonce: 41,
        command: .setViewState(.blackScreen),
        token: "black-command"
      )
    )
    _ = try await client.perform(
      roleCommandRequest(
        receipt: receipt,
        phaseNonce: 42,
        command: .setViewState(.whiteScreen),
        token: "white-command"
      )
    )
    _ = try await client.perform(
      roleCommandRequest(
        receipt: receipt,
        phaseNonce: 43,
        command: .setViewState(.running),
        token: "running-command"
      )
    )

    let semanticRequest = roleSemanticRequest(
      receipt: receipt,
      token: "semantic-request",
      startedAt: 175
    )
    let semantic = try await client.readExactRoleSemanticState(semanticRequest)
    #expect(semantic.request == semanticRequest)
    #expect(semantic.acquiredMachAbsoluteTime == 200)
    #expect(semantic.semanticState.slideID == 50)
    #expect(semantic.semanticState.slideIndex == 3)
    #expect(semantic.semanticState.currentViewState == .running)
    #expect(semantic.semanticState.presentationSaved)
    #expect(sender.exactVisibility)
    #expect(sender.exactViewState == .running)
    #expect(sender.exactObjectRootIndices.allSatisfy { $0 == 1 })
    #expect(
      Set(sender.exactObjectLeafCodes).isSuperset(of: [
        PowerPointAppleEventProperty.visible.rawValue,
        PowerPointAppleEventProperty.slideState.rawValue,
        PowerPointAppleEventProperty.slideID.rawValue,
        PowerPointAppleEventProperty.slideIndex.rawValue,
        PowerPointAppleEventProperty.presentationSaved.rawValue,
      ])
    )
    let exactIdentityReader: any ExactPowerPointSlideIdentityReadingClient = client
    _ = exactIdentityReader
  }

  @Test func wrongOrReplayedObjectTokenFailsBeforeAnotherExternalCall() async throws {
    let sender = FakeManagedAppleEventSender()
    let client = makeClient(sender: sender, objectToken: "retained-token")
    let receipt = try await client.startManagedSlideShow(startRequest())
    let callsAfterStart = sender.totalSendCount
    let wrongRequest = PowerPointManagedSlideShowRoleCapabilityRequest(
      bindingSessionToken: receipt.bindingSessionToken,
      slideShowObjectToken: "wrong-token",
      processIdentifier: Int(receipt.processIdentifier),
      bundleIdentifier: receipt.bundleIdentifier,
      challengeNonce: 40,
      capability: .visibility,
      freshRequestToken: "wrong-object-request"
    )

    #expect(
      await capturedFailure { try await client.readCapability(wrongRequest) }
        == .objectTokenMismatch
    )
    #expect(sender.totalSendCount == callsAfterStart)

    let request = roleCapabilityRequest(
      receipt: receipt,
      capability: .visibility,
      token: "one-shot-object-request"
    )
    _ = try await client.readCapability(request)
    let callsAfterAcceptedRequest = sender.totalSendCount
    #expect(
      await capturedFailure { try await client.readCapability(request) }
        == .requestAlreadyConsumed
    )
    #expect(sender.totalSendCount == callsAfterAcceptedRequest)
  }

  @Test func invalidatedSessionCanExitOnlyItsRetainedReturnedObject() async throws {
    let sender = FakeManagedAppleEventSender()
    let client = makeClient(sender: sender, objectToken: "rollback-object")
    let receipt = try await client.startManagedSlideShow(startRequest())
    client.invalidateSession()

    #expect(
      await capturedFailure {
        try await client.readExactRoleSemanticState(
          self.roleSemanticRequest(
            receipt: receipt,
            token: "after-invalidation",
            startedAt: 100
          )
        )
      } == .staleSession
    )
    try await client.exitRetainedSlideShowObject(receipt)

    #expect(sender.exitSlideShowSendCount == 1)
    #expect(sender.exitRootObjectIndices == [1])
    #expect(
      !(await client.ownsRetainedSlideShowObject(
        bindingSessionToken: receipt.bindingSessionToken,
        slideShowObjectToken: receipt.slideShowObjectToken
      ))
    )
  }

  @Test func malformedExactObjectReplyFailsClosedAndRetainsRecoveryOwnership() async throws {
    let sender = FakeManagedAppleEventSender(exactReplyMode: .malformedGet)
    let client = makeClient(sender: sender, objectToken: "malformed-reply-object")
    let receipt = try await client.startManagedSlideShow(startRequest())

    #expect(
      await capturedFailure {
        try await client.readCapability(
          self.roleCapabilityRequest(
            receipt: receipt,
            capability: .visibility,
            token: "malformed-capability"
          )
        )
      } == .malformedReply
    )
    #expect(sender.exactObjectRootIndices == [1])
    #expect(
      await client.ownsRetainedSlideShowObject(
        bindingSessionToken: receipt.bindingSessionToken,
        slideShowObjectToken: receipt.slideShowObjectToken
      )
    )
  }

  @Test func permissionDenialFailsBeforeAnyDescriptorIsSent() async {
    let permission = ScriptedManagedPermissionChecker(states: [.denied])
    let sender = FakeManagedAppleEventSender()
    let client = makeClient(permission: permission, sender: sender)

    let failure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(failure == .permissionDenied)
    #expect(sender.totalSendCount == 0)
    #expect(sender.runSlideShowSendCount == 0)
  }

  @Test func userConsentRequirementIsNotConvertedIntoAnImplicitPrompt() async {
    let permission = ScriptedManagedPermissionChecker(
      states: [.requiresUserConsent]
    )
    let sender = FakeManagedAppleEventSender()
    let client = makeClient(permission: permission, sender: sender)

    let failure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10)
      )
    }
    #expect(failure == .permissionRequiresExplicitUserAction)
    #expect(sender.totalSendCount == 0)
    let targets = await permission.targets
    #expect(targets.count == 1)
    #expect(targets.first?.bindingSessionToken == session)
  }

  @Test func malformedRunReplyConsumesTheOnlyStartAttemptWithoutResending() async {
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0,
      runReplyMode: .malformed
    )
    let client = makeClient(sender: sender)

    let firstFailure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(firstFailure == .startCommandReplyMalformedPossiblyDelivered)
    #expect(sender.runSlideShowSendCount == 1)

    let retryFailure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(retryFailure == .startAttemptAlreadyConsumed)
    #expect(sender.runSlideShowSendCount == 1)
  }

  @Test func staleSessionAndRequestIdentityMismatchFailBeforeExternalCalls() async {
    let sender = FakeManagedAppleEventSender()
    let permission = ScriptedManagedPermissionChecker(states: [.authorized])
    let client = makeClient(permission: permission, sender: sender)

    let staleFailure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(
          session: "old-session",
          startedAt: 10
        )
      )
    }
    #expect(staleFailure == .staleSession)

    let processFailure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(
          processIdentifier: self.processIdentifier + 1,
          startedAt: 10
        )
      )
    }
    #expect(processFailure == .targetIdentityMismatch)

    let wrongIdentity = PowerPointWindowIdentity(
      windowID: 100,
      ownerProcessID: processIdentifier + 1,
      bundleIdentifier: bundleIdentifier
    )!
    let startFailure = await capturedFailure {
      try await client.startManagedSlideShow(
        ManagedSlideShowStartRequest(
          frozenWindowIdentity: wrongIdentity,
          bindingSessionToken: self.session,
          requiredActivePresentationCount: 1,
          requiredPreexistingSlideShowWindowCount: 0
        )
      )
    }
    #expect(startFailure == .targetIdentityMismatch)

    let wrongWindowIdentity = PowerPointWindowIdentity(
      windowID: 101,
      ownerProcessID: processIdentifier,
      bundleIdentifier: bundleIdentifier
    )!
    let wrongWindowFailure = await capturedFailure {
      try await client.startManagedSlideShow(
        ManagedSlideShowStartRequest(
          frozenWindowIdentity: wrongWindowIdentity,
          bindingSessionToken: self.session,
          requiredActivePresentationCount: 1,
          requiredPreexistingSlideShowWindowCount: 0
        )
      )
    }
    #expect(wrongWindowFailure == .targetIdentityMismatch)
    #expect(sender.totalSendCount == 0)
    #expect(await permission.targets.isEmpty)
  }

  @Test func malformedExternalSessionContextFailsBeforeExternalCalls() async {
    let permission = ScriptedManagedPermissionChecker(states: [.authorized])
    let sender = FakeManagedAppleEventSender()
    let malformedContext = sessionContext(session: " \n")
    let client = makeClient(
      sessionContext: malformedContext,
      permission: permission,
      sender: sender
    )

    let failure = await capturedFailure {
      try await client.startManagedSlideShow(
        ManagedSlideShowStartRequest(
          frozenWindowIdentity: malformedContext.frozenWindowIdentity,
          bindingSessionToken: malformedContext.bindingSessionToken,
          requiredActivePresentationCount: 1,
          requiredPreexistingSlideShowWindowCount: 0
        )
      )
    }

    #expect(failure == .malformedConfiguration)
    #expect(sender.totalSendCount == 0)
    #expect(await permission.targets.isEmpty)
  }

  @Test func coordinatorAndStageAContextMismatchFailsBeforeExternalCalls() async {
    let permission = ScriptedManagedPermissionChecker(states: [.authorized])
    let sender = FakeManagedAppleEventSender()
    let stageAContext = sessionContext(session: "stage-a-session")
    let coordinatorContext = sessionContext(session: "coordinator-session")
    let client = makeClient(
      sessionContext: stageAContext,
      permission: permission,
      sender: sender
    )
    let coordinator = ManagedSlideShowBindingCoordinator(
      sessionContext: coordinatorContext,
      observationReader: client,
      slideShowStarter: client,
      machClock: ScriptedManagedClientMachClock([10, 20])
    )

    let result = await coordinator.correlateCandidate(
      for: coordinatorContext.frozenWindowIdentity
    )

    guard case .failure(let failure) = result else {
      Issue.record("Expected the mismatched Stage A client to fail")
      return
    }
    #expect(failure.reason == .baselineReadFailed)
    #expect(failure.recoveryReceipt == nil)
    #expect(sender.totalSendCount == 0)
    #expect(await permission.targets.isEmpty)
  }

  @Test(arguments: [
    PowerPointManagedSlideShowProcessIdentity(
      processIdentifier: 701,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    ),
    PowerPointManagedSlideShowProcessIdentity(
      processIdentifier: 700,
      bundleIdentifier: "wrong.bundle"
    ),
  ])
  func liveProcessIdentityMismatchFailsClosed(
    identityValue: PowerPointManagedSlideShowProcessIdentity
  ) async {
    let identity = ScriptedManagedProcessIdentityReader(identity: identityValue)
    let sender = FakeManagedAppleEventSender()
    let client = makeClient(identity: identity, sender: sender)

    let failure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10)
      )
    }
    #expect(failure == .targetIdentityMismatch)
    #expect(sender.totalSendCount == 0)
  }

  @Test func successfulStartCannotBeRetriedOrReuseItsObjectToken() async throws {
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0
    )
    let client = makeClient(sender: sender, objectToken: "single-object-token")

    let receipt = try await client.startManagedSlideShow(startRequest())
    let retryFailure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }

    #expect(retryFailure == .startAttemptAlreadyConsumed)
    #expect(sender.runSlideShowSendCount == 1)
    #expect(
      await client.ownsRetainedSlideShowObject(
        bindingSessionToken: session,
        slideShowObjectToken: receipt.slideShowObjectToken
      )
    )
    #expect(
      !(await client.ownsRetainedSlideShowObject(
        bindingSessionToken: "other-session",
        slideShowObjectToken: receipt.slideShowObjectToken
      ))
    )
    #expect(
      !(await client.ownsRetainedSlideShowObject(
        bindingSessionToken: session,
        slideShowObjectToken: "single-object-token-reused"
      ))
    )
  }

  @Test func compositeObservationRejectsCountsThatChangeAroundInventory() async {
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0
    )
    sender.setCountScript(.presentation, values: [1, 2])
    sender.setCountScript(.slideShowWindow, values: [0, 0])
    let client = makeClient(sender: sender)

    let failure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10)
      )
    }
    #expect(failure == .unstableCompositeObservation)
    #expect(sender.runSlideShowSendCount == 0)
  }

  @Test func malformedExactWindowInventoryFailsClosed() async {
    let inventory = ScriptedManagedWindowInventoryReader(
      windows: [managedWindow(100), managedWindow(100)]
    )
    let client = makeClient(inventory: inventory)

    let duplicateFailure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10)
      )
    }
    #expect(duplicateFailure == .malformedWindowInventory)

    await inventory.setWindows([
      ManagedSlideShowWindowIdentity(
        windowID: 101,
        processIdentifier: Int(processIdentifier + 1),
        bundleIdentifier: bundleIdentifier
      )
    ])
    let wrongProcessFailure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10, freshToken: "next")
      )
    }
    #expect(wrongProcessFailure == .malformedWindowInventory)
  }

  @Test func startRechecksPreconditionsImmediatelyBeforeItsSingleSend() async {
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0
    )
    sender.setCountScript(.presentation, values: [1, 0])
    sender.setCountScript(.slideShowWindow, values: [0, 0])
    let client = makeClient(sender: sender)

    let failure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(failure == .startPreconditionMismatch)
    #expect(sender.runSlideShowSendCount == 0)

    let retryFailure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(retryFailure == .startAttemptAlreadyConsumed)
  }

  @Test func processIdentityChangeAfterFinalCountsPreventsTheRunEvent() async {
    let exact = exactProcessIdentity()
    let identity = ScriptedManagedProcessIdentityReader(
      identities: [
        exact,  // permission boundary
        exact, exact,  // first count bracket
        exact,  // final count bracket begins
        PowerPointManagedSlideShowProcessIdentity(
          processIdentifier: processIdentifier,
          bundleIdentifier: "replacement.bundle"
        ),
      ]
    )
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0
    )
    let client = makeClient(identity: identity, sender: sender)

    let failure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(failure == .targetIdentityMismatch)
    #expect(sender.runSlideShowSendCount == 0)
  }

  @Test(arguments: ["", "  \n", " padded-token "])
  func invalidOpaqueTokenFailsBeforeSendAndCannotTriggerRetry(
    invalidToken: String
  ) async {
    let sender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0
    )
    let client = makeClient(sender: sender, objectToken: invalidToken)

    let failure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(failure == .opaqueObjectTokenUnavailable)
    #expect(sender.totalSendCount == 0)
    #expect(sender.runSlideShowSendCount == 0)
    let retryFailure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(retryFailure == .startAttemptAlreadyConsumed)
    #expect(sender.runSlideShowSendCount == 0)
  }

  @Test func duplicateOpaqueTokenReservationFailsBeforeAnyExternalCall() async {
    let registry = PowerPointManagedSlideShowOpaqueObjectTokenRegistry()
    #expect(
      registry.reserveStart(
        bindingSessionToken: "other-session",
        objectToken: "already-reserved"
      ) == .reserved
    )
    let sender = FakeManagedAppleEventSender()
    let permission = ScriptedManagedPermissionChecker(states: [.authorized])
    let client = makeClient(
      permission: permission,
      sender: sender,
      objectToken: "already-reserved",
      objectTokenRegistry: registry
    )

    let failure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }

    #expect(failure == .opaqueObjectTokenUnavailable)
    #expect(sender.totalSendCount == 0)
    #expect(await permission.targets.isEmpty)
  }

  @Test(arguments: [
    ManagedRunReplyMode.missing,
    .malformed,
    .transportFailure,
  ])
  func possiblyDeliveredStartFailuresAreDistinctAndNeverRetried(
    mode: ManagedRunReplyMode
  ) async {
    let sender = FakeManagedAppleEventSender(runReplyMode: mode)
    let client = makeClient(sender: sender)

    let firstFailure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    let expected: PowerPointManagedSlideShowAppleEventClientFailure =
      switch mode {
      case .missing: .startCommandReplyMissingPossiblyDelivered
      case .malformed: .startCommandReplyMalformedPossiblyDelivered
      case .transportFailure: .startCommandDeliveryUnknown
      case .valid: .staleCompletion
      }
    #expect(firstFailure == expected)
    #expect(sender.runSlideShowSendCount == 1)

    let retryFailure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }
    #expect(retryFailure == .startAttemptAlreadyConsumed)
    #expect(sender.runSlideShowSendCount == 1)
  }

  @Test func callerCancellationBeforeReplyStillRetainsTheExactReturnedObject() async throws {
    let gate = ControllableManagedRunSendGate()
    let sender = FakeManagedAppleEventSender(runSendGate: gate)
    let client = makeClient(
      sender: sender,
      objectToken: "caller-cancelled-object"
    )
    let task = Task {
      try await client.startManagedSlideShow(self.startRequest())
    }
    try await waitForManagedClientState { gate.hasStarted }

    task.cancel()
    gate.resumeWithReply()

    #expect(await capturedFailure { try await task.value } == .cancelled)
    #expect(sender.runSlideShowSendCount == 1)
    #expect(
      await client.ownsRetainedSlideShowObject(
        bindingSessionToken: session,
        slideShowObjectToken: "caller-cancelled-object"
      )
    )
  }

  @Test func explicitCancellationBeforeReplyStillRetainsTheExactReturnedObject() async throws {
    let gate = ControllableManagedRunSendGate()
    let sender = FakeManagedAppleEventSender(runSendGate: gate)
    let client = makeClient(
      sender: sender,
      objectToken: "explicitly-cancelled-object"
    )
    let task = Task {
      try await client.startManagedSlideShow(self.startRequest())
    }
    try await waitForManagedClientState { gate.hasStarted }

    client.cancelCurrentOperation()
    gate.resumeWithReply()

    #expect(await capturedFailure { try await task.value } == .cancelled)
    #expect(sender.runSlideShowSendCount == 1)
    #expect(
      await client.ownsRetainedSlideShowObject(
        bindingSessionToken: session,
        slideShowObjectToken: "explicitly-cancelled-object"
      )
    )
  }

  @Test func sharedRegistryAllowsOnlyOneStartAcrossClientsForTheSameSession() async throws {
    let registry = PowerPointManagedSlideShowOpaqueObjectTokenRegistry()
    let firstSender = FakeManagedAppleEventSender()
    let secondSender = FakeManagedAppleEventSender()
    let first = makeClient(
      sender: firstSender,
      objectToken: "first-client-token",
      objectTokenRegistry: registry
    )
    let second = makeClient(
      sender: secondSender,
      objectToken: "second-client-token",
      objectTokenRegistry: registry
    )

    _ = try await first.startManagedSlideShow(startRequest())
    let secondFailure = await capturedFailure {
      try await second.startManagedSlideShow(self.startRequest())
    }

    #expect(secondFailure == .startAttemptAlreadyConsumed)
    #expect(firstSender.runSlideShowSendCount == 1)
    #expect(secondSender.totalSendCount == 0)
  }

  @Test func frozenWindowMustStillExistBeforePermissionOrAppleEvents() async {
    let inventory = ScriptedManagedWindowInventoryReader(
      windows: [managedWindow(101)]
    )
    let permission = ScriptedManagedPermissionChecker(states: [.authorized])
    let sender = FakeManagedAppleEventSender()
    let client = makeClient(
      permission: permission,
      inventory: inventory,
      sender: sender
    )

    let failure = await capturedFailure {
      try await client.startManagedSlideShow(self.startRequest())
    }

    #expect(failure == .frozenWindowUnavailable)
    #expect(await inventory.readCount == 1)
    #expect(await permission.targets.isEmpty)
    #expect(sender.totalSendCount == 0)
  }

  @Test func inFlightInvalidationLatchesBeforeSynchronousReplyAndReturnsRecoveryReceipt()
    async throws
  {
    let gate = ControllableManagedRunSendGate()
    let sender = FakeManagedAppleEventSender(runSendGate: gate)
    let client = makeClient(
      sender: sender,
      objectToken: "invalidated-object"
    )
    let task = Task {
      try await client.startManagedSlideShow(self.startRequest())
    }
    try await waitForManagedClientState { gate.hasStarted }

    client.invalidateSession()
    gate.resumeWithReply()

    let recoverable = await capturedRecoverableStartFailure {
      try await task.value
    }
    #expect(recoverable?.reason == .staleSession)
    #expect(recoverable?.recoveryReceipt.slideShowObjectToken == "invalidated-object")
    #expect(
      await client.ownsRetainedSlideShowObject(
        bindingSessionToken: session,
        slideShowObjectToken: "invalidated-object"
      )
    )
    #expect(
      await capturedFailure {
        try await client.readCompositeObservation(
          self.observationRequest(startedAt: 10, freshToken: "after-invalidate")
        )
      } == .staleSession
    )
  }

  @Test func retainedObjectHasExplicitReleaseAfterRollback() async throws {
    let registry = PowerPointManagedSlideShowOpaqueObjectTokenRegistry()
    let client = makeClient(
      objectToken: "release-after-rollback",
      objectTokenRegistry: registry
    )
    let receipt = try await client.startManagedSlideShow(startRequest())

    #expect(await client.releaseRetainedSlideShowObject(receipt))
    #expect(
      !(await client.ownsRetainedSlideShowObject(
        bindingSessionToken: session,
        slideShowObjectToken: receipt.slideShowObjectToken
      ))
    )
    #expect(!(await client.releaseRetainedSlideShowObject(receipt)))
  }

  @Test func nonFiniteTimeoutsFailBeforeAnyExternalCall() async {
    for timeout in [TimeInterval.nan, .infinity, -.infinity] {
      let permission = ScriptedManagedPermissionChecker(states: [.authorized])
      let sender = FakeManagedAppleEventSender()
      let client = makeClient(
        permission: permission,
        sender: sender,
        eventTimeout: timeout
      )

      let failure = await capturedFailure {
        try await client.startManagedSlideShow(self.startRequest())
      }
      #expect(failure == .malformedConfiguration)
      #expect(await permission.targets.isEmpty)
      #expect(sender.totalSendCount == 0)
    }
  }

  @Test func cancelledNoncooperativeCheckMustDrainBeforeReplacement() async throws {
    let permission = ControllableManagedPermissionChecker()
    let sender = FakeManagedAppleEventSender()
    let client = makeClient(permission: permission, sender: sender)

    let firstTask = Task {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10)
      )
    }
    try await waitForManagedClientState {
      await permission.callCount == 1
    }
    firstTask.cancel()

    let overlappingFailure = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10, freshToken: "overlap")
      )
    }
    #expect(overlappingFailure == .priorOperationStillDraining)

    await permission.resume(.authorized)
    let cancelledFailure = await capturedFailure { try await firstTask.value }
    #expect(cancelledFailure == .cancelled)
    #expect(sender.totalSendCount == 0)

    let recovered = try await client.readCompositeObservation(
      observationRequest(startedAt: 10, freshToken: "after-drain")
    )
    #expect(recovered.freshObservationToken == "after-drain")
  }

  @Test func explicitCancellationAlsoRetainsOwnershipUntilDependencyReturns() async throws {
    let permission = ControllableManagedPermissionChecker()
    let client = makeClient(permission: permission)
    let task = Task {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10)
      )
    }
    try await waitForManagedClientState { await permission.callCount == 1 }
    client.cancelCurrentOperation()

    let overlap = await capturedFailure {
      try await client.readCompositeObservation(
        self.observationRequest(startedAt: 10, freshToken: "overlap")
      )
    }
    #expect(overlap == .priorOperationStillDraining)
    await permission.resume(.authorized)
    #expect(await capturedFailure { try await task.value } == .cancelled)
  }

  private func makeClient(
    sessionContext: ManagedSlideShowSessionContext? = nil,
    permission: any PowerPointManagedSlideShowPermissionChecking =
      ScriptedManagedPermissionChecker(states: [.authorized]),
    identity: any PowerPointManagedSlideShowProcessIdentityReading =
      ScriptedManagedProcessIdentityReader(
        identity: PowerPointManagedSlideShowProcessIdentity(
          processIdentifier: 700,
          bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
        )
      ),
    inventory: any PowerPointManagedSlideShowWindowInventoryReading =
      ScriptedManagedWindowInventoryReader(
        windows: [
          ManagedSlideShowWindowIdentity(
            windowID: 100,
            processIdentifier: 700,
            bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
          )
        ]
      ),
    sender: FakeManagedAppleEventSender = FakeManagedAppleEventSender(
      presentationCount: 1,
      slideShowWindowCount: 0
    ),
    clock: any ManagedSlideShowBindingMachClock =
      ScriptedManagedClientMachClock([20]),
    objectToken: String = "object-token",
    objectTokenRegistry: any PowerPointManagedSlideShowOpaqueObjectTokenReserving =
      PowerPointManagedSlideShowOpaqueObjectTokenRegistry(),
    eventTimeout: TimeInterval = 2
  ) -> PowerPointManagedSlideShowAppleEventClient {
    PowerPointManagedSlideShowAppleEventClient(
      sessionContext: sessionContext ?? self.sessionContext(),
      permissionChecker: permission,
      identityReader: identity,
      windowInventoryReader: inventory,
      eventSender: sender,
      machClock: clock,
      opaqueObjectTokenFactory: { objectToken },
      opaqueObjectTokenRegistry: objectTokenRegistry,
      eventTimeout: eventTimeout
    )
  }

  private func sessionContext(
    session: String? = nil,
    processIdentifier: pid_t? = nil,
    windowID: CGWindowID = 100
  ) -> ManagedSlideShowSessionContext {
    ManagedSlideShowSessionContext(
      bindingSessionToken: session ?? self.session,
      frozenWindowIdentity: PowerPointWindowIdentity(
        windowID: windowID,
        ownerProcessID: processIdentifier ?? self.processIdentifier,
        bundleIdentifier: bundleIdentifier
      )!
    )
  }

  private func observationRequest(
    session: String? = nil,
    processIdentifier: pid_t? = nil,
    startedAt: UInt64,
    freshToken: String = "fresh-token"
  ) -> ManagedSlideShowCompositeObservationRequest {
    ManagedSlideShowCompositeObservationRequest(
      bindingSessionToken: session ?? self.session,
      processIdentifier: processIdentifier ?? self.processIdentifier,
      bundleIdentifier: bundleIdentifier,
      freshObservationToken: freshToken,
      requestStartedMachAbsoluteTime: startedAt
    )
  }

  private func startRequest() -> ManagedSlideShowStartRequest {
    ManagedSlideShowStartRequest(
      frozenWindowIdentity: PowerPointWindowIdentity(
        windowID: 100,
        ownerProcessID: processIdentifier,
        bundleIdentifier: bundleIdentifier
      )!,
      bindingSessionToken: session,
      requiredActivePresentationCount: 1,
      requiredPreexistingSlideShowWindowCount: 0
    )
  }

  private func roleCapabilityRequest(
    receipt: ManagedSlideShowStartReceipt,
    capability: PowerPointManagedSlideShowRoleCapability,
    token: String
  ) -> PowerPointManagedSlideShowRoleCapabilityRequest {
    PowerPointManagedSlideShowRoleCapabilityRequest(
      bindingSessionToken: receipt.bindingSessionToken,
      slideShowObjectToken: receipt.slideShowObjectToken,
      processIdentifier: Int(receipt.processIdentifier),
      bundleIdentifier: receipt.bundleIdentifier,
      challengeNonce: 40,
      capability: capability,
      freshRequestToken: token
    )
  }

  private func roleCommandRequest(
    receipt: ManagedSlideShowStartReceipt,
    phaseNonce: UInt64,
    command: PowerPointManagedSlideShowRoleCommand,
    token: String
  ) -> PowerPointManagedSlideShowRoleCommandRequest {
    PowerPointManagedSlideShowRoleCommandRequest(
      bindingSessionToken: receipt.bindingSessionToken,
      slideShowObjectToken: receipt.slideShowObjectToken,
      processIdentifier: Int(receipt.processIdentifier),
      bundleIdentifier: receipt.bundleIdentifier,
      challengeNonce: 40,
      phaseNonce: phaseNonce,
      command: command,
      freshRequestToken: token
    )
  }

  private func roleSemanticRequest(
    receipt: ManagedSlideShowStartReceipt,
    token: String,
    startedAt: UInt64
  ) -> PowerPointManagedSlideShowRoleSemanticStateRequest {
    PowerPointManagedSlideShowRoleSemanticStateRequest(
      bindingSessionToken: receipt.bindingSessionToken,
      slideShowObjectToken: receipt.slideShowObjectToken,
      processIdentifier: Int(receipt.processIdentifier),
      bundleIdentifier: receipt.bundleIdentifier,
      freshRequestToken: token,
      requestStartedMachAbsoluteTime: startedAt
    )
  }

  private func exactProcessIdentity() -> PowerPointManagedSlideShowProcessIdentity {
    PowerPointManagedSlideShowProcessIdentity(
      processIdentifier: processIdentifier,
      bundleIdentifier: bundleIdentifier
    )
  }

  private func managedWindow(_ windowID: Int) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: Int(processIdentifier),
      bundleIdentifier: bundleIdentifier
    )
  }
}

private actor ScriptedManagedPermissionChecker:
  PowerPointManagedSlideShowPermissionChecking
{
  private var states: [PowerPointAutomationPermissionState]
  private var lastState: PowerPointAutomationPermissionState
  private(set) var targets: [PowerPointAutomationPermissionTarget] = []

  init(states: [PowerPointAutomationPermissionState]) {
    self.states = states
    self.lastState = states.last ?? .unavailable
  }

  func passivePreflight(
    target: PowerPointAutomationPermissionTarget
  ) -> PowerPointAutomationPermissionState {
    targets.append(target)
    guard !states.isEmpty else { return lastState }
    let state = states.removeFirst()
    lastState = state
    return state
  }
}

private actor ControllableManagedPermissionChecker:
  PowerPointManagedSlideShowPermissionChecking
{
  private var continuation: CheckedContinuation<PowerPointAutomationPermissionState, Never>?
  private var fallback: PowerPointAutomationPermissionState = .authorized
  private(set) var callCount = 0

  func passivePreflight(
    target: PowerPointAutomationPermissionTarget
  ) async -> PowerPointAutomationPermissionState {
    callCount += 1
    if callCount > 1 { return fallback }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func resume(_ state: PowerPointAutomationPermissionState) {
    fallback = state
    continuation?.resume(returning: state)
    continuation = nil
  }
}

private actor ScriptedManagedProcessIdentityReader:
  PowerPointManagedSlideShowProcessIdentityReading
{
  private var identities: [PowerPointManagedSlideShowProcessIdentity?]
  private var lastIdentity: PowerPointManagedSlideShowProcessIdentity?

  init(identity: PowerPointManagedSlideShowProcessIdentity?) {
    self.identities = [identity]
    self.lastIdentity = identity
  }

  init(identities: [PowerPointManagedSlideShowProcessIdentity?]) {
    self.identities = identities
    self.lastIdentity = identities.last ?? nil
  }

  func currentIdentity(
    for processIdentifier: pid_t
  ) -> PowerPointManagedSlideShowProcessIdentity? {
    guard !identities.isEmpty else { return lastIdentity }
    let identity = identities.removeFirst()
    lastIdentity = identity
    return identity
  }
}

private actor ScriptedManagedWindowInventoryReader:
  PowerPointManagedSlideShowWindowInventoryReading
{
  private var windows: [ManagedSlideShowWindowIdentity]
  private(set) var readCount = 0

  init(windows: [ManagedSlideShowWindowIdentity]) {
    self.windows = windows
  }

  func readExactWindowInventory(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) -> [ManagedSlideShowWindowIdentity] {
    readCount += 1
    return windows
  }

  func setWindows(_ windows: [ManagedSlideShowWindowIdentity]) {
    self.windows = windows
  }
}

private actor ScriptedManagedClientMachClock: ManagedSlideShowBindingMachClock {
  private var values: [UInt64]
  private var lastValue: UInt64

  init(_ values: [UInt64]) {
    self.values = values
    self.lastValue = values.last ?? 0
  }

  func now() -> UInt64 {
    guard !values.isEmpty else { return lastValue }
    let value = values.removeFirst()
    lastValue = value
    return value
  }
}

enum ManagedRunReplyMode: Sendable {
  case valid
  case missing
  case malformed
  case transportFailure
}

private enum ManagedExactObjectReplyMode: Sendable {
  case valid
  case malformedGet
}

private enum ManagedFakeTransportError: Error {
  case controlled
}

private final class ControllableManagedRunSendGate: @unchecked Sendable {
  private let lock = NSLock()
  private let replySemaphore = DispatchSemaphore(value: 0)
  private var _hasStarted = false

  var hasStarted: Bool {
    lock.withLock { _hasStarted }
  }

  func markStartedAndWaitForReply() {
    lock.withLock { _hasStarted = true }
    replySemaphore.wait()
  }

  func resumeWithReply() {
    replySemaphore.signal()
  }
}

private final class FakeManagedAppleEventSender:
  PowerPointManagedSlideShowAppleEventSending, @unchecked Sendable
{
  private let lock = NSLock()
  private var presentationCount: Int32
  private var slideShowWindowCount: Int32
  private var countScripts: [OSType: [Int32]] = [:]
  private let runReplyMode: ManagedRunReplyMode
  private let runSendGate: ControllableManagedRunSendGate?
  private let exactReplyMode: ManagedExactObjectReplyMode
  private var _exactVisibility: Bool
  private var _exactViewState: PowerPointSlideShowState
  private let exactSlideID: Int32
  private let exactSlideIndex: Int32
  private let exactPresentationSaved: Bool
  private let showTypeCode: OSType?
  private let showTypeMalformed: Bool
  private var _totalSendCount = 0
  private var _runSlideShowSendCount = 0
  private var _exitSlideShowSendCount = 0
  private var _lastSendOptionsRawValue: UInt?
  private var _targetProcessIdentifiers: [pid_t] = []
  private var _exactObjectLeafCodes: [OSType] = []
  private var _exactObjectRootIndices: [Int32] = []
  private var _exitRootObjectIndices: [Int32] = []

  init(
    presentationCount: Int32 = 1,
    slideShowWindowCount: Int32 = 0,
    runReplyMode: ManagedRunReplyMode = .valid,
    runSendGate: ControllableManagedRunSendGate? = nil,
    exactReplyMode: ManagedExactObjectReplyMode = .valid,
    exactVisibility: Bool = true,
    exactViewState: PowerPointSlideShowState = .running,
    exactSlideID: Int32 = 50,
    exactSlideIndex: Int32 = 3,
    exactPresentationSaved: Bool = true,
    showTypeCode: OSType? = PowerPointSlideShowType.window.rawValue,
    showTypeMalformed: Bool = false
  ) {
    self.presentationCount = presentationCount
    self.slideShowWindowCount = slideShowWindowCount
    self.runReplyMode = runReplyMode
    self.runSendGate = runSendGate
    self.exactReplyMode = exactReplyMode
    _exactVisibility = exactVisibility
    _exactViewState = exactViewState
    self.exactSlideID = exactSlideID
    self.exactSlideIndex = exactSlideIndex
    self.exactPresentationSaved = exactPresentationSaved
    self.showTypeCode = showTypeCode
    self.showTypeMalformed = showTypeMalformed
  }

  var totalSendCount: Int { lock.withLock { _totalSendCount } }
  var runSlideShowSendCount: Int { lock.withLock { _runSlideShowSendCount } }
  var exitSlideShowSendCount: Int { lock.withLock { _exitSlideShowSendCount } }
  var exactVisibility: Bool { lock.withLock { _exactVisibility } }
  var exactViewState: PowerPointSlideShowState { lock.withLock { _exactViewState } }
  var exactObjectLeafCodes: [OSType] { lock.withLock { _exactObjectLeafCodes } }
  var exactObjectRootIndices: [Int32] { lock.withLock { _exactObjectRootIndices } }
  var exitRootObjectIndices: [Int32] { lock.withLock { _exitRootObjectIndices } }
  var lastSendOptionsRawValue: UInt? {
    lock.withLock { _lastSendOptionsRawValue }
  }
  var targetProcessIdentifiers: [pid_t] {
    lock.withLock { _targetProcessIdentifiers }
  }

  func setCountScript(
    _ objectClass: PowerPointAppleEventObjectClass,
    values: [Int32]
  ) {
    lock.withLock { countScripts[objectClass.rawValue] = values }
  }

  func send(
    _ event: NSAppleEventDescriptor,
    options: NSAppleEventDescriptor.SendOptions,
    timeout: TimeInterval
  ) throws -> NSAppleEventDescriptor? {
    let isRunSlideShow =
      event.eventClass == AEEventClass(PowerPointAppleEventCode.powerPointSuite)
      && event.eventID == AEEventID(PowerPointAppleEventCode.runSlideShow)

    if isRunSlideShow {
      lock.withLock {
        recordSend(event, options: options)
        _runSlideShowSendCount += 1
        slideShowWindowCount = 1
      }
      runSendGate?.markStartedAndWaitForReply()
      switch runReplyMode {
      case .valid:
        return managedClientReply(
          direct: managedClientObjectSpecifier(
            objectClass: .slideShowWindow,
            index: 1
          )
        )
      case .missing:
        return nil
      case .malformed:
        return managedClientReply(
          direct: NSAppleEventDescriptor(string: "malformed")
        )
      case .transportFailure:
        throw ManagedFakeTransportError.controlled
      }
    }

    return lock.withLock {
      recordSend(event, options: options)

      if event.eventClass == AEEventClass(PowerPointAppleEventCode.powerPointSuite),
        event.eventID == AEEventID(PowerPointAppleEventCode.exitSlideShow),
        let direct = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
      {
        _exitSlideShowSendCount += 1
        if let rootIndex = managedClientRootObjectIndex(direct) {
          _exitRootObjectIndices.append(rootIndex)
        }
        return managedClientReply(direct: nil)
      }

      if event.eventClass == AEEventClass(kAECoreSuite),
        event.eventID == AEEventID(kAECountElements),
        let objectClass = event.paramDescriptor(
          forKeyword: AEKeyword(keyAEObjectClass)
        )?.typeCodeValue
      {
        let count: Int32
        if var script = countScripts[objectClass], !script.isEmpty {
          count = script.removeFirst()
          countScripts[objectClass] = script
        } else if objectClass == PowerPointAppleEventObjectClass.presentation.rawValue {
          count = presentationCount
        } else {
          count = slideShowWindowCount
        }
        return managedClientReply(direct: NSAppleEventDescriptor(int32: count))
      }

      if event.eventClass == AEEventClass(kAECoreSuite),
        event.eventID == AEEventID(kAEGetData),
        let direct = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))
      {
        let leafCode = managedClientPropertyLeafCode(direct)
        if leafCode == PowerPointAppleEventProperty.slideShowType.rawValue {
          if showTypeMalformed {
            return managedClientReply(direct: NSAppleEventDescriptor(string: "malformed"))
          }
          guard let showTypeCode else { return managedClientReply(direct: nil) }
          return managedClientReply(
            direct: NSAppleEventDescriptor(enumCode: showTypeCode)
          )
        }
        if managedClientRootObjectClass(direct) == .slideShowWindow,
          let rootIndex = managedClientRootObjectIndex(direct)
        {
          _exactObjectLeafCodes.append(leafCode ?? 0)
          _exactObjectRootIndices.append(rootIndex)
          if exactReplyMode == .malformedGet {
            return managedClientReply(
              direct: NSAppleEventDescriptor(string: "malformed")
            )
          }
          switch leafCode {
          case PowerPointAppleEventProperty.visible.rawValue:
            return managedClientReply(
              direct: NSAppleEventDescriptor(boolean: _exactVisibility)
            )
          case PowerPointAppleEventProperty.slideState.rawValue:
            return managedClientReply(
              direct: NSAppleEventDescriptor(enumCode: _exactViewState.rawValue)
            )
          case PowerPointAppleEventProperty.slideID.rawValue:
            return managedClientReply(direct: NSAppleEventDescriptor(int32: exactSlideID))
          case PowerPointAppleEventProperty.slideIndex.rawValue:
            return managedClientReply(direct: NSAppleEventDescriptor(int32: exactSlideIndex))
          case PowerPointAppleEventProperty.presentationSaved.rawValue:
            return managedClientReply(
              direct: NSAppleEventDescriptor(boolean: exactPresentationSaved)
            )
          default:
            return managedClientReply(direct: nil)
          }
        }
        return managedClientReply(
          direct: managedClientObjectSpecifier(
            objectClass: .presentation,
            index: 1
          )
        )
      }

      if event.eventClass == AEEventClass(kAECoreSuite),
        event.eventID == AEEventID(kAESetData),
        let direct = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)),
        managedClientRootObjectClass(direct) == .slideShowWindow,
        let rootIndex = managedClientRootObjectIndex(direct),
        let leafCode = managedClientPropertyLeafCode(direct),
        let data = event.paramDescriptor(forKeyword: AEKeyword(keyAEData))
      {
        _exactObjectLeafCodes.append(leafCode)
        _exactObjectRootIndices.append(rootIndex)
        switch leafCode {
        case PowerPointAppleEventProperty.visible.rawValue:
          guard data.descriptorType == DescType(typeBoolean) else { return nil }
          _exactVisibility = data.booleanValue
        case PowerPointAppleEventProperty.slideState.rawValue:
          guard data.descriptorType == DescType(typeEnumerated),
            let state = PowerPointSlideShowState(rawValue: data.enumCodeValue)
          else { return nil }
          _exactViewState = state
        default:
          return nil
        }
        return managedClientReply(direct: nil)
      }

      return nil
    }
  }

  private func recordSend(
    _ event: NSAppleEventDescriptor,
    options: NSAppleEventDescriptor.SendOptions
  ) {
    _totalSendCount += 1
    _lastSendOptionsRawValue = options.rawValue
    if let target = event.attributeDescriptor(
      forKeyword: AEKeyword(keyAddressAttr)
    ), target.descriptorType == DescType(typeKernelProcessID),
      target.data.count == MemoryLayout<pid_t>.size
    {
      _targetProcessIdentifiers.append(
        target.data.withUnsafeBytes { bytes in
          bytes.loadUnaligned(as: pid_t.self)
        }
      )
    }

  }
}

private func managedClientPropertyLeafCode(
  _ descriptor: NSAppleEventDescriptor
) -> OSType? {
  descriptor.forKeyword(AEKeyword(keyAEKeyData))?.typeCodeValue
}

private func managedClientRootObjectIndex(
  _ descriptor: NSAppleEventDescriptor
) -> Int32? {
  var current = descriptor
  while current.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
    == OSType(typeProperty),
    let container = current.forKeyword(AEKeyword(keyAEContainer))
  {
    current = container
  }
  return current.forKeyword(AEKeyword(keyAEKeyData))?.int32Value
}

private func managedClientRootObjectClass(
  _ descriptor: NSAppleEventDescriptor
) -> PowerPointAppleEventObjectClass? {
  var current = descriptor
  while current.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
    == OSType(typeProperty),
    let container = current.forKeyword(AEKeyword(keyAEContainer))
  {
    current = container
  }
  guard
    let rawValue = current.forKeyword(AEKeyword(keyAEDesiredClass))?.typeCodeValue
  else { return nil }
  return PowerPointAppleEventObjectClass(rawValue: rawValue)
}

private func managedClientReply(
  direct: NSAppleEventDescriptor?
) -> NSAppleEventDescriptor {
  let reply = NSAppleEventDescriptor(
    eventClass: AEEventClass(kAECoreSuite),
    eventID: AEEventID(kAEAnswer),
    targetDescriptor: nil,
    returnID: AEReturnID(kAutoGenerateReturnID),
    transactionID: AETransactionID(kAnyTransactionID)
  )
  if let direct {
    reply.setParam(direct, forKeyword: AEKeyword(keyDirectObject))
  }
  return reply
}

private func managedClientObjectSpecifier(
  objectClass: PowerPointAppleEventObjectClass,
  index: Int32
) -> NSAppleEventDescriptor? {
  let record = NSAppleEventDescriptor.record()
  record.setDescriptor(
    NSAppleEventDescriptor(typeCode: objectClass.rawValue),
    forKeyword: AEKeyword(keyAEDesiredClass)
  )
  record.setDescriptor(
    NSAppleEventDescriptor(enumCode: OSType(formAbsolutePosition)),
    forKeyword: AEKeyword(keyAEKeyForm)
  )
  record.setDescriptor(
    NSAppleEventDescriptor(int32: index),
    forKeyword: AEKeyword(keyAEKeyData)
  )
  record.setDescriptor(
    NSAppleEventDescriptor.null(),
    forKeyword: AEKeyword(keyAEContainer)
  )
  return record.coerce(toDescriptorType: DescType(typeObjectSpecifier))
}

@MainActor
private func capturedFailure<Value>(
  _ operation: () async throws -> Value
) async -> PowerPointManagedSlideShowAppleEventClientFailure? {
  do {
    _ = try await operation()
    return nil
  } catch let failure as PowerPointManagedSlideShowAppleEventClientFailure {
    return failure
  } catch let failure as PowerPointManagedSlideShowRecoverableStartFailure {
    return failure.reason
  } catch {
    Issue.record("Unexpected error type: \(error)")
    return nil
  }
}

@MainActor
private func capturedRecoverableStartFailure<Value>(
  _ operation: () async throws -> Value
) async -> PowerPointManagedSlideShowRecoverableStartFailure? {
  do {
    _ = try await operation()
    return nil
  } catch let failure as PowerPointManagedSlideShowRecoverableStartFailure {
    return failure
  } catch {
    Issue.record("Unexpected error type: \(error)")
    return nil
  }
}

private func waitForManagedClientState(
  maxYields: Int = 10_000,
  _ predicate: @escaping @Sendable () async -> Bool
) async throws {
  for _ in 0..<maxYields {
    if await predicate() { return }
    await Task.yield()
  }
  Issue.record("Timed out waiting for managed-client fake state")
  throw PowerPointManagedSlideShowAppleEventClientFailure.staleCompletion
}
