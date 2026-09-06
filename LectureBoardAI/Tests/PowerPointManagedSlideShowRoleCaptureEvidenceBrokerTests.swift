import CoreGraphics
import CoreVideo
import Foundation
import LectureBoardCore
import ScreenCaptureKit
import Testing

@testable import LectureBoard_AI

/// Deterministic fakes only. These tests do not enumerate ScreenCaptureKit content, create an
/// `SCStream`, send an Apple Event, query permission, or launch PowerPoint.
@MainActor
struct PowerPointManagedSlideShowRoleCaptureEvidenceBrokerTests {
  private let operationID = CaptureOperationID(rawValue: 7)
  private let generation: UInt64 = 9

  @Test func auxiliaryFingerprintUsesAuthoritativeContentCropAndIdleContinuity() throws {
    let pixelBuffer = try #require(
      brokerPixelBuffer(
        width: 66,
        height: 20,
        whiteRegion: CGRect(x: 0, y: 0, width: 35, height: 20)
      )
    )
    let geometry = brokerSurfaceAttachments(
      contentRect: CGRect(x: 0, y: 0, width: 35.555_556_416_5, height: 20.000_000_484_3),
      scaleFactor: 1,
      contentScale: 0.022_222_22
    )
    var processor = PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor()
    switch processor.process(
      status: .generated,
      pixelBuffer: pixelBuffer,
      attachments: geometry
    ) {
    case .generated(let fingerprint):
      #expect(fingerprint.luminance.allSatisfy { $0 == 255 })
    case .idle, .invalid:
      Issue.record("Expected a cropped generated fingerprint")
    }
    #expect(
      processor.process(status: .idle, pixelBuffer: nil, attachments: nil) == .idle
    )
    #expect(
      processor.process(status: .idle, pixelBuffer: nil, attachments: geometry) == .idle
    )
  }

  @Test func auxiliaryFingerprintRejectsMalformedOrOutOfBoundsInitialGeometryAndPoisons() throws {
    let pixelBuffer = try #require(
      brokerPixelBuffer(width: 8, height: 4, whiteRegion: CGRect(x: 0, y: 0, width: 8, height: 4))
    )
    let valid = brokerSurfaceAttachments(
      contentRect: CGRect(x: 0, y: 0, width: 8, height: 4),
      scaleFactor: 1,
      contentScale: 1
    )
    let invalidAttachments: [[SCStreamFrameInfo: Any]?] = [
      nil,
      [.contentRect: NSValue(rect: CGRect(x: 0, y: 0, width: 8, height: 4))],
      [
        .contentRect: NSValue(rect: CGRect(x: 0, y: 0, width: 8, height: 4)),
        .scaleFactor: true,
        .contentScale: NSNumber(value: 1),
      ],
      brokerSurfaceAttachments(
        contentRect: CGRect(x: 0, y: 0, width: 9, height: 4),
        scaleFactor: 1,
        contentScale: 1
      ),
    ]
    for attachments in invalidAttachments {
      var processor = PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor()
      #expect(
        processor.process(
          status: .generated,
          pixelBuffer: pixelBuffer,
          attachments: attachments
        ) == .invalid
      )
      #expect(
        processor.process(
          status: .generated,
          pixelBuffer: pixelBuffer,
          attachments: valid
        ) == .invalid
      )
    }
  }

  @Test func auxiliaryFingerprintRejectsLaterGeometryBufferAndIdleDrift() throws {
    let pixelBuffer = try #require(
      brokerPixelBuffer(width: 8, height: 4, whiteRegion: CGRect(x: 0, y: 0, width: 8, height: 4))
    )
    let resizedBuffer = try #require(
      brokerPixelBuffer(width: 9, height: 4, whiteRegion: CGRect(x: 0, y: 0, width: 9, height: 4))
    )
    let valid = brokerSurfaceAttachments(
      contentRect: CGRect(x: 0, y: 0, width: 8, height: 4),
      scaleFactor: 1,
      contentScale: 1
    )
    let moved = brokerSurfaceAttachments(
      contentRect: CGRect(x: 0.5, y: 0, width: 7.5, height: 4),
      scaleFactor: 1,
      contentScale: 1
    )
    let partial: [SCStreamFrameInfo: Any] = [
      .contentRect: NSValue(rect: CGRect(x: 0, y: 0, width: 8, height: 4))
    ]

    let mutations:
      [(inout PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor) ->
        PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor.Outcome] = [
          { (processor: inout PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor) in
            processor.process(status: .generated, pixelBuffer: pixelBuffer, attachments: moved)
          },
          { (processor: inout PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor) in
            processor.process(status: .generated, pixelBuffer: resizedBuffer, attachments: valid)
          },
          { (processor: inout PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor) in
            processor.process(status: .idle, pixelBuffer: pixelBuffer, attachments: partial)
          },
          { (processor: inout PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor) in
            processor.process(status: .idle, pixelBuffer: resizedBuffer, attachments: nil)
          },
        ]
    for mutation in mutations {
      var processor = PowerPointManagedSlideShowRoleAuxiliaryFingerprintProcessor()
      guard
        case .generated = processor.process(
          status: .generated,
          pixelBuffer: pixelBuffer,
          attachments: valid
        )
      else {
        Issue.record("Expected initial generated evidence")
        continue
      }
      #expect(mutation(&processor) == .invalid)
      #expect(
        processor.process(status: .idle, pixelBuffer: nil, attachments: nil) == .invalid
      )
    }
  }

  @Test func captureAnchorWaitsOnceForDelayedInitialDelivery() async throws {
    let candidate = identity(20)
    let gate = BrokerNextDeliveryGate()
    let primary = BrokerScriptedDeliverySource(
      identity: candidate,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      steps: [
        .delivery(delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1))
      ],
      nextGate: gate
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [BrokerRetainedWindowReference(identity: candidate)],
      primary: primary,
      inventory: BrokerWindowInventory([candidate]),
      factory: BrokerAuxiliaryFactory(sources: [:])
    )

    let pending = Task { try await lease.captureAnchor() }
    while await primary.nextCount == 0 { await Task.yield() }
    await gate.release()
    let first = try await pending.value
    let second = try await lease.captureAnchor()

    #expect(first == second)
    #expect(first.candidateStreamMemberToken == "candidate-member")
    #expect(first.candidateContinuityToken == "candidate-continuity")
    #expect(first.minimumCandidateDeliverySequenceExclusive == 10)
    #expect(await primary.nextCount == 1)
    #expect(
      await primary.requests == [
        PowerPointManagedSlideShowRoleCaptureDeliveryRequest(
          commandReplyMachAbsoluteTime: 0,
          requestStartedMachAbsoluteTime: 0
        )
      ]
    )
  }

  @Test func captureAnchorPreservesBoundedInitialDeliveryTimeout() async throws {
    let candidate = identity(20)
    let primary = PowerPointManagedSlideShowRoleCaptureDeliveryBuffer(
      identity: candidate,
      captureOperationID: operationID,
      captureGeneration: generation,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      deliveryTimeout: 0.1
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [BrokerRetainedWindowReference(identity: candidate)],
      primary: primary,
      inventory: BrokerWindowInventory([candidate]),
      factory: BrokerAuxiliaryFactory(sources: [:])
    )

    #expect(
      await capturedFailure {
        _ = try await lease.captureAnchor()
      } == .deliveryTimedOut
    )
    await lease.stop()
  }

  @Test func stoppedOrCancelledPendingInitialDeliveryCannotIssueAnchor() async throws {
    for cancellation in [false, true] {
      let candidate = identity(20)
      let gate = BrokerNextDeliveryGate()
      let primary = BrokerScriptedDeliverySource(
        identity: candidate,
        streamMemberToken: "candidate-member",
        continuityToken: "candidate-continuity",
        steps: [
          .delivery(delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1))
        ],
        nextGate: gate
      )
      let lease = try makeLease(
        candidate: candidate,
        retained: [BrokerRetainedWindowReference(identity: candidate)],
        primary: primary,
        inventory: BrokerWindowInventory([candidate]),
        factory: BrokerAuxiliaryFactory(sources: [:])
      )
      let pending = Task { try await lease.captureAnchor() }
      while await primary.nextCount == 0 { await Task.yield() }
      if cancellation {
        pending.cancel()
      } else {
        await lease.stop()
      }
      await gate.release()

      #expect(
        await capturedFailure {
          _ = try await pending.value
        } == .inactiveLease,
        "cancellation: \(cancellation)"
      )
      if cancellation { await lease.stop() }
    }
  }

  @Test
  func initialDeliveryWaitRetainsExactValidationAndNeverRetriesMalformedCurrent() async throws {
    for mutation in [
      BrokerDeliveryMutation.missingIdentity,
      .blankStatus,
      .operationDrift,
      .generationDrift,
      .streamDrift,
      .continuityDrift,
    ] {
      let candidate = identity(20)
      let primary = BrokerScriptedDeliverySource(
        identity: candidate,
        streamMemberToken: "candidate-member",
        continuityToken: "candidate-continuity",
        steps: [
          .delivery(
            delivery(
              candidate,
              sequence: 10,
              callback: 100,
              display: 90,
              luminance: 1,
              mutation: mutation
            )
          )
        ]
      )
      let lease = try makeLease(
        candidate: candidate,
        retained: [BrokerRetainedWindowReference(identity: candidate)],
        primary: primary,
        inventory: BrokerWindowInventory([candidate]),
        factory: BrokerAuxiliaryFactory(sources: [:])
      )

      #expect(
        await capturedFailure {
          _ = try await lease.captureAnchor()
        } == mutation.expectedFailure,
        "awaited mutation: \(mutation)"
      )
      #expect(await primary.nextCount == 1)
    }

    for mutation in [BrokerDeliveryMutation.missingIdentity, .operationDrift] {
      let candidate = identity(20)
      let invalidCurrent = BrokerScriptedDeliverySource(
        identity: candidate,
        streamMemberToken: "candidate-member",
        continuityToken: "candidate-continuity",
        current: delivery(
          candidate,
          sequence: 10,
          callback: 100,
          display: 90,
          luminance: 1,
          mutation: mutation
        ),
        steps: [
          .delivery(delivery(candidate, sequence: 11, callback: 110, display: 100, luminance: 2))
        ]
      )
      let invalidLease = try makeLease(
        candidate: candidate,
        retained: [BrokerRetainedWindowReference(identity: candidate)],
        primary: invalidCurrent,
        inventory: BrokerWindowInventory([candidate]),
        factory: BrokerAuxiliaryFactory(sources: [:])
      )

      #expect(
        await capturedFailure {
          _ = try await invalidLease.captureAnchor()
        } == mutation.expectedFailure,
        "current mutation: \(mutation)"
      )
      #expect(await invalidCurrent.nextCount == 0)
    }
  }

  @Test func preAnchorSealRetainsHandlesWhileReadingFreshSameIDGeometry() async throws {
    let candidate = identity(20)
    let originalOther = identity(21)
    let late = identity(22)
    let candidateGeometry = ManagedSlideShowWindowGeometry(
      left: 100, top: 340, width: 1_600, height: 900)
    let originalOtherGeometry = ManagedSlideShowWindowGeometry(
      left: 20, top: 30, width: 800, height: 600)
    let lateGeometry = ManagedSlideShowWindowGeometry(
      left: 100, top: 340, width: 66, height: 20)
    let movedOtherGeometry = ManagedSlideShowWindowGeometry(
      left: 40, top: 60, width: 640, height: 480)
    let originalCandidateReference = BrokerRetainedWindowReference(
      identity: candidate, windowGeometry: candidateGeometry)
    let originalOtherReference = BrokerRetainedWindowReference(
      identity: originalOther, windowGeometry: originalOtherGeometry)
    let refreshedCandidateReference = BrokerRetainedWindowReference(
      identity: candidate,
      windowGeometry: ManagedSlideShowWindowGeometry(left: 0, top: 0, width: 1, height: 1)
    )
    let refreshedOtherReference = BrokerRetainedWindowReference(
      identity: originalOther,
      windowGeometry: ManagedSlideShowWindowGeometry(left: 0, top: 0, width: 2, height: 2)
    )
    let lateReference = BrokerRetainedWindowReference(
      identity: late, windowGeometry: lateGeometry)
    let primary = BrokerScriptedDeliverySource(
      identity: candidate,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      current: delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1),
      steps: [
        .delivery(delivery(candidate, sequence: 11, callback: 130, display: 125, luminance: 2)),
        .delivery(
          delivery(
            candidate,
            status: .idle,
            sequence: 12,
            callback: 150,
            display: 125,
            luminance: 2
          )
        ),
      ]
    )
    let originalOtherSource = BrokerScriptedDeliverySource(
      identity: originalOther,
      streamMemberToken: "other-member",
      continuityToken: "other-continuity",
      steps: [
        .delivery(delivery(originalOther, sequence: 1, callback: 130, display: 125, luminance: 3)),
        .delivery(
          delivery(
            originalOther,
            status: .idle,
            sequence: 2,
            callback: 150,
            display: 125,
            luminance: 3
          )
        ),
      ]
    )
    let lateSource = BrokerScriptedDeliverySource(
      identity: late,
      streamMemberToken: "late-member",
      continuityToken: "late-continuity",
      steps: [
        .delivery(
          delivery(
            late,
            sequence: 1,
            callback: 130,
            display: 125,
            luminance: 4,
            streamMemberToken: "late-member",
            continuityToken: "late-continuity"
          )
        ),
        .delivery(
          delivery(
            late,
            status: .idle,
            sequence: 2,
            callback: 150,
            display: 125,
            luminance: 4,
            streamMemberToken: "late-member",
            continuityToken: "late-continuity"
          )
        ),
      ]
    )
    let snapshotReader = BrokerRetainedWindowSnapshotReader(
      windows: [refreshedCandidateReference, refreshedOtherReference, lateReference]
    )
    let factory = BrokerAuxiliaryFactory(
      sources: [21: originalOtherSource, 22: lateSource]
    )
    let inventory = BrokerMutableWindowInventory(
      [candidate, originalOther, late],
      geometries: [
        20: candidateGeometry,
        21: originalOtherGeometry,
        22: lateGeometry,
      ]
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [originalCandidateReference, originalOtherReference],
      primary: primary,
      inventory: inventory,
      factory: factory,
      retainedWindowSnapshotReader: snapshotReader
    )

    let anchor = try await lease.captureAnchor()
    let initial = try await lease.readWindowEvidence(
      for: request(anchor: anchor, phase: .baseline, nonce: 40, minimum: 110, started: 120)
    )
    await inventory.replace(
      with: [candidate, originalOther, late],
      geometries: [
        20: candidateGeometry,
        21: movedOtherGeometry,
        22: lateGeometry,
      ]
    )
    let stable = try await lease.readWindowEvidence(
      for: request(anchor: anchor, phase: .baseline, nonce: 40, minimum: 135, started: 140)
    )

    #expect(await snapshotReader.readCount == 1)
    #expect(
      factory.requestedReferenceIDs == [
        ObjectIdentifier(originalOtherReference), ObjectIdentifier(lateReference),
      ]
    )
    #expect(!factory.requestedReferenceIDs.contains(ObjectIdentifier(refreshedOtherReference)))
    #expect(
      initial.windows.first(where: { $0.identity.windowID == 21 })?.windowGeometry
        == originalOtherGeometry
    )
    #expect(
      stable.windows.first(where: { $0.identity.windowID == 20 })?.windowGeometry
        == candidateGeometry
    )
    #expect(
      stable.windows.first(where: { $0.identity.windowID == 21 })?.windowGeometry
        == movedOtherGeometry
    )
    #expect(
      stable.windows.first(where: { $0.identity.windowID == 22 })?.windowGeometry == lateGeometry)
  }

  @Test func preAnchorSealRejectsMalformedDuplicateAndMissingOriginalSnapshots() async throws {
    let candidate = identity(20)
    let other = identity(21)
    let foreign = PowerPointWindowIdentity(
      windowID: 22,
      ownerProcessID: 701,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )!
    let snapshots: [[any PowerPointManagedSlideShowRoleRetainedWindowReference]] = [
      [
        BrokerRetainedWindowReference(identity: candidate),
        BrokerRetainedWindowReference(identity: foreign),
      ],
      [
        BrokerRetainedWindowReference(identity: candidate),
        BrokerRetainedWindowReference(identity: candidate),
        BrokerRetainedWindowReference(identity: other),
      ],
      [BrokerRetainedWindowReference(identity: candidate)],
    ]

    for snapshot in snapshots {
      let primary = primarySource(candidate)
      let snapshotReader = BrokerRetainedWindowSnapshotReader(windows: snapshot)
      let lease = try makeLease(
        candidate: candidate,
        retained: [
          BrokerRetainedWindowReference(identity: candidate),
          BrokerRetainedWindowReference(identity: other),
        ],
        primary: primary,
        inventory: BrokerWindowInventory([candidate, other]),
        factory: BrokerAuxiliaryFactory(sources: [:]),
        retainedWindowSnapshotReader: snapshotReader
      )

      #expect(
        await capturedFailure {
          _ = try await lease.captureAnchor()
        } == .inventoryDrift
      )
      #expect(
        await capturedFailure {
          _ = try await lease.captureAnchor()
        } == .inactiveLease
      )
      #expect(await snapshotReader.readCount == 1)
    }
  }

  @Test func preAnchorSealRejectsParallelCreationAndNeverAdoptsPostSealWindows() async throws {
    let candidate = identity(20)
    let late = identity(21)
    let postSeal = identity(22)
    let gate = BrokerNextDeliveryGate()
    let snapshotReader = BrokerRetainedWindowSnapshotReader(
      windows: [
        BrokerRetainedWindowReference(identity: candidate),
        BrokerRetainedWindowReference(identity: late),
      ],
      gate: gate
    )
    let inventory = BrokerMutableWindowInventory([candidate, late])
    let primary = primarySource(candidate)
    let lease = try makeLease(
      candidate: candidate,
      retained: [BrokerRetainedWindowReference(identity: candidate)],
      primary: primary,
      inventory: inventory,
      factory: BrokerAuxiliaryFactory(sources: [:]),
      retainedWindowSnapshotReader: snapshotReader
    )
    let pending = Task { try await lease.captureAnchor() }
    while await snapshotReader.readCount == 0 { await Task.yield() }

    #expect(
      await capturedFailure {
        _ = try await lease.captureAnchor()
      } == .inactiveLease
    )
    await gate.release()
    let anchor = try await pending.value
    #expect(try await lease.captureAnchor() == anchor)
    #expect(await snapshotReader.readCount == 1)

    await inventory.replace(with: [candidate, late, postSeal])
    #expect(
      await capturedFailure {
        _ = try await lease.readWindowEvidence(
          for: self.request(anchor: anchor, phase: .baseline)
        )
      } == .inventoryDrift
    )
    #expect(await snapshotReader.readCount == 1)
  }

  @Test func stoppedOrCancelledPendingPreAnchorSealCannotIssueAnchor() async throws {
    for cancellation in [false, true] {
      let candidate = identity(20)
      let gate = BrokerNextDeliveryGate()
      let snapshotReader = BrokerRetainedWindowSnapshotReader(
        windows: [BrokerRetainedWindowReference(identity: candidate)],
        gate: gate
      )
      let lease = try makeLease(
        candidate: candidate,
        retained: [BrokerRetainedWindowReference(identity: candidate)],
        primary: primarySource(candidate),
        inventory: BrokerWindowInventory([candidate]),
        factory: BrokerAuxiliaryFactory(sources: [:]),
        retainedWindowSnapshotReader: snapshotReader
      )
      let pending = Task { try await lease.captureAnchor() }
      while await snapshotReader.readCount == 0 { await Task.yield() }
      if cancellation {
        pending.cancel()
      } else {
        await lease.stop()
      }
      await gate.release()

      #expect(
        await capturedFailure {
          _ = try await pending.value
        } == .inactiveLease,
        "cancellation: \(cancellation)"
      )
      #expect(await snapshotReader.readCount == 1)
      if cancellation { await lease.stop() }
    }
  }

  @Test func primaryIdleAndSamePayloadAuxiliaryIdlePreserveExactContinuity() async throws {
    let candidate = identity(20)
    let other = identity(21)
    let candidateReference = BrokerRetainedWindowReference(identity: candidate)
    let otherReference = BrokerRetainedWindowReference(identity: other)
    let primary = BrokerScriptedDeliverySource(
      identity: candidate,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      current: delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1),
      steps: [
        .delivery(
          delivery(
            candidate,
            status: .idle,
            sequence: 11,
            callback: 130,
            display: 90,
            luminance: 1
          )
        ),
        .delivery(
          delivery(
            candidate,
            status: .idle,
            sequence: 12,
            callback: 150,
            display: 90,
            luminance: 1
          )
        ),
      ]
    )
    let auxiliary = BrokerScriptedDeliverySource(
      identity: other,
      streamMemberToken: "other-member",
      continuityToken: "other-continuity",
      steps: [
        .delivery(delivery(other, sequence: 1, callback: 130, display: 125, luminance: 2)),
        .delivery(
          delivery(
            other,
            status: .idle,
            sequence: 2,
            callback: 150,
            display: 125,
            luminance: 2
          )
        ),
      ]
    )
    let factory = BrokerAuxiliaryFactory(sources: [21: auxiliary])
    let lease = try makeLease(
      candidate: candidate,
      retained: [candidateReference, otherReference],
      primary: primary,
      inventory: BrokerWindowInventory([candidate, other]),
      factory: factory
    )
    let anchor = try await lease.captureAnchor()

    let first = try await lease.readWindowEvidence(
      for: request(anchor: anchor, phase: .baseline, nonce: 40, minimum: 110, started: 120)
    )
    let second = try await lease.readWindowEvidence(
      for: request(anchor: anchor, phase: .baseline, nonce: 40, minimum: 135, started: 140)
    )

    #expect(first.windows.map(\.deliveryProvenance?.status) == [.idle, .generated])
    #expect(second.windows.map(\.deliveryProvenance?.status) == [.idle, .idle])
    #expect(second.windows.map(\.displayTime) == [90, 125])
    #expect(await primary.startCount == 0)
    #expect(await auxiliary.startCount == 1)
    #expect(factory.requestedReferenceIDs == [ObjectIdentifier(otherReference)])
    #expect(!factory.requestedReferenceIDs.contains(ObjectIdentifier(candidateReference)))
  }

  @Test func firstCandidateMutationDeliveryMustBeGenerated() async throws {
    let candidate = identity(20)
    let primary = BrokerScriptedDeliverySource(
      identity: candidate,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      current: delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1),
      steps: [
        .delivery(
          delivery(
            candidate,
            status: .idle,
            sequence: 11,
            callback: 130,
            display: 90,
            luminance: 1
          )
        )
      ]
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [BrokerRetainedWindowReference(identity: candidate)],
      primary: primary,
      inventory: BrokerWindowInventory([candidate]),
      factory: BrokerAuxiliaryFactory(sources: [:])
    )
    let anchor = try await lease.captureAnchor()

    #expect(
      await capturedFailure {
        _ = try await lease.readWindowEvidence(
          for: self.request(
            anchor: anchor,
            phase: .pixelBlack,
            nonce: 41,
            minimum: 110,
            started: 120
          )
        )
      } == .candidateMutationRequiresGeneratedPayload
    )
  }

  @Test func inventoryDriftNeverRebindsFromNumericWindowIdentifiers() async throws {
    let candidate = identity(20)
    let retainedOther = identity(21)
    let replacement = identity(22)
    let primary = primarySource(candidate)
    let factory = BrokerAuxiliaryFactory(sources: [:])
    let lease = try makeLease(
      candidate: candidate,
      retained: [
        BrokerRetainedWindowReference(identity: candidate),
        BrokerRetainedWindowReference(identity: retainedOther),
      ],
      primary: primary,
      inventory: BrokerWindowInventory([candidate, replacement]),
      factory: factory
    )
    let anchor = try await lease.captureAnchor()

    #expect(
      await capturedFailure {
        _ = try await lease.readWindowEvidence(
          for: self.request(anchor: anchor, phase: .baseline)
        )
      } == .inventoryDrift
    )
    #expect(factory.requestedReferenceIDs.isEmpty)
  }

  @Test func malformedGapAndLineageDriftFailClosed() async throws {
    for mutation in BrokerDeliveryMutation.allCases {
      let candidate = identity(20)
      let primary = BrokerScriptedDeliverySource(
        identity: candidate,
        streamMemberToken: "candidate-member",
        continuityToken: "candidate-continuity",
        current: delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1),
        steps: mutation.steps(
          delivery: delivery(
            candidate,
            status: .idle,
            sequence: 11,
            callback: 130,
            display: 90,
            luminance: 1,
            mutation: mutation
          )
        )
      )
      let lease = try makeLease(
        candidate: candidate,
        retained: [BrokerRetainedWindowReference(identity: candidate)],
        primary: primary,
        inventory: BrokerWindowInventory([candidate]),
        factory: BrokerAuxiliaryFactory(sources: [:])
      )
      let anchor = try await lease.captureAnchor()

      #expect(
        await capturedFailure {
          _ = try await lease.readWindowEvidence(
            for: self.request(anchor: anchor, phase: .baseline)
          )
        } == mutation.expectedFailure,
        "mutation: \(mutation)"
      )
    }
  }

  @Test func callbackReplayAfterAcceptedDeliveryFailsClosed() async throws {
    let candidate = identity(20)
    let primary = BrokerScriptedDeliverySource(
      identity: candidate,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      current: delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1),
      steps: [
        .delivery(delivery(candidate, sequence: 11, callback: 130, display: 125, luminance: 2)),
        .delivery(
          delivery(
            candidate,
            status: .idle,
            sequence: 12,
            callback: 130,
            display: 125,
            luminance: 2
          )
        ),
      ]
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [BrokerRetainedWindowReference(identity: candidate)],
      primary: primary,
      inventory: BrokerWindowInventory([candidate]),
      factory: BrokerAuxiliaryFactory(sources: [:])
    )
    let anchor = try await lease.captureAnchor()
    _ = try await lease.readWindowEvidence(
      for: request(anchor: anchor, phase: .baseline, minimum: 110, started: 120)
    )

    #expect(
      await capturedFailure {
        _ = try await lease.readWindowEvidence(
          for: self.request(anchor: anchor, phase: .baseline, minimum: 110, started: 120)
        )
      } == .deliveryCallbackNotIncreasing
    )
  }

  @Test func hiddenCandidateIsRepresentedOnlyAsOffscreenNilEvidence() async throws {
    let candidate = identity(20)
    let other = identity(21)
    let primary = primarySource(candidate)
    let auxiliary = BrokerScriptedDeliverySource(
      identity: other,
      streamMemberToken: "other-member",
      continuityToken: "other-continuity",
      steps: [.delivery(delivery(other, sequence: 1, callback: 130, display: 125, luminance: 2))]
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [
        BrokerRetainedWindowReference(identity: candidate),
        BrokerRetainedWindowReference(identity: other),
      ],
      primary: primary,
      inventory: BrokerWindowInventory([other]),
      factory: BrokerAuxiliaryFactory(sources: [21: auxiliary])
    )
    let anchor = try await lease.captureAnchor()

    let snapshot = try await lease.readWindowEvidence(
      for: request(
        anchor: anchor,
        phase: .visibilityHidden,
        nonce: 41,
        minimum: 110,
        started: 120
      )
    )
    let candidateEvidence = try #require(snapshot.windows.first)

    #expect(candidateEvidence.identity.windowID == 20)
    #expect(!candidateEvidence.isOnScreen)
    #expect(candidateEvidence.fingerprint == nil)
    #expect(candidateEvidence.displayTime == nil)
    #expect(candidateEvidence.deliveryProvenance == nil)
    #expect(snapshot.candidateDisplayTime == nil)
    #expect(await primary.nextCount == 0)
  }

  @Test func stopIsBoundedAndStopsEveryStartedExactSource() async throws {
    let candidate = identity(20)
    let other = identity(21)
    let stopGate = BrokerStopGate()
    let primary = BrokerScriptedDeliverySource(
      identity: candidate,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      current: delivery(candidate, sequence: 10, callback: 100, display: 90, luminance: 1),
      steps: [
        .delivery(
          delivery(candidate, status: .idle, sequence: 11, callback: 130, display: 90, luminance: 1)
        )
      ],
      stopGate: stopGate
    )
    let auxiliary = BrokerScriptedDeliverySource(
      identity: other,
      streamMemberToken: "other-member",
      continuityToken: "other-continuity",
      steps: [.delivery(delivery(other, sequence: 1, callback: 130, display: 125, luminance: 2))],
      stopGate: stopGate
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [
        BrokerRetainedWindowReference(identity: candidate),
        BrokerRetainedWindowReference(identity: other),
      ],
      primary: primary,
      inventory: BrokerWindowInventory([candidate, other]),
      factory: BrokerAuxiliaryFactory(sources: [21: auxiliary]),
      cleanupDeadline: BrokerImmediateCleanupDeadline()
    )
    let anchor = try await lease.captureAnchor()
    _ = try await lease.readWindowEvidence(for: request(anchor: anchor, phase: .baseline))

    await lease.stop()
    for _ in 0..<10 { await Task.yield() }

    #expect(await primary.stopCount == 1)
    #expect(await auxiliary.stopCount == 1)
    #expect(
      await capturedFailure {
        _ = try await lease.readWindowEvidence(
          for: self.request(anchor: anchor, phase: .baseline, minimum: 140, started: 150)
        )
      } == .inactiveLease
    )
    await stopGate.release()
  }

  @Test func primaryRecorderRetainsItsExactStopActionPastTheLeaseDeadline() async throws {
    let candidate = identity(20)
    let recorder = PowerPointManagedSlideShowRoleCaptureDeliveryBuffer(
      identity: candidate,
      captureOperationID: operationID,
      captureGeneration: generation,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity"
    )
    let probe = BrokerStopActionProbe()
    try recorder.installStopAction { await probe.run() }
    let lease = try PowerPointManagedSlideShowRoleCaptureEvidenceLease(
      captureOperationID: operationID,
      captureGeneration: generation,
      candidateIdentity: candidate,
      retainedWindows: [BrokerRetainedWindowReference(identity: candidate)],
      primarySource: recorder,
      inventoryReader: BrokerWindowInventory([candidate]),
      auxiliaryFactory: BrokerAuxiliaryFactory(sources: [:]),
      cleanupDeadline: BrokerImmediateCleanupDeadline()
    )

    await lease.stop()
    for _ in 0..<10 { await Task.yield() }

    #expect(await probe.runCount == 1)
    await probe.release()
  }

  @Test func brokerJoinsEchoedExactObjectStateAndExactStreamEvidence() async throws {
    let candidate = identity(20)
    let primary = BrokerScriptedDeliverySource(
      identity: candidate,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      current: delivery(candidate, sequence: 10, callback: 90, display: 80, luminance: 1),
      steps: [
        .delivery(delivery(candidate, sequence: 11, callback: 160, display: 150, luminance: 3))
      ]
    )
    let lease = try makeLease(
      candidate: candidate,
      retained: [BrokerRetainedWindowReference(identity: candidate)],
      primary: primary,
      inventory: BrokerWindowInventory([candidate]),
      factory: BrokerAuxiliaryFactory(sources: [:])
    )
    let anchor = try await lease.captureAnchor()
    let semantic = BrokerSemanticReader(acquiredMachAbsoluteTime: 130)
    let broker = PowerPointManagedSlideShowRoleCaptureEvidenceBroker(
      lease: lease,
      semanticReader: semantic,
      machClock: BrokerMachClock([120, 140, 170]),
      semanticRequestTokenFactory: { "semantic-fresh" }
    )

    let result = try await broker.readFreshEvidence(
      request(
        anchor: anchor,
        phase: .pixelBlack,
        nonce: 41,
        minimum: 100,
        started: 110
      )
    )

    #expect(result.freshRequestToken == "fresh")
    #expect(result.observation.semanticState.currentViewState == .blackScreen)
    #expect(result.observation.evidenceObservedMachAbsoluteTime == 170)
    #expect(result.observation.candidateDisplayTime == 150)
    #expect((await semantic.requests).map(\.slideShowObjectToken) == ["object"])
  }

  private func makeLease(
    candidate: PowerPointWindowIdentity,
    retained: [any PowerPointManagedSlideShowRoleRetainedWindowReference],
    primary: any PowerPointManagedSlideShowRoleCaptureDeliverySource,
    inventory: any PowerPointManagedSlideShowRoleWindowInventoryReading,
    factory: BrokerAuxiliaryFactory,
    retainedWindowSnapshotReader:
      (any PowerPointManagedSlideShowRoleRetainedWindowSnapshotReading)? = nil,
    cleanupDeadline: any PowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadlineWaiting =
      BrokerImmediateCleanupDeadline()
  ) throws -> PowerPointManagedSlideShowRoleCaptureEvidenceLease {
    try PowerPointManagedSlideShowRoleCaptureEvidenceLease(
      captureOperationID: operationID,
      captureGeneration: generation,
      candidateIdentity: candidate,
      retainedWindows: retained,
      primarySource: primary,
      inventoryReader: inventory,
      auxiliaryFactory: factory,
      retainedWindowSnapshotReader: retainedWindowSnapshotReader,
      cleanupDeadline: cleanupDeadline
    )
  }

  private func request(
    anchor: ManagedSlideShowRoleChallengeCaptureAnchor,
    phase: ManagedSlideShowRoleChallengePhase,
    nonce: UInt64 = 40,
    minimum: UInt64 = 110,
    started: UInt64 = 120
  ) -> PowerPointManagedSlideShowRoleFreshEvidenceRequest {
    PowerPointManagedSlideShowRoleFreshEvidenceRequest(
      bindingSessionToken: "session",
      slideShowObjectToken: "object",
      processIdentifier: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
      candidateWindowIdentity: managedIdentity(20),
      captureOperationID: operationID.rawValue,
      captureGeneration: generation,
      captureAnchor: anchor,
      phase: phase,
      nonce: nonce,
      minimumDisplayTimeExclusive: minimum,
      requestStartedMachAbsoluteTime: started,
      freshRequestToken: "fresh"
    )
  }

  private func primarySource(_ identity: PowerPointWindowIdentity) -> BrokerScriptedDeliverySource {
    BrokerScriptedDeliverySource(
      identity: identity,
      streamMemberToken: "candidate-member",
      continuityToken: "candidate-continuity",
      current: delivery(identity, sequence: 10, callback: 100, display: 90, luminance: 1),
      steps: [
        .delivery(
          delivery(identity, status: .idle, sequence: 11, callback: 130, display: 90, luminance: 1)
        )
      ]
    )
  }

  private func delivery(
    _ identity: PowerPointWindowIdentity,
    status: ManagedSlideShowRoleWindowDeliveryStatus = .generated,
    sequence: UInt64,
    callback: UInt64,
    display: UInt64,
    luminance: UInt8,
    mutation: BrokerDeliveryMutation? = nil,
    streamMemberToken: String? = nil,
    continuityToken: String? = nil
  ) -> PowerPointManagedSlideShowRoleCaptureDelivery {
    PowerPointManagedSlideShowRoleCaptureDelivery(
      identity: mutation == .missingIdentity ? nil : identity,
      status: mutation == .blankStatus ? .blank : status,
      captureOperationID: mutation == .operationDrift
        ? CaptureOperationID(rawValue: 8) : operationID,
      captureGeneration: mutation == .generationDrift ? generation + 1 : generation,
      streamMemberToken: mutation == .streamDrift
        ? "drift-member"
        : streamMemberToken ?? (identity.windowID == 20 ? "candidate-member" : "other-member"),
      continuityToken: mutation == .continuityDrift
        ? "drift-continuity"
        : continuityToken
          ?? (identity.windowID == 20 ? "candidate-continuity" : "other-continuity"),
      deliverySequence: mutation == .sequenceReplay ? 10 : sequence,
      callbackMachAbsoluteTime: mutation == .callbackReplay ? 100 : callback,
      displayTime: display,
      fingerprint: FrameFingerprint(
        sampleColumns: 1,
        sampleRows: 1,
        luminance: [luminance]
      )
    )
  }

  private func identity(_ windowID: CGWindowID) -> PowerPointWindowIdentity {
    PowerPointWindowIdentity(
      windowID: windowID,
      ownerProcessID: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )!
  }

  private func managedIdentity(_ windowID: Int) -> ManagedSlideShowWindowIdentity {
    ManagedSlideShowWindowIdentity(
      windowID: windowID,
      processIdentifier: 700,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )
  }

  private func capturedFailure(
    _ operation: () async throws -> Void
  ) async -> PowerPointManagedSlideShowRoleCaptureEvidenceFailure? {
    do {
      try await operation()
      return nil
    } catch let failure as PowerPointManagedSlideShowRoleCaptureEvidenceFailure {
      return failure
    } catch {
      return nil
    }
  }
}

private enum BrokerDeliveryMutation: CaseIterable, Equatable, Sendable {
  case gap
  case missingIdentity
  case blankStatus
  case operationDrift
  case generationDrift
  case streamDrift
  case continuityDrift
  case sequenceReplay
  case callbackReplay

  func steps(
    delivery: PowerPointManagedSlideShowRoleCaptureDelivery
  ) -> [BrokerDeliveryStep] {
    self == .gap ? [.failure(.deliveryUnavailable)] : [.delivery(delivery)]
  }

  var expectedFailure: PowerPointManagedSlideShowRoleCaptureEvidenceFailure {
    switch self {
    case .gap: .deliveryUnavailable
    case .missingIdentity: .malformedDelivery
    case .blankStatus: .unsupportedDeliveryStatus
    case .operationDrift: .deliveryCaptureOperationMismatch
    case .generationDrift: .deliveryCaptureGenerationMismatch
    case .streamDrift: .deliveryStreamMemberMismatch
    case .continuityDrift: .deliveryContinuityMismatch
    case .sequenceReplay: .deliverySequenceNotIncreasing
    case .callbackReplay: .deliveryCallbackOutOfBounds
    }
  }
}

private final class BrokerRetainedWindowReference:
  PowerPointManagedSlideShowRoleRetainedWindowReference, @unchecked Sendable
{
  let identity: PowerPointWindowIdentity
  let windowGeometry: ManagedSlideShowWindowGeometry?

  init(
    identity: PowerPointWindowIdentity,
    windowGeometry: ManagedSlideShowWindowGeometry? = nil
  ) {
    self.identity = identity
    self.windowGeometry = windowGeometry
  }
}

private func brokerSurfaceAttachments(
  contentRect: CGRect,
  scaleFactor: Double,
  contentScale: Double
) -> [SCStreamFrameInfo: Any] {
  [
    .contentRect: NSValue(rect: contentRect),
    .scaleFactor: NSNumber(value: scaleFactor),
    .contentScale: NSNumber(value: contentScale),
  ]
}

private func brokerPixelBuffer(
  width: Int,
  height: Int,
  whiteRegion: CGRect
) -> CVPixelBuffer? {
  var pixelBuffer: CVPixelBuffer?
  guard
    CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      nil,
      &pixelBuffer
    ) == kCVReturnSuccess,
    let pixelBuffer
  else { return nil }
  CVPixelBufferLockBaseAddress(pixelBuffer, [])
  defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
  guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
  let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
  let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
  for y in 0..<height {
    for x in 0..<width {
      let value: UInt8 =
        whiteRegion.contains(CGPoint(x: CGFloat(x), y: CGFloat(y))) ? 255 : 0
      let offset = y * bytesPerRow + x * 4
      bytes[offset] = value
      bytes[offset + 1] = value
      bytes[offset + 2] = value
      bytes[offset + 3] = 255
    }
  }
  return pixelBuffer
}

private enum BrokerDeliveryStep: Sendable {
  case delivery(PowerPointManagedSlideShowRoleCaptureDelivery)
  case failure(PowerPointManagedSlideShowRoleCaptureEvidenceFailure)
}

private actor BrokerScriptedDeliverySource: PowerPointManagedSlideShowRoleCaptureDeliverySource {
  nonisolated let retainedIdentity: PowerPointWindowIdentity
  nonisolated let streamMemberToken: String
  nonisolated let continuityToken: String

  private let current: PowerPointManagedSlideShowRoleCaptureDelivery?
  private var steps: [BrokerDeliveryStep]
  private let stopGate: BrokerStopGate?
  private let nextGate: BrokerNextDeliveryGate?
  private(set) var startCount = 0
  private(set) var nextCount = 0
  private(set) var stopCount = 0
  private(set) var requests: [PowerPointManagedSlideShowRoleCaptureDeliveryRequest] = []

  init(
    identity: PowerPointWindowIdentity,
    streamMemberToken: String,
    continuityToken: String,
    current: PowerPointManagedSlideShowRoleCaptureDelivery? = nil,
    steps: [BrokerDeliveryStep],
    stopGate: BrokerStopGate? = nil,
    nextGate: BrokerNextDeliveryGate? = nil
  ) {
    retainedIdentity = identity
    self.streamMemberToken = streamMemberToken
    self.continuityToken = continuityToken
    self.current = current
    self.steps = steps
    self.stopGate = stopGate
    self.nextGate = nextGate
  }

  func start() async throws {
    startCount += 1
  }

  func currentDelivery() async -> PowerPointManagedSlideShowRoleCaptureDelivery? {
    current
  }

  func nextDelivery(
    after request: PowerPointManagedSlideShowRoleCaptureDeliveryRequest
  ) async throws -> PowerPointManagedSlideShowRoleCaptureDelivery {
    nextCount += 1
    requests.append(request)
    if let nextGate { await nextGate.wait() }
    guard !steps.isEmpty else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.deliveryUnavailable
    }
    switch steps.removeFirst() {
    case .delivery(let delivery): return delivery
    case .failure(let failure): throw failure
    }
  }

  func stop() async {
    stopCount += 1
    if let stopGate { await stopGate.wait() }
  }
}

private actor BrokerNextDeliveryGate {
  private var released = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !released else { return }
    await withCheckedContinuation { continuations.append($0) }
  }

  func release() {
    released = true
    let pending = continuations
    continuations.removeAll()
    for continuation in pending { continuation.resume() }
  }
}

private actor BrokerRetainedWindowSnapshotReader:
  PowerPointManagedSlideShowRoleRetainedWindowSnapshotReading
{
  private let windows: [any PowerPointManagedSlideShowRoleRetainedWindowReference]
  private let gate: BrokerNextDeliveryGate?
  private(set) var readCount = 0

  init(
    windows: [any PowerPointManagedSlideShowRoleRetainedWindowReference],
    gate: BrokerNextDeliveryGate? = nil
  ) {
    self.windows = windows
    self.gate = gate
  }

  func currentRetainedPowerPointWindows(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [any PowerPointManagedSlideShowRoleRetainedWindowReference] {
    readCount += 1
    if let gate { await gate.wait() }
    return windows
  }
}

private actor BrokerWindowInventory: PowerPointManagedSlideShowRoleWindowInventoryReading {
  private let identities: [PowerPointWindowIdentity]
  private let geometries: [Int: ManagedSlideShowWindowGeometry]

  init(
    _ identities: [PowerPointWindowIdentity],
    geometries: [Int: ManagedSlideShowWindowGeometry] = [:]
  ) {
    self.identities = identities
    self.geometries = geometries
  }

  func currentPowerPointWindowIdentities(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [PowerPointWindowIdentity] {
    identities
  }

  func currentPowerPointWindowInventory(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [PowerPointManagedSlideShowRoleWindowInventoryEntry] {
    identities.map {
      PowerPointManagedSlideShowRoleWindowInventoryEntry(
        identity: $0,
        windowGeometry: geometries[Int($0.windowID)]
      )
    }
  }
}

private actor BrokerMutableWindowInventory:
  PowerPointManagedSlideShowRoleWindowInventoryReading
{
  private var identities: [PowerPointWindowIdentity]
  private var geometries: [Int: ManagedSlideShowWindowGeometry]

  init(
    _ identities: [PowerPointWindowIdentity],
    geometries: [Int: ManagedSlideShowWindowGeometry] = [:]
  ) {
    self.identities = identities
    self.geometries = geometries
  }

  func replace(
    with identities: [PowerPointWindowIdentity],
    geometries: [Int: ManagedSlideShowWindowGeometry] = [:]
  ) {
    self.identities = identities
    self.geometries = geometries
  }

  func currentPowerPointWindowIdentities(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [PowerPointWindowIdentity] {
    identities
  }

  func currentPowerPointWindowInventory(
    processIdentifier: pid_t,
    bundleIdentifier: String
  ) async throws -> [PowerPointManagedSlideShowRoleWindowInventoryEntry] {
    identities.map {
      PowerPointManagedSlideShowRoleWindowInventoryEntry(
        identity: $0,
        windowGeometry: geometries[Int($0.windowID)]
      )
    }
  }
}

private final class BrokerAuxiliaryFactory:
  PowerPointManagedSlideShowRoleAuxiliaryStreamFactory, @unchecked Sendable
{
  private let lock = NSLock()
  private let sources: [Int: BrokerScriptedDeliverySource]
  private var referenceIDs: [ObjectIdentifier] = []

  init(sources: [Int: BrokerScriptedDeliverySource]) {
    self.sources = sources
  }

  var requestedReferenceIDs: [ObjectIdentifier] {
    lock.withLock { referenceIDs }
  }

  func makeSource(
    for retainedWindow: any PowerPointManagedSlideShowRoleRetainedWindowReference,
    captureOperationID: CaptureOperationID,
    captureGeneration: UInt64
  ) throws -> any PowerPointManagedSlideShowRoleCaptureDeliverySource {
    lock.withLock { referenceIDs.append(ObjectIdentifier(retainedWindow)) }
    guard let source = sources[Int(retainedWindow.identity.windowID)] else {
      throw PowerPointManagedSlideShowRoleCaptureEvidenceFailure.auxiliaryStreamUnavailable
    }
    return source
  }
}

private struct BrokerImmediateCleanupDeadline:
  PowerPointManagedSlideShowRoleCaptureEvidenceCleanupDeadlineWaiting
{
  func waitForDeadline() async {}
}

private actor BrokerStopGate {
  private var released = false
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func wait() async {
    guard !released else { return }
    await withCheckedContinuation { continuations.append($0) }
  }

  func release() {
    released = true
    let pending = continuations
    continuations.removeAll()
    for continuation in pending { continuation.resume() }
  }
}

private actor BrokerStopActionProbe {
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  private(set) var runCount = 0

  func run() async {
    runCount += 1
    guard !released else { return }
    await withCheckedContinuation { continuation = $0 }
  }

  func release() {
    released = true
    continuation?.resume()
    continuation = nil
  }
}

private actor BrokerMachClock: ManagedSlideShowBindingMachClock {
  private var times: [UInt64]

  init(_ times: [UInt64]) {
    self.times = times
  }

  func now() async -> UInt64 {
    guard !times.isEmpty else { return 0 }
    return times.removeFirst()
  }
}

private actor BrokerSemanticReader: PowerPointManagedSlideShowRoleSemanticStateReadingClient {
  private let acquiredMachAbsoluteTime: UInt64
  private(set) var requests: [PowerPointManagedSlideShowRoleSemanticStateRequest] = []

  init(acquiredMachAbsoluteTime: UInt64) {
    self.acquiredMachAbsoluteTime = acquiredMachAbsoluteTime
  }

  func readExactRoleSemanticState(
    _ request: PowerPointManagedSlideShowRoleSemanticStateRequest
  ) async throws -> PowerPointManagedSlideShowRoleSemanticStateReading {
    requests.append(request)
    return PowerPointManagedSlideShowRoleSemanticStateReading(
      request: request,
      acquiredMachAbsoluteTime: acquiredMachAbsoluteTime,
      semanticState: ManagedSlideShowRoleSemanticState(
        slideID: 10,
        slideIndex: 2,
        currentViewState: .blackScreen,
        presentationSaved: true
      )
    )
  }
}
