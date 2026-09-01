import Combine
import CoreGraphics
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct AppContentChangeIntegrationTests {
  @Test func separatesInitialStabilitySparseAndSignificantVisualUpdates() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()

    await model.startWindowCapture()
    #expect(model.captureStatus == .capturing)

    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }
    try await analyzer.waitForAnalysisCount(1)

    #expect(model.contentRevisionCount == 0)
    #expect(model.slideChangeCount == 0)

    let sparseRevision = changingCells(
      in: denseBaseline,
      indices: Array(0..<30)
    )
    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: sparseRevision
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 1 }
    try await analyzer.waitForAnalysisCount(2)

    #expect(model.stableFrameCount == 1)
    #expect(model.slideChangeCount == 0)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 4_000)
    #expect(model.latestContentRevisionEvent?.confirmedMachAbsoluteTime == 6_000)
    #expect(model.latestContentRevisionEvent?.source == .continuousDenseNew)

    let significantUpdateCoarse = coarseFingerprint(luminance: 107)
    let significantUpdateDense = changingCells(
      in: denseBaseline,
      indices: Array(0..<1_000)
    )
    for sequenceNumber in 7...9 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: significantUpdateCoarse,
          contentFingerprint: significantUpdateDense
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 2 }
    try await analyzer.waitForAnalysisCount(3)

    #expect(model.stableFrameCount == 2)
    #expect(model.slideChangeCount == 0)
    #expect(model.latestSlideAnalysis?.strokeCandidateRegions.count == 1)
    #expect(model.latestContentRevisionEvent?.ordinal == 2)
    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 7_000)
    #expect(model.latestContentRevisionEvent?.confirmedMachAbsoluteTime == 9_000)
    #expect(model.latestContentRevisionEvent?.source == .coarseSignificantVisualChange)

    await capture.emit(
      frame(
        sequenceNumber: 10,
        image: image,
        coarseFingerprint: significantUpdateCoarse,
        contentFingerprint: significantUpdateDense
      )
    )
    try await waitUntil { model.capturedFrameCount == 10 }
    #expect(model.contentRevisionCount == 2)

    let followingSparseUpdate = changingCells(
      in: significantUpdateDense,
      indices: Array(1_000..<1_030)
    )
    for sequenceNumber in 11...13 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: significantUpdateCoarse,
          contentFingerprint: followingSparseUpdate
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 3 }
    try await analyzer.waitForAnalysisCount(4)
    #expect(model.slideChangeCount == 0)
    #expect(model.latestContentRevisionEvent?.ordinal == 3)
    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 11_000)
    #expect(model.latestContentRevisionEvent?.confirmedMachAbsoluteTime == 13_000)
    #expect(model.latestContentRevisionEvent?.source == .continuousDenseNew)

    let snapshot = RuntimeVerificationSnapshotProjector.makeSnapshot(
      from: model,
      timestamp: Date(timeIntervalSince1970: 0),
      elapsedMilliseconds: 1_000,
      screenRecordingPermission: .authorized
    )
    #expect(snapshot.stableFrameCount == 2)
    #expect(snapshot.slideChangeCount == 0)
    #expect(snapshot.contentRevisionCount == 3)
    #expect(snapshot.strokeCandidateRegionCount == 1)

    await model.stopWindowCapture()
  }

  @Test func countsACoarseStableRevisionAsStableWithoutInflatingSlideCount() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let denseBaseline = denseFingerprint()

    await model.startWindowCapture()

    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint(luminance: 100),
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }
    try await analyzer.waitForAnalysisCount(1)

    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint(luminance: 104),
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 1 }
    try await analyzer.waitForAnalysisCount(2)

    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: image,
        coarseFingerprint: coarseFingerprint(luminance: 104),
        contentFingerprint: denseBaseline
      )
    )
    try await waitUntil { model.capturedFrameCount == 7 }

    #expect(model.stableFrameCount == 2)
    #expect(model.slideChangeCount == 0)
    #expect(model.contentRevisionCount == 1)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 4_000)
    #expect(model.latestContentRevisionEvent?.confirmedMachAbsoluteTime == 6_000)
    #expect(model.latestContentRevisionEvent?.source == .coarseStable)

    await model.stopWindowCapture()
  }

  @Test func recordsDenseIdleRepeatAsItsOwnRevisionSource() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let idleRevision = changingCells(in: denseBaseline, indices: Array(0..<30))

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }

    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: idleRevision,
          deliveryKind: .idleRepeat,
          displayTime: 4_000
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 1 }

    #expect(model.newCapturedFrameCount == 3)
    #expect(model.repeatedCapturedFrameCount == 3)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 4_000)
    #expect(model.latestContentRevisionEvent?.confirmedMachAbsoluteTime == 4_000)
    #expect(model.latestContentRevisionEvent?.source == .continuousDenseIdleRepeat)

    await model.stopWindowCapture()
  }

  @Test func denseCandidateReplacementMovesTheEvidenceIntervalStartForward() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let abandonedCandidate = changingCells(in: denseBaseline, indices: Array(0..<30))
    let confirmedCandidate = changingCells(in: denseBaseline, indices: Array(30..<60))

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }

    await capture.emit(
      frame(
        sequenceNumber: 4,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: abandonedCandidate
      )
    )
    for sequenceNumber in 5...7 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: confirmedCandidate
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 1 }

    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 5_000)
    #expect(model.latestContentRevisionEvent?.confirmedMachAbsoluteTime == 7_000)
    #expect(model.latestContentRevisionEvent?.source == .continuousDenseNew)

    await model.stopWindowCapture()
  }

  @Test func invalidSourceTimesNeverCarryAnOlderRevisionEventForward() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let firstRevision = changingCells(in: denseBaseline, indices: Array(0..<30))
    let secondRevision = changingCells(in: denseBaseline, indices: Array(30..<60))

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }
    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: firstRevision
        )
      )
    }
    try await waitUntil { model.latestContentRevisionEvent?.ordinal == 1 }

    for sequenceNumber in 7...9 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: secondRevision,
          displayTime: 0
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 2 }

    #expect(model.latestContentRevisionEvent == nil)
    let snapshot = RuntimeVerificationSnapshotProjector.makeSnapshot(
      from: model,
      timestamp: Date(timeIntervalSince1970: 0),
      elapsedMilliseconds: 1_000,
      screenRecordingPermission: .authorized
    )
    #expect(snapshot.contentRevisionCount == 0)
    #expect(snapshot.latestContentRevisionEvent == nil)

    await model.stopWindowCapture()
  }

  @Test func discardsDetailedPendingChangeDuringSignificantVisualUpdateAndRebases()
    async throws
  {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let significantUpdateDense = changingCells(
      in: denseBaseline,
      indices: Array(0..<1_000)
    )

    await model.startWindowCapture()

    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }

    let pendingDetailedRevision = changingCells(
      in: denseBaseline,
      indices: Array(0..<30)
    )
    for sequenceNumber in 4...5 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: pendingDetailedRevision
        )
      )
    }

    for sequenceNumber in 6...8 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint(luminance: 107),
          contentFingerprint: significantUpdateDense
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 1 }

    for sequenceNumber in 9...11 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint(luminance: 107),
          contentFingerprint: significantUpdateDense
        )
      )
    }
    try await waitUntil { model.capturedFrameCount == 11 }

    #expect(model.stableFrameCount == 2)
    #expect(model.slideChangeCount == 0)
    #expect(model.contentRevisionCount == 1)
    #expect(await analyzer.currentAnalysisCount() == 2)

    await model.stopWindowCapture()
  }

  @Test func stoppingAndRestartingRequiresANewContentBaseline() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let pendingDetailedRevision = changingCells(
      in: denseBaseline,
      indices: Array(0..<30)
    )

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }

    for sequenceNumber in 4...5 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: pendingDetailedRevision
        )
      )
    }
    await model.stopWindowCapture()

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: pendingDetailedRevision
        )
      )
    }
    try await waitUntil {
      model.capturedFrameCount == 3 && model.stableFrameCount == 1
    }

    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)
    #expect(model.slideChangeCount == 0)

    await model.stopWindowCapture()
  }

  @Test func newCaptureResetsRevisionCountAndEventTogether() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let denseRevision = changingCells(in: denseBaseline, indices: Array(0..<30))

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }
    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseRevision
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 1 }
    #expect(model.latestContentRevisionEvent?.ordinal == 1)

    await model.stopWindowCapture()
    await model.startWindowCapture()
    try await waitUntil { model.captureStatus == .capturing }

    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)

    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseRevision
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)

    await model.stopWindowCapture()
  }

  @Test func ignoresDuplicateAndOutOfOrderFramesWithoutAdvancingDetectorState() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let sparseRevision = changingCells(
      in: denseBaseline,
      indices: Array(0..<30)
    )

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }

    await capture.emit(
      frame(
        sequenceNumber: 5,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: sparseRevision
      )
    )
    try await waitUntil { model.capturedFrameCount == 4 }

    await capture.emit(
      frame(
        sequenceNumber: 5,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: sparseRevision
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 2,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: sparseRevision
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: sparseRevision
      )
    )
    try await waitUntil { model.capturedFrameCount == 5 }

    #expect(model.newCapturedFrameCount == 5)
    #expect(
      model.capturedFrameCount
        == model.newCapturedFrameCount + model.repeatedCapturedFrameCount
    )
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)

    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: sparseRevision
      )
    )
    try await waitUntil { model.contentRevisionCount == 1 }

    #expect(model.capturedFrameCount == 6)
    #expect(model.newCapturedFrameCount == 6)
    #expect(
      model.capturedFrameCount
        == model.newCapturedFrameCount + model.repeatedCapturedFrameCount
    )
    #expect(model.stableFrameCount == 1)
    #expect(model.slideChangeCount == 0)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.source == .continuousDenseNew)

    await model.stopWindowCapture()
  }

  @Test func captureErrorAllowsANewSessionToRestartItsSequence() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()

    await model.startWindowCapture()
    for sequenceNumber in 10...12 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }

    await capture.emitError("controlled capture error")
    try await waitUntil { model.captureStatus == .error("controlled capture error") }

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil {
      model.capturedFrameCount == 3 && model.stableFrameCount == 1
    }

    #expect(model.captureStatus == .capturing)
    #expect(model.newCapturedFrameCount == 3)
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)

    await model.stopWindowCapture()
  }

  @Test func discardsPendingDetailedChangeWhenCoarseTransitionReturnsToOriginalSlide()
    async throws
  {
    let capture = FrameEmittingWindowCapture()
    let analyzer = RecordingSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let pendingDetailedRevision = changingCells(
      in: denseBaseline,
      indices: Array(0..<30)
    )

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }

    for sequenceNumber in 4...5 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: pendingDetailedRevision
        )
      )
    }

    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: image,
        coarseFingerprint: coarseFingerprint(luminance: 107),
        contentFingerprint: pendingDetailedRevision
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 7,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: pendingDetailedRevision
      )
    )
    try await waitUntil { model.capturedFrameCount == 7 }

    #expect(model.contentRevisionCount == 0)
    #expect(model.slideChangeCount == 0)

    for sequenceNumber in 8...9 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: pendingDetailedRevision
        )
      )
    }
    try await waitUntil { model.contentRevisionCount == 1 }

    #expect(model.stableFrameCount == 1)
    #expect(model.slideChangeCount == 0)

    await model.stopWindowCapture()
  }

  @Test func coarseCandidateClosesProposalsUntilReturnedBaselineIsReanalyzed() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = ControllableSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()

    try await establishReadyAnalysis(
      model: model,
      capture: capture,
      analyzer: analyzer,
      image: image,
      coarseFingerprint: coarseBaseline,
      contentFingerprint: denseBaseline
    )

    await capture.emit(
      frame(
        sequenceNumber: 4,
        image: image,
        coarseFingerprint: coarseFingerprint(luminance: 107),
        contentFingerprint: denseBaseline
      )
    )
    try await waitUntil { model.capturedFrameCount == 4 }
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)

    model.receive(proposalDefinition("Candidate means content that is not yet stable."))
    #expect(model.boardScene.elements.isEmpty)

    await capture.emit(
      frame(
        sequenceNumber: 5,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: denseBaseline
      )
    )
    try await analyzer.waitForInvocation(sequenceNumber: 5)
    #expect(model.slideAnalysisStatus == .analyzing)
    model.receive(proposalDefinition("Recovery means returning to the old baseline."))
    #expect(model.boardScene.elements.isEmpty)

    try await analyzer.succeed(
      sequenceNumber: 5,
      title: "revalidated baseline",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    receiveConfirmedProposal(
      "Freshness means using the reanalyzed current frame.",
      on: model
    )
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func denseCandidateAndConfirmedChangeKeepProposalsClosedUntilNewAnalysisCompletes()
    async throws
  {
    let capture = FrameEmittingWindowCapture()
    let analyzer = ControllableSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let denseRevision = changingCells(in: denseBaseline, indices: Array(0..<30))

    try await establishReadyAnalysis(
      model: model,
      capture: capture,
      analyzer: analyzer,
      image: image,
      coarseFingerprint: coarseBaseline,
      contentFingerprint: denseBaseline
    )

    await capture.emit(
      frame(
        sequenceNumber: 4,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: denseRevision
      )
    )
    try await waitUntil { model.capturedFrameCount == 4 }
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)
    model.receive(proposalDefinition("Pending ink means occupancy is not yet current."))
    #expect(model.boardScene.elements.isEmpty)

    for sequenceNumber in 5...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseRevision
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 6)
    #expect(model.contentRevisionCount == 1)
    #expect(model.slideAnalysisStatus == .analyzing)
    model.receive(proposalDefinition("Confirmed ink means analysis is still required."))
    #expect(model.boardScene.elements.isEmpty)

    try await analyzer.succeed(
      sequenceNumber: 6,
      title: "new dense revision",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    receiveConfirmedProposal("Current occupancy means proposals may resume.", on: model)
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func missingAndInvalidDenseFingerprintsCloseProposalsUntilAValidFrameIsReanalyzed()
    async throws
  {
    let capture = FrameEmittingWindowCapture()
    let analyzer = ControllableSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let wrongSizedDenseFingerprint = ContentFingerprint(
      sampleColumns: 80,
      sampleRows: 45,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 80 * 45
      )
    )

    try await establishReadyAnalysis(
      model: model,
      capture: capture,
      analyzer: analyzer,
      image: image,
      coarseFingerprint: coarseBaseline,
      contentFingerprint: denseBaseline
    )

    await capture.emit(
      frame(
        sequenceNumber: 4,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: nil
      )
    )
    try await waitUntil { model.capturedFrameCount == 4 }
    #expect(model.slideAnalysisStatus == .idle)
    model.receive(proposalDefinition("Missing evidence means proposals remain closed."))
    #expect(model.boardScene.elements.isEmpty)

    await capture.emit(
      frame(
        sequenceNumber: 5,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: wrongSizedDenseFingerprint
      )
    )
    try await waitUntil { model.capturedFrameCount == 5 }
    #expect(model.slideAnalysisStatus == .idle)
    model.receive(proposalDefinition("Invalid evidence means proposals remain closed."))
    #expect(model.boardScene.elements.isEmpty)

    await capture.emit(
      frame(
        sequenceNumber: 6,
        image: image,
        coarseFingerprint: coarseBaseline,
        contentFingerprint: denseBaseline
      )
    )
    try await analyzer.waitForInvocation(sequenceNumber: 6)
    #expect(model.slideAnalysisStatus == .analyzing)
    try await analyzer.succeed(
      sequenceNumber: 6,
      title: "valid dense baseline",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    receiveConfirmedProposal("Validated evidence means proposals may resume.", on: model)
    #expect(!model.boardScene.elements.isEmpty)

    model.boardScene = BoardScene(slideNumber: model.boardScene.slideNumber)
    let elementCountBeforeMissingConfirmedFrame = model.boardScene.elements.count
    let changedCoarseFingerprint = coarseFingerprint(luminance: 107)
    for sequenceNumber in 7...9 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: changedCoarseFingerprint,
          contentFingerprint: nil
        )
      )
    }
    try await waitUntil { model.capturedFrameCount == 9 }
    #expect(!(await analyzer.hasInvocation(sequenceNumber: 9)))
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)
    model.receive(proposalDefinition("Missing dense evidence closes confirmed coarse frames."))
    #expect(model.boardScene.elements.count == elementCountBeforeMissingConfirmedFrame)

    await model.stopWindowCapture()
  }

  @Test func currentAnalyzerCancellationSettlesButReplacedCancellationDoesNot() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = ControllableSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let sparseRevision = changingCells(
      in: denseBaseline,
      indices: Array(0..<30)
    )

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 3)

    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: sparseRevision
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 6)

    var observedStatuses: [AppModel.SlideAnalysisStatus] = []
    let statusSubscription = model.$slideAnalysisStatus.dropFirst().sink { status in
      observedStatuses.append(status)
    }
    try await analyzer.failWithCancellation(sequenceNumber: 3)
    await waitForMainActorQueueDrain()
    #expect(model.slideAnalysisStatus == .analyzing)
    #expect(observedStatuses.isEmpty)

    try await analyzer.failWithCancellation(sequenceNumber: 6)
    try await waitUntil { model.slideAnalysisStatus == .idle }
    await waitForMainActorQueueDrain()
    #expect(model.latestSlideAnalysis == nil)
    #expect(observedStatuses == [.idle])

    await model.stopWindowCapture()
    withExtendedLifetime(statusSubscription) {}
  }

  @Test func staleAnalysisCannotReplaceARevisionOrPublishAfterStop() async throws {
    let capture = FrameEmittingWindowCapture()
    let analyzer = ControllableSlideVisualAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let image = try #require(makeImage())
    let coarseBaseline = coarseFingerprint(luminance: 100)
    let denseBaseline = denseFingerprint()
    let firstRevision = changingCells(
      in: denseBaseline,
      indices: Array(0..<30)
    )
    let secondRevision = changingCells(
      in: firstRevision,
      indices: Array(30..<60)
    )

    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: denseBaseline
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 3)

    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: firstRevision
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 6)

    try await analyzer.succeed(sequenceNumber: 6, title: "revision B")
    try await waitUntil { model.latestSlideAnalysis?.title == "revision B" }

    var observedTitles: [String?] = []
    let analysisSubscription = model.$latestSlideAnalysis.dropFirst().sink { analysis in
      observedTitles.append(analysis?.title)
    }
    try await analyzer.succeed(sequenceNumber: 3, title: "stale A")
    await waitForMainActorQueueDrain()
    #expect(model.latestSlideAnalysis?.title == "revision B")
    #expect(model.slideAnalysisStatus == .ready)
    #expect(!observedTitles.contains("stale A"))

    for sequenceNumber in 7...9 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseBaseline,
          contentFingerprint: secondRevision
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 9)
    #expect(model.slideAnalysisStatus == .analyzing)

    await model.stopWindowCapture()
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)

    try await analyzer.succeed(sequenceNumber: 9, title: "stale after stop")
    await waitForMainActorQueueDrain()
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)
    #expect(!observedTitles.contains("stale after stop"))
    withExtendedLifetime(analysisSubscription) {}
  }

  private func makeModel(
    capture: FrameEmittingWindowCapture,
    analyzer: any SlideVisualAnalyzing
  ) -> AppModel {
    let permissionService = PermissionService(
      screenCaptureClient: ContentIntegrationAuthorizedPermissionClient()
    )
    let model = AppModel(
      permissionService: permissionService,
      windowCapture: capture,
      scanner: ContentIntegrationWindowScanner(),
      slideVisionAnalyzer: analyzer,
      slideCanvasConfirmationMode: .testOnlyUseFullCapturedFrame
    )
    model.powerPointWindows = [
      PowerPointWindowDescriptor(
        id: 42,
        title: "Synthetic content integration window",
        applicationName: "Microsoft PowerPoint",
        ownerProcessID: 700,
        bundleIdentifier: "com.microsoft.Powerpoint",
        frame: .zero
      )
    ]
    model.selectedPowerPointWindowID = 42
    return model
  }

  private func establishReadyAnalysis(
    model: AppModel,
    capture: FrameEmittingWindowCapture,
    analyzer: ControllableSlideVisualAnalyzer,
    image: CGImage,
    coarseFingerprint: FrameFingerprint,
    contentFingerprint: ContentFingerprint
  ) async throws {
    await model.startWindowCapture()
    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 3)
    try await analyzer.succeed(
      sequenceNumber: 3,
      title: "baseline",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
  }

  private func frame(
    sequenceNumber: UInt64,
    image: CGImage,
    coarseFingerprint: FrameFingerprint,
    contentFingerprint: ContentFingerprint?,
    deliveryKind: CapturedFrameDeliveryKind = .new,
    displayTime: UInt64? = nil
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: 42,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(timeIntervalSince1970: TimeInterval(sequenceNumber)),
      displayTime: displayTime ?? sequenceNumber * 1_000,
      deliveryKind: deliveryKind,
      image: image,
      fingerprint: coarseFingerprint,
      contentFingerprint: contentFingerprint
    )
  }

  private func coarseFingerprint(luminance: UInt8) -> FrameFingerprint {
    FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: luminance, count: 32 * 18)
    )
  }

  private func denseFingerprint() -> ContentFingerprint {
    ContentFingerprint(
      sampleColumns: 160,
      sampleRows: 90,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 160 * 90
      )
    )
  }

  private func changingCells(
    in fingerprint: ContentFingerprint,
    indices: [Int]
  ) -> ContentFingerprint {
    var cells = fingerprint.cells
    for index in indices {
      cells[index] = RGBContentCell(red: 190, green: 20, blue: 20)
    }
    return ContentFingerprint(
      sampleColumns: fingerprint.sampleColumns,
      sampleRows: fingerprint.sampleRows,
      cells: cells
    )
  }

  private func boardProposalOccupiedRegions() -> [NormalizedRect] {
    [NormalizedRect(x: 0.05, y: 0.05, width: 0.2, height: 0.15)]
  }

  private func proposalDefinition(_ text: String) -> TranscriptSegment {
    TranscriptSegment(
      text: text,
      startTime: 0,
      endTime: 5,
      language: .englishUS,
      confidence: 0.95,
      emphasis: 0.9
    )
  }

  private func receiveConfirmedProposal(_ text: String, on model: AppModel) {
    model.receive(proposalDefinition(text))
    model.receive(proposalDefinition(text))
  }

  private func makeImage() -> CGImage? {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
    return CGContext(
      data: nil,
      width: 2,
      height: 2,
      bitsPerComponent: 8,
      bytesPerRow: 8,
      space: colorSpace ?? CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()
  }

  private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool
  ) async throws {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    throw ContentIntegrationTestError.timedOut
  }

  private func waitForMainActorQueueDrain() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }
}

private enum ContentIntegrationTestError: Error {
  case timedOut
  case analysisTimedOut
}

private actor FrameEmittingWindowCapture: PowerPointWindowCapturing {
  private var frameHandler: CaptureFrameHandler?
  private var errorHandler: CaptureErrorHandler?

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    frameHandler = onFrame
    errorHandler = onError
  }

  func stop(operationID: CaptureOperationID) async {
    frameHandler = nil
    errorHandler = nil
  }

  func emit(_ frame: CapturedPowerPointFrame) {
    frameHandler?(frame)
  }

  func emitError(_ message: String) {
    errorHandler?(message)
  }
}

private actor RecordingSlideVisualAnalyzer: SlideVisualAnalyzing {
  private var analysisCount = 0

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    analysisCount += 1
    return SlideVisualAnalysis(
      strokeCandidateRegions: [
        NormalizedRect(x: 0.7, y: 0.2, width: 0.1, height: 0.05)
      ],
      occupiedRegions: [
        NormalizedRect(x: 0.69, y: 0.19, width: 0.12, height: 0.07)
      ]
    )
  }

  func waitForAnalysisCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if analysisCount >= expectedCount { return }
      await Task.yield()
    }
    throw ContentIntegrationTestError.analysisTimedOut
  }

  func currentAnalysisCount() -> Int {
    analysisCount
  }
}

private enum ControllableSlideVisualAnalyzerError: Error {
  case timedOutWaitingForInvocation(UInt64)
  case missingInvocation(UInt64)
}

private actor ControllableSlideVisualAnalyzer: SlideVisualAnalyzing {
  private var invokedSequenceNumbers: Set<UInt64> = []
  private var continuations: [UInt64: CheckedContinuation<SlideVisualAnalysis, any Error>] = [:]

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    invokedSequenceNumbers.insert(frame.sequenceNumber)
    return try await withCheckedThrowingContinuation { continuation in
      continuations[frame.sequenceNumber] = continuation
    }
  }

  func waitForInvocation(sequenceNumber: UInt64) async throws {
    for _ in 0..<10_000 {
      if invokedSequenceNumbers.contains(sequenceNumber) { return }
      await Task.yield()
    }
    throw ControllableSlideVisualAnalyzerError.timedOutWaitingForInvocation(sequenceNumber)
  }

  func hasInvocation(sequenceNumber: UInt64) -> Bool {
    invokedSequenceNumbers.contains(sequenceNumber)
  }

  func succeed(
    sequenceNumber: UInt64,
    title: String,
    occupiedRegions: [NormalizedRect] = []
  ) throws {
    guard let continuation = continuations.removeValue(forKey: sequenceNumber) else {
      throw ControllableSlideVisualAnalyzerError.missingInvocation(sequenceNumber)
    }
    continuation.resume(
      returning: SlideVisualAnalysis(
        title: title,
        occupiedRegions: occupiedRegions
      )
    )
  }

  func failWithCancellation(sequenceNumber: UInt64) throws {
    guard let continuation = continuations.removeValue(forKey: sequenceNumber) else {
      throw ControllableSlideVisualAnalyzerError.missingInvocation(sequenceNumber)
    }
    continuation.resume(throwing: CancellationError())
  }
}

private struct ContentIntegrationWindowScanner: PowerPointWindowScanning {
  func scan() async throws -> [PowerPointWindowDescriptor] { [] }
}

@MainActor
private struct ContentIntegrationAuthorizedPermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }

  func requestAccess() -> Bool { true }
}
