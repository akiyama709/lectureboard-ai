import AppKit
import CoreGraphics
import Darwin
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct AppFreshContentSampleIntegrationTests {
  @Test func imageFixturePassesFreshPreparationAndTokenConfirmation() throws {
    let images = try makeImages()
    let operationID = CaptureOperationID(rawValue: 1)
    let identity = try #require(freshSampleWindow.identity)
    let requestID = FreshSampleRequestID()
    let selection = try #require(
      ConfirmedSlideCanvasSelection.testOnlyFullFrame(
        captureOperationID: operationID,
        windowID: identity.windowID,
        sourcePixelWidth: images.firstCandidate.width,
        sourcePixelHeight: images.firstCandidate.height
      )
    )
    let sample = FreshPowerPointWindowSample(
      requestID: requestID,
      captureOperationID: operationID,
      identity: identity,
      requestStartedMachAbsoluteTime: 1,
      capturedAt: Date(timeIntervalSince1970: 1),
      captureSurfaceGeometry: captureGeometry(for: images.firstCandidate),
      image: images.firstCandidate
    )

    let prepared: CapturedSlideCanvasFrame
    switch FreshSlideCanvasSamplePreparer.evaluate(
      sample,
      expectedIdentity: identity,
      anchorSequenceNumber: 4,
      selection: selection
    ) {
    case .prepared(let frame):
      prepared = frame
    case .rejected(let reason):
      Issue.record("Fixture preparation was rejected: \(reason)")
      return
    }

    #expect(prepared.contentFingerprint == images.firstContent)
    #expect(
      prepared.fingerprint.normalizedDifference(
        from: coarseFingerprint(for: images.firstCandidate)
      ) == 0
    )

    var detector = StableContentChangeDetector()
    let rebased = detector.rebase(to: images.baselineContent)
    #expect(rebased)
    let initial = detector.ingest(images.firstContent)
    let token = try #require(initial.pendingChangeToken)
    #expect(initial.state == .contentChangePending(consecutiveFrames: 1))
    #expect(
      detector.confirmPendingChange(try #require(prepared.contentFingerprint), token: token)?.state
        == .contentChangePending(consecutiveFrames: 2)
    )
  }

  @Test func twoBoundedSamplesConfirmOnePendingRevisionWithoutChangingStreamProvenance()
    async throws
  {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let overlay = FreshSampleRecordingOverlayController()
    let leaseScheduler = FreshSampleRecordingLeaseScheduler()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      leaseScheduler: leaseScheduler
    )
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    let streamMetrics = StreamProvenanceSnapshot(model: model)
    let overlayCallsBeforeFresh = overlay.snapshot
    let leaseCallsBeforeFresh = leaseScheduler.snapshot

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    #expect(await capture.returnCancellationStates == [false])
    try await waitForFreshInvocationCount(capture, expected: 2)
    #expect(model.contentRevisionCount == 0)

    try await capture.succeedFresh(
      at: 1,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitUntil {
      model.contentRevisionCount == 1 && model.slideAnalysisStatus == .ready
    }
    try await analyzer.waitForInvocationCount(2)
    await settleAsyncWork()

    #expect(await capture.freshInvocationCount == 2)
    #expect(await analyzer.invocationCount == 2)
    #expect(await analyzer.latestOriginIsBoundedFreshSample)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 4_000)
    #expect(
      (model.latestContentRevisionEvent?.confirmedMachAbsoluteTime ?? 0) >= 4_000
    )
    #expect(model.latestContentRevisionEvent?.source == .boundedFreshSample)
    #expect(StreamProvenanceSnapshot(model: model) == streamMetrics)
    #expect(overlay.snapshot == overlayCallsBeforeFresh)
    #expect(leaseScheduler.snapshot == leaseCallsBeforeFresh)

    await model.stopWindowCapture()
  }

  @Test func twoBoundedSamplesConfirmOneCoarseStreamCandidateWithoutChangingProvenance()
    async throws
  {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let overlay = FreshSampleRecordingOverlayController()
    let leaseScheduler = FreshSampleRecordingLeaseScheduler()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      leaseScheduler: leaseScheduler
    )
    let images = try makeImages()
    let coarseCandidate = try #require(
      makeImage(changedPixelIndices: [], baseChannel: 251)
    )
    let coarseContent = try #require(
      CGImageRasterizer.makeContentFingerprint(from: coarseCandidate)
    )

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: coarseCandidate, content: coarseContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    let streamMetrics = StreamProvenanceSnapshot(model: model)
    let overlayCallsBeforeFresh = overlay.snapshot
    let leaseCallsBeforeFresh = leaseScheduler.snapshot

    try await capture.succeedFresh(
      at: 0,
      image: coarseCandidate,
      geometry: captureGeometry(for: coarseCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    try await waitForFreshInvocationCount(capture, expected: 2)
    #expect(model.contentRevisionCount == 0)

    try await capture.succeedFresh(
      at: 1,
      image: coarseCandidate,
      geometry: captureGeometry(for: coarseCandidate)
    )
    try await waitUntil {
      model.contentRevisionCount == 1 && model.slideAnalysisStatus == .ready
    }
    try await analyzer.waitForInvocationCount(2)
    await settleAsyncWork()

    #expect(await capture.freshInvocationCount == 2)
    #expect(model.contentRevisionCount == 1)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.evidenceStartedMachAbsoluteTime == 4_000)
    #expect(
      (model.latestContentRevisionEvent?.confirmedMachAbsoluteTime ?? 0) >= 4_000
    )
    #expect(model.latestContentRevisionEvent?.source == .boundedFreshSample)
    #expect(await analyzer.latestOriginIsBoundedFreshSample)
    #expect(StreamProvenanceSnapshot(model: model) == streamMetrics)
    #expect(overlay.snapshot == overlayCallsBeforeFresh)
    #expect(leaseScheduler.snapshot == leaseCallsBeforeFresh)

    await model.stopWindowCapture()
  }

  @Test func staleCoarseResultsAfterCandidateReplacementAndResetRecordNoRevision()
    async throws
  {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()
    let firstCoarseCandidate = try #require(
      makeImage(changedPixelIndices: [], baseChannel: 251)
    )
    let replacementCoarseCandidate = try #require(
      makeImage(changedPixelIndices: [], baseChannel: 247)
    )
    let firstCoarseContent = try #require(
      CGImageRasterizer.makeContentFingerprint(from: firstCoarseCandidate)
    )
    let replacementCoarseContent = try #require(
      CGImageRasterizer.makeContentFingerprint(from: replacementCoarseCandidate)
    )

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(
        sequenceNumber: 4,
        image: firstCoarseCandidate,
        content: firstCoarseContent
      )
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    await capture.emit(
      streamFrame(
        sequenceNumber: 5,
        image: replacementCoarseCandidate,
        content: replacementCoarseContent
      )
    )
    try await waitForFreshInvocationCount(capture, expected: 2)

    try await capture.succeedFresh(
      at: 0,
      image: firstCoarseCandidate,
      geometry: captureGeometry(for: firstCoarseCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    #expect(await capture.returnCancellationStates == [true])
    #expect(model.contentRevisionCount == 0)

    await model.stopWindowCapture()
    try await capture.succeedFresh(
      at: 1,
      image: replacementCoarseCandidate,
      geometry: captureGeometry(for: replacementCoarseCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 2)
    await settleAsyncWork()

    #expect(await capture.freshInvocationCount == 2)
    #expect(await capture.returnCancellationStates == [true, true])
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)
  }

  @Test func boundedFreshSamplesRecordRoundTripRevisionOrdinalsAndSource() async throws {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)

    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)
    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshInvocationCount(capture, expected: 2)
    try await capture.succeedFresh(
      at: 1,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitUntil { model.contentRevisionCount == 1 }

    let firstEvent = try #require(model.latestContentRevisionEvent)
    #expect(firstEvent.ordinal == 1)
    #expect(firstEvent.evidenceStartedMachAbsoluteTime == 4_000)
    #expect(firstEvent.confirmedMachAbsoluteTime >= firstEvent.evidenceStartedMachAbsoluteTime)
    #expect(firstEvent.source == .boundedFreshSample)

    await capture.emit(
      streamFrame(sequenceNumber: 5, image: images.baseline, content: images.baselineContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 3)
    try await capture.succeedFresh(
      at: 2,
      image: images.baseline,
      geometry: captureGeometry(for: images.baseline)
    )
    try await waitForFreshInvocationCount(capture, expected: 4)
    try await capture.succeedFresh(
      at: 3,
      image: images.baseline,
      geometry: captureGeometry(for: images.baseline)
    )
    try await waitUntil { model.contentRevisionCount == 2 }

    let secondEvent = try #require(model.latestContentRevisionEvent)
    #expect(secondEvent.ordinal == 2)
    #expect(secondEvent.evidenceStartedMachAbsoluteTime == 5_000)
    #expect(secondEvent.confirmedMachAbsoluteTime >= secondEvent.evidenceStartedMachAbsoluteTime)
    #expect(secondEvent.source == .boundedFreshSample)
    #expect(await capture.freshInvocationCount == 4)

    await model.stopWindowCapture()
  }

  @Test(arguments: [UInt64(0), 3_999, UInt64.max])
  func invalidFreshRequestStartIsRejectedBeforeDetectorConfirmation(
    requestStartedMachAbsoluteTime: UInt64
  ) async throws {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate),
      requestStartedMachAbsoluteTime: requestStartedMachAbsoluteTime
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    await settleAsyncWork()

    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)
    #expect(await capture.freshInvocationCount == 1)

    await model.stopWindowCapture()
  }

  @Test func newerStreamCandidateRejectsOldResultAndReceivesItsOwnTwoAttemptBudget()
    async throws
  {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    await capture.emit(
      streamFrame(
        sequenceNumber: 5,
        image: images.replacementCandidate,
        content: images.replacementContent
      )
    )
    try await waitForFreshInvocationCount(capture, expected: 2)

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    #expect(await capture.returnCancellationStates == [true])
    await settleAsyncWork()
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)

    try await capture.succeedFresh(
      at: 1,
      image: images.replacementCandidate,
      geometry: captureGeometry(for: images.replacementCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 2)
    #expect(await capture.returnCancellationStates == [true, false])
    try await waitForFreshInvocationCount(capture, expected: 3)
    #expect(model.contentRevisionCount == 0)

    try await capture.succeedFresh(
      at: 2,
      image: images.replacementCandidate,
      geometry: captureGeometry(for: images.replacementCandidate)
    )
    try await waitUntil { model.contentRevisionCount == 1 }

    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.source == .boundedFreshSample)

    #expect(await capture.freshInvocationCount == 3)
    #expect(model.capturedFrameCount == 5)
    #expect(model.newCapturedFrameCount == 5)
    #expect(model.repeatedCapturedFrameCount == 0)

    await model.stopWindowCapture()
  }

  @Test func resultFromStoppedSessionCannotPublishIntoRestartedCapture() async throws {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    await model.stopWindowCapture()
    await model.startWindowCapture()
    try await waitUntil { model.captureStatus == .capturing }
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)
    for sequenceNumber in 1...3 {
      await capture.emit(
        streamFrame(
          sequenceNumber: UInt64(sequenceNumber),
          image: images.baseline,
          content: images.baselineContent
        )
      )
    }
    try await waitUntil { model.stableFrameCount == 1 }
    await capture.emit(
      streamFrame(
        sequenceNumber: 4,
        image: images.replacementCandidate,
        content: images.replacementContent
      )
    )
    try await waitForFreshInvocationCount(capture, expected: 2)

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    #expect(await capture.returnCancellationStates == [true])
    await settleAsyncWork()
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)

    try await capture.succeedFresh(
      at: 1,
      image: images.replacementCandidate,
      geometry: captureGeometry(for: images.replacementCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 2)
    #expect(await capture.returnCancellationStates == [true, false])
    try await waitForFreshInvocationCount(capture, expected: 3)
    try await capture.succeedFresh(
      at: 2,
      image: images.replacementCandidate,
      geometry: captureGeometry(for: images.replacementCandidate)
    )
    try await waitUntil { model.contentRevisionCount == 1 }

    let invocations = await capture.freshInvocations
    #expect(invocations.count == 3)
    #expect(invocations[0].operationID != invocations[1].operationID)
    #expect(invocations[1].operationID == invocations[2].operationID)
    #expect(model.capturedFrameCount == 4)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.source == .boundedFreshSample)

    await model.stopWindowCapture()
  }

  @Test func providerBusyDefersNewCandidateUntilOldSystemRequestReturns() async throws {
    let capture = ControllableFreshSampleCapture(enforcesSingleInFlightRequest: true)
    let analyzer = FreshSampleRecordingAnalyzer()
    let waiter = ManualFreshSampleWaiter()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      freshSampleWaiter: waiter
    )
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForManualWaitCount(waiter, expected: 1)
    try await waiter.resume(at: 0)
    try await waitForFreshInvocationCount(capture, expected: 1)

    await capture.emit(
      streamFrame(
        sequenceNumber: 5,
        image: images.replacementCandidate,
        content: images.replacementContent
      )
    )
    try await waitForManualWaitCount(waiter, expected: 2)
    try await waiter.resume(at: 1)
    try await waitForBusyRejectionCount(capture, expected: 1)
    try await waitForManualWaitCount(waiter, expected: 3)

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    #expect(await capture.returnCancellationStates == [true])

    try await waiter.resume(at: 2)
    try await waitForFreshInvocationCount(capture, expected: 2)
    try await capture.succeedFresh(
      at: 1,
      image: images.replacementCandidate,
      geometry: captureGeometry(for: images.replacementCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 2)
    try await waitForManualWaitCount(waiter, expected: 4)

    try await waiter.resume(at: 3)
    try await waitForFreshInvocationCount(capture, expected: 3)
    try await capture.succeedFresh(
      at: 2,
      image: images.replacementCandidate,
      geometry: captureGeometry(for: images.replacementCandidate)
    )
    try await waitUntil { model.contentRevisionCount == 1 }

    #expect(await capture.freshInvocationCount == 3)
    #expect(await capture.providerCallCount == 4)
    #expect(await capture.busyRejectionCount == 1)
    #expect(await capture.returnCancellationStates == [true, false, false])
    #expect(model.capturedFrameCount == 5)

    await model.stopWindowCapture()
  }

  @Test func providerBusyRetryLimitFailsClosedWithoutStartingAnotherSystemSample()
    async throws
  {
    let capture = ControllableFreshSampleCapture(enforcesSingleInFlightRequest: true)
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    await capture.emit(
      streamFrame(
        sequenceNumber: 5,
        image: images.replacementCandidate,
        content: images.replacementContent
      )
    )
    try await waitForBusyRejectionCount(capture, expected: 11)
    await settleAsyncWork()

    #expect(await capture.freshInvocationCount == 1)
    #expect(await capture.providerCallCount == 12)
    #expect(await capture.busyRejectionCount == 11)
    #expect(model.contentRevisionCount == 0)

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    await settleAsyncWork()
    #expect(await capture.freshInvocationCount == 1)

    await capture.emit(
      streamFrame(
        sequenceNumber: 6,
        image: images.replacementCandidate,
        content: images.replacementContent
      )
    )
    try await waitUntil { model.capturedFrameCount == 6 }
    #expect(await capture.freshInvocationCount == 1)
    await capture.emit(
      streamFrame(
        sequenceNumber: 7,
        image: images.replacementCandidate,
        content: images.replacementContent
      )
    )
    try await waitUntil { model.contentRevisionCount == 1 }
    #expect(await capture.freshInvocationCount == 1)

    await model.stopWindowCapture()
  }

  @Test func invalidDenseEvidenceDiscardsOldTokenAndNewCandidateGetsTwoFreshAttempts()
    async throws
  {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()
    let wrongSizedFingerprint = ContentFingerprint(
      sampleColumns: 80,
      sampleRows: 45,
      cells: Array(
        repeating: RGBContentCell(red: 0, green: 0, blue: 0),
        count: 80 * 45
      )
    )

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    await capture.emit(
      streamFrame(
        sequenceNumber: 5,
        image: images.firstCandidate,
        content: wrongSizedFingerprint
      )
    )
    try await waitUntil { model.capturedFrameCount == 5 }
    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    #expect(await capture.returnCancellationStates == [true])
    #expect(model.contentRevisionCount == 0)

    await capture.emit(
      streamFrame(sequenceNumber: 6, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 2)
    try await capture.succeedFresh(
      at: 1,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 2)
    try await waitForFreshInvocationCount(capture, expected: 3)
    try await capture.succeedFresh(
      at: 2,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitUntil { model.contentRevisionCount == 1 }

    #expect(await capture.freshInvocationCount == 3)
    #expect(await capture.returnCancellationStates == [true, false, false])

    await model.stopWindowCapture()
  }

  @Test func unfinishedProviderCallbackDoesNotRetainTheAppModel() async throws {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let images = try makeImages()
    var model: AppModel? = makeModel(capture: capture, analyzer: analyzer)

    if let liveModel = model {
      try await establishBaseline(
        model: liveModel,
        capture: capture,
        analyzer: analyzer,
        images: images
      )
      await capture.emit(
        streamFrame(
          sequenceNumber: 4,
          image: images.firstCandidate,
          content: images.firstContent
        )
      )
      try await waitForFreshInvocationCount(capture, expected: 1)
    } else {
      Issue.record("Expected a live AppModel fixture.")
      return
    }

    weak let weakModel = model
    model = nil
    try await waitUntil { weakModel == nil }

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    #expect(await capture.returnCancellationStates == [true])
  }

  @Test(arguments: FreshSampleFailureMode.allCases)
  func failedFreshEvidenceExhaustsOnlyItsEpisodeAndStreamCanStillConfirm(
    mode: FreshSampleFailureMode
  ) async throws {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let model = makeModel(capture: capture, analyzer: analyzer)
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)

    switch mode {
    case .captureError:
      try await capture.failFresh(at: 0)
    case .geometryMismatch:
      let mismatchedGeometry = try #require(
        CaptureSurfaceGeometry(
          contentRect: CGRect(
            x: 0,
            y: 0,
            width: images.firstCandidate.width + 1,
            height: images.firstCandidate.height
          ),
          scaleFactor: 2,
          contentScale: 1,
          outputPixelWidth: images.firstCandidate.width + 1,
          outputPixelHeight: images.firstCandidate.height
        )
      )
      try await capture.succeedFresh(
        at: 0,
        image: images.firstCandidate,
        geometry: mismatchedGeometry
      )
    case .coarseMismatch:
      try await capture.succeedFresh(
        at: 0,
        image: images.coarseMismatch,
        geometry: captureGeometry(for: images.coarseMismatch)
      )
    }
    await settleAsyncWork()

    await capture.emit(
      streamFrame(sequenceNumber: 5, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitUntil { model.capturedFrameCount == 5 }
    await settleAsyncWork()
    #expect(await capture.freshInvocationCount == 1)
    #expect(model.contentRevisionCount == 0)
    #expect(model.latestContentRevisionEvent == nil)

    await capture.emit(
      streamFrame(sequenceNumber: 6, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitUntil { model.contentRevisionCount == 1 }
    #expect(await capture.freshInvocationCount == 1)
    #expect(await analyzer.invocationCount == 2)
    #expect(model.latestContentRevisionEvent?.ordinal == 1)
    #expect(model.latestContentRevisionEvent?.source == .continuousDenseNew)

    await model.stopWindowCapture()
  }

  @Test func freshOnlyAnalysisDoesNotRenderOrRenewTheOverlayLease() async throws {
    let capture = ControllableFreshSampleCapture()
    let analyzer = FreshSampleRecordingAnalyzer()
    let overlay = FreshSampleRecordingOverlayController()
    let leaseScheduler = FreshSampleRecordingLeaseScheduler()
    let model = makeModel(
      capture: capture,
      analyzer: analyzer,
      overlay: overlay,
      leaseScheduler: leaseScheduler
    )
    let images = try makeImages()

    try await establishBaseline(model: model, capture: capture, analyzer: analyzer, images: images)
    await capture.emit(
      streamFrame(sequenceNumber: 4, image: images.firstCandidate, content: images.firstContent)
    )
    try await waitForFreshInvocationCount(capture, expected: 1)
    let overlayCallsAfterPendingBoundary = overlay.snapshot
    let leaseCallsAfterPendingBoundary = leaseScheduler.snapshot

    try await capture.succeedFresh(
      at: 0,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitForFreshReturnCount(capture, expected: 1)
    try await waitForFreshInvocationCount(capture, expected: 2)
    try await capture.succeedFresh(
      at: 1,
      image: images.firstCandidate,
      geometry: captureGeometry(for: images.firstCandidate)
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    await settleAsyncWork()

    #expect(await analyzer.latestOriginIsBoundedFreshSample)
    #expect(overlay.snapshot == overlayCallsAfterPendingBoundary)
    #expect(leaseScheduler.snapshot == leaseCallsAfterPendingBoundary)

    await model.stopWindowCapture()
  }

  private func makeModel(
    capture: ControllableFreshSampleCapture,
    analyzer: FreshSampleRecordingAnalyzer,
    overlay: FreshSampleRecordingOverlayController = FreshSampleRecordingOverlayController(),
    leaseScheduler: FreshSampleRecordingLeaseScheduler = FreshSampleRecordingLeaseScheduler(),
    freshSampleWaiter: any FreshContentSampleWaiting = YieldingFreshSampleWaiter()
  ) -> AppModel {
    let model = AppModel(
      permissionService: PermissionService(
        screenCaptureClient: FreshSampleAuthorizedPermissionClient()
      ),
      windowCapture: capture,
      scanner: FreshSampleWindowScanner(),
      slideIdentityProvider: SilentFreshSampleSlideIdentityProvider(),
      slideVisionAnalyzer: analyzer,
      slideCanvasConfirmationMode: .testOnlyUseFullCapturedFrame,
      freshContentSampleDelay: .zero,
      freshContentSampleWaiter: freshSampleWaiter,
      overlayController: overlay,
      displayCoordinateSnapshotProvider: EmptyFreshSampleDisplayProvider(),
      productionOverlayEligibilityProvider: RejectingFreshSampleOverlayEligibilityProvider(),
      productionOverlayLeaseScheduler: leaseScheduler,
      productionOverlaySafetyEventProvider: FreshSampleSafetyEventProvider()
    )
    model.powerPointWindows = [freshSampleWindow]
    model.selectedPowerPointWindowID = freshSampleWindow.id
    return model
  }

  private func establishBaseline(
    model: AppModel,
    capture: ControllableFreshSampleCapture,
    analyzer: FreshSampleRecordingAnalyzer,
    images: FreshSampleImages
  ) async throws {
    await model.startWindowCapture()
    try await waitUntil { model.captureStatus == .capturing }
    for sequenceNumber in 1...3 {
      await capture.emit(
        streamFrame(
          sequenceNumber: UInt64(sequenceNumber),
          image: images.baseline,
          content: images.baselineContent
        )
      )
    }
    try await waitUntil {
      model.stableFrameCount == 1 && model.slideAnalysisStatus == .ready
    }
    try await analyzer.waitForInvocationCount(1)
  }

  private func streamFrame(
    sequenceNumber: UInt64,
    image: CGImage,
    content: ContentFingerprint
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: freshSampleWindow.id,
      sequenceNumber: sequenceNumber,
      capturedAt: Date(timeIntervalSince1970: TimeInterval(sequenceNumber)),
      displayTime: sequenceNumber * 1_000,
      deliveryKind: .new,
      captureSurfaceGeometry: captureGeometry(for: image),
      image: image,
      fingerprint: coarseFingerprint(for: image),
      contentFingerprint: content
    )
  }

  private func captureGeometry(for image: CGImage) -> CaptureSurfaceGeometry {
    guard
      let geometry = CaptureSurfaceGeometry(
        contentRect: CGRect(x: 0, y: 0, width: image.width, height: image.height),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: image.width,
        outputPixelHeight: image.height
      )
    else {
      preconditionFailure("Synthetic fresh-sample geometry must be valid.")
    }
    return geometry
  }

  private func coarseFingerprint(for image: CGImage) -> FrameFingerprint {
    guard let fingerprint = CGImageRasterizer.makeFrameFingerprint(from: image) else {
      preconditionFailure("Synthetic fresh-sample image must produce a coarse fingerprint.")
    }
    return fingerprint
  }

  private func makeImages() throws -> FreshSampleImages {
    let baseline = try #require(makeImage(changedPixelIndices: []))
    let firstCandidate = try #require(makeImage(changedPixelIndices: Set(0..<20)))
    let replacementCandidate = try #require(makeImage(changedPixelIndices: Set(40..<60)))
    let coarseMismatch = try #require(makeImage(changedPixelIndices: Set(0..<(160 * 90))))
    return FreshSampleImages(
      baseline: baseline,
      firstCandidate: firstCandidate,
      replacementCandidate: replacementCandidate,
      coarseMismatch: coarseMismatch,
      baselineContent: try #require(CGImageRasterizer.makeContentFingerprint(from: baseline)),
      firstContent: try #require(
        CGImageRasterizer.makeContentFingerprint(from: firstCandidate)
      ),
      replacementContent: try #require(
        CGImageRasterizer.makeContentFingerprint(from: replacementCandidate)
      )
    )
  }

  private func makeImage(
    changedPixelIndices: Set<Int>,
    baseChannel: UInt8 = 255
  ) -> CGImage? {
    let width = 160
    let height = 90
    var bytes: [UInt8] = []
    bytes.reserveCapacity(width * height * 4)
    for row in 0..<height {
      for column in 0..<width {
        let pixelIndex = row * width + column
        let channel: UInt8 = changedPixelIndices.contains(pixelIndex) ? 0 : baseChannel
        bytes.append(contentsOf: [channel, channel, channel, 255])
      }
    }
    guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
    return CGImage(
      width: width,
      height: height,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(
        rawValue:
          CGBitmapInfo.byteOrder32Big.rawValue
          | CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private func waitUntil(
    _ predicate: @escaping @MainActor () -> Bool
  ) async throws {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    throw FreshSampleIntegrationTestError.modelPredicateTimedOut
  }

  private func waitForFreshInvocationCount(
    _ capture: ControllableFreshSampleCapture,
    expected: Int
  ) async throws {
    for _ in 0..<10_000 {
      let actual = await capture.freshInvocationCount
      if actual >= expected { return }
      await Task.yield()
    }
    throw FreshSampleIntegrationTestError.freshInvocationTimedOut(
      expected: expected,
      actual: await capture.freshInvocationCount
    )
  }

  private func waitForFreshReturnCount(
    _ capture: ControllableFreshSampleCapture,
    expected: Int
  ) async throws {
    for _ in 0..<10_000 {
      let actual = await capture.returnCancellationStates.count
      if actual >= expected { return }
      await Task.yield()
    }
    throw FreshSampleIntegrationTestError.freshReturnTimedOut(
      expected: expected,
      actual: await capture.returnCancellationStates.count
    )
  }

  private func waitForBusyRejectionCount(
    _ capture: ControllableFreshSampleCapture,
    expected: Int
  ) async throws {
    for _ in 0..<10_000 {
      let actual = await capture.busyRejectionCount
      if actual >= expected { return }
      await Task.yield()
    }
    throw FreshSampleIntegrationTestError.busyRejectionTimedOut(
      expected: expected,
      actual: await capture.busyRejectionCount
    )
  }

  private func waitForManualWaitCount(
    _ waiter: ManualFreshSampleWaiter,
    expected: Int
  ) async throws {
    for _ in 0..<10_000 {
      let actual = await waiter.waitCount
      if actual >= expected { return }
      await Task.yield()
    }
    throw FreshSampleIntegrationTestError.manualWaitTimedOut(
      expected: expected,
      actual: await waiter.waitCount
    )
  }

  private func settleAsyncWork() async {
    for _ in 0..<50 {
      await Task.yield()
    }
  }
}

private let freshSampleWindow = PowerPointWindowDescriptor(
  id: 42,
  title: "Synthetic bounded fresh-sample window",
  applicationName: "Microsoft PowerPoint",
  ownerProcessID: 700,
  bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
  frame: .zero
)

private struct FreshSampleImages: @unchecked Sendable {
  let baseline: CGImage
  let firstCandidate: CGImage
  let replacementCandidate: CGImage
  let coarseMismatch: CGImage
  let baselineContent: ContentFingerprint
  let firstContent: ContentFingerprint
  let replacementContent: ContentFingerprint
}

private struct StreamProvenanceSnapshot: Equatable {
  let capturedFrameCount: Int
  let newCapturedFrameCount: Int
  let repeatedCapturedFrameCount: Int
  let lastNewFrameAt: Date?
  let latestDifferenceFromStableFrame: Double?
  let stableFrameCount: Int
  let slideChangeCount: Int
  let slideIdentitySampleCount: Int
  let slideIdentityContinuityBreakCount: Int
  let slideCanvasStatus: SlideCanvasStatus
  let slideCanvasCalibrationRevision: Int
  let confirmedSlideCanvasRegion: SlideCanvasRegion?
  let overlayMappingState: SlideCanvasOverlayMappingState

  @MainActor
  init(model: AppModel) {
    capturedFrameCount = model.capturedFrameCount
    newCapturedFrameCount = model.newCapturedFrameCount
    repeatedCapturedFrameCount = model.repeatedCapturedFrameCount
    lastNewFrameAt = model.lastNewFrameAt
    latestDifferenceFromStableFrame = model.latestDifferenceFromStableFrame
    stableFrameCount = model.stableFrameCount
    slideChangeCount = model.slideChangeCount
    slideIdentitySampleCount = model.slideIdentitySampleCount
    slideIdentityContinuityBreakCount = model.slideIdentityContinuityBreakCount
    slideCanvasStatus = model.slideCanvasStatus
    slideCanvasCalibrationRevision = model.slideCanvasCalibrationRevision
    confirmedSlideCanvasRegion = model.confirmedSlideCanvasRegion
    overlayMappingState = model.slideCanvasOverlayMappingState
  }
}

enum FreshSampleFailureMode: CaseIterable, Sendable {
  case captureError
  case geometryMismatch
  case coarseMismatch
}

private enum FreshSampleIntegrationTestError: Error {
  case modelPredicateTimedOut
  case freshInvocationTimedOut(expected: Int, actual: Int)
  case freshReturnTimedOut(expected: Int, actual: Int)
  case busyRejectionTimedOut(expected: Int, actual: Int)
  case manualWaitTimedOut(expected: Int, actual: Int)
  case analyzerInvocationTimedOut(expected: Int, actual: Int)
  case missingFreshInvocation(Int)
  case missingFreshContinuation(Int)
  case missingManualWait(Int)
  case controlledCaptureFailure
}

private struct FreshSampleInvocation: Sendable {
  let operationID: CaptureOperationID
  let identity: PowerPointWindowIdentity
  let requestID: FreshSampleRequestID
}

private actor ControllableFreshSampleCapture: PowerPointWindowCapturing {
  private let enforcesSingleInFlightRequest: Bool
  private var frameHandler: CaptureFrameHandler?
  private var invocations: [FreshSampleInvocation] = []
  private var cancellationStatesAtReturn: [Bool] = []
  private var totalProviderCallCount = 0
  private var totalBusyRejectionCount = 0
  private var providerInFlightRequestID: FreshSampleRequestID?
  private var continuations:
    [FreshSampleRequestID: CheckedContinuation<FreshPowerPointWindowSample, any Error>] = [:]

  var freshInvocationCount: Int { invocations.count }
  var freshInvocations: [FreshSampleInvocation] { invocations }
  var returnCancellationStates: [Bool] { cancellationStatesAtReturn }
  var providerCallCount: Int { totalProviderCallCount }
  var busyRejectionCount: Int { totalBusyRejectionCount }

  init(enforcesSingleInFlightRequest: Bool = false) {
    self.enforcesSingleInFlightRequest = enforcesSingleInFlightRequest
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    frameHandler = onFrame
  }

  func stop(operationID: CaptureOperationID) async {
    frameHandler = nil
  }

  func captureFreshSample(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    requestID: FreshSampleRequestID
  ) async throws -> FreshPowerPointWindowSample {
    totalProviderCallCount += 1
    if enforcesSingleInFlightRequest, providerInFlightRequestID != nil {
      totalBusyRejectionCount += 1
      throw FreshPowerPointWindowSampleError.requestAlreadyInFlight
    }
    if enforcesSingleInFlightRequest {
      providerInFlightRequestID = requestID
    }
    defer {
      if providerInFlightRequestID == requestID {
        providerInFlightRequestID = nil
      }
    }
    invocations.append(
      FreshSampleInvocation(
        operationID: operationID,
        identity: identity,
        requestID: requestID
      )
    )
    let sample = try await withCheckedThrowingContinuation { continuation in
      continuations[requestID] = continuation
    }
    cancellationStatesAtReturn.append(Task.isCancelled)
    return sample
  }

  func emit(_ frame: CapturedPowerPointFrame) {
    frameHandler?(frame)
  }

  func succeedFresh(
    at index: Int,
    image: CGImage,
    geometry: CaptureSurfaceGeometry,
    requestStartedMachAbsoluteTime: UInt64? = nil
  ) throws {
    guard invocations.indices.contains(index) else {
      throw FreshSampleIntegrationTestError.missingFreshInvocation(index)
    }
    let invocation = invocations[index]
    guard let continuation = continuations.removeValue(forKey: invocation.requestID) else {
      throw FreshSampleIntegrationTestError.missingFreshContinuation(index)
    }
    continuation.resume(
      returning: FreshPowerPointWindowSample(
        requestID: invocation.requestID,
        captureOperationID: invocation.operationID,
        identity: invocation.identity,
        requestStartedMachAbsoluteTime:
          requestStartedMachAbsoluteTime ?? mach_absolute_time(),
        capturedAt: Date(timeIntervalSince1970: TimeInterval(index + 100)),
        captureSurfaceGeometry: geometry,
        image: image
      )
    )
  }

  func failFresh(at index: Int) throws {
    guard invocations.indices.contains(index) else {
      throw FreshSampleIntegrationTestError.missingFreshInvocation(index)
    }
    let invocation = invocations[index]
    guard let continuation = continuations.removeValue(forKey: invocation.requestID) else {
      throw FreshSampleIntegrationTestError.missingFreshContinuation(index)
    }
    continuation.resume(throwing: FreshSampleIntegrationTestError.controlledCaptureFailure)
  }
}

private actor FreshSampleRecordingAnalyzer: SlideVisualAnalyzing {
  private var origins: [CapturedSlideCanvasFrameOrigin] = []

  var invocationCount: Int { origins.count }
  var latestOriginIsBoundedFreshSample: Bool {
    guard let origin = origins.last else { return false }
    if case .boundedFreshSample = origin { return true }
    return false
  }

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    origins.append(frame.origin)
    return SlideVisualAnalysis(
      title: "fresh-sample analysis",
      occupiedRegions: [
        NormalizedRect(x: 0.05, y: 0.05, width: 0.2, height: 0.15)
      ]
    )
  }

  func waitForInvocationCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if origins.count >= expectedCount { return }
      await Task.yield()
    }
    throw FreshSampleIntegrationTestError.analyzerInvocationTimedOut(
      expected: expectedCount,
      actual: origins.count
    )
  }
}

private struct YieldingFreshSampleWaiter: FreshContentSampleWaiting {
  func wait(for duration: Duration) async {
    await Task.yield()
  }
}

private actor ManualFreshSampleWaiter: FreshContentSampleWaiting {
  private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private(set) var waitCount = 0

  func wait(for duration: Duration) async {
    let index = waitCount
    waitCount += 1
    await withCheckedContinuation { continuation in
      continuations[index] = continuation
    }
  }

  func resume(at index: Int) throws {
    guard let continuation = continuations.removeValue(forKey: index) else {
      throw FreshSampleIntegrationTestError.missingManualWait(index)
    }
    continuation.resume()
  }
}

@MainActor
private final class FreshSampleRecordingOverlayController: OverlayWindowControlling {
  struct Snapshot: Equatable {
    let showCount: Int
    let renderCount: Int
    let hideCount: Int
  }

  private var showCount = 0
  private var renderCount = 0
  private var hideCount = 0

  var snapshot: Snapshot {
    Snapshot(showCount: showCount, renderCount: renderCount, hideCount: hideCount)
  }

  func showDemo(scene: BoardScene, style: DigitalInkStyle, on screen: NSScreen?) {
    showCount += 1
  }

  func render(scene: BoardScene, style: DigitalInkStyle, in frame: CGRect) {
    renderCount += 1
  }

  func hide() {
    hideCount += 1
  }
}

@MainActor
private final class FreshSampleRecordingLeaseScheduler: ProductionOverlayLeaseScheduling {
  struct Snapshot: Equatable {
    let scheduleCount: Int
    let cancelCount: Int
  }

  private var scheduleCount = 0
  private var cancelCount = 0

  var snapshot: Snapshot {
    Snapshot(scheduleCount: scheduleCount, cancelCount: cancelCount)
  }

  func schedule(
    after duration: Duration,
    action: @escaping @MainActor @Sendable () -> Void
  ) {
    scheduleCount += 1
  }

  func cancel() {
    cancelCount += 1
  }
}

@MainActor
private final class FreshSampleSafetyEventProvider: ProductionOverlaySafetyEventProviding {
  func start(onUnsafeEvent: @escaping ProductionOverlayUnsafeEventHandler) {}
  func stop() {}
}

@MainActor
private struct EmptyFreshSampleDisplayProvider: DisplayCoordinateSnapshotProviding {
  func currentSnapshots() -> [DisplayCoordinateSnapshot] { [] }
}

@MainActor
private struct RejectingFreshSampleOverlayEligibilityProvider:
  ProductionOverlayEligibilityProviding
{
  func allowsProductionOverlay(
    for identity: PowerPointWindowIdentity,
    screenGeometry: CaptureScreenGeometry
  ) -> Bool {
    false
  }
}

private struct FreshSampleWindowScanner: PowerPointWindowScanning {
  func scan() async throws -> [PowerPointWindowDescriptor] { [] }
}

private actor SilentFreshSampleSlideIdentityProvider: PowerPointSlideIdentityProviding {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async {}

  func stop(operationID: CaptureOperationID) async {}
}

@MainActor
private struct FreshSampleAuthorizedPermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }
  func requestAccess() -> Bool { true }
}
