import CoreGraphics
import Darwin
import Foundation
import LectureBoardCore
import Testing

@testable import LectureBoard_AI

@MainActor
struct AppSlideIdentityIntegrationTests {
  @Test func transcriptionOperationGateRejectsEverySupersededOperation() {
    var gate = TranscriptionOperationGate()
    let first = gate.begin()
    #expect(gate.accepts(first))

    gate.invalidate()
    #expect(!gate.accepts(first))

    let second = gate.begin()
    #expect(!gate.accepts(first))
    #expect(gate.accepts(second))
    let rejectedStaleInvalidation = gate.invalidate(ifCurrent: first)
    #expect(!rejectedStaleInvalidation)
    #expect(gate.accepts(second))
    let acceptedCurrentInvalidation = gate.invalidate(ifCurrent: second)
    #expect(acceptedCurrentInvalidation)
    #expect(!gate.hasActiveOperation)
  }

  @Test func establishedBaselineRebasesWithoutCountingAChange() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let seventhSlide = try sample(slideID: 707, slideIndex: 7)
    model.boardScene = markerScene(slideNumber: 1)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(seventhSlide))
    try await waitUntil { model.slideIdentityState == .establishing }
    #expect(model.boardScene.slideNumber == 1)
    #expect(model.boardScene.elements.count == 1)

    await provider.emit(sequenceNumber: 2, signal: .available(seventhSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 7)
    #expect(model.boardScene.elements.isEmpty)

    model.boardScene = markerScene(slideNumber: 7)
    let reorderedSameSlide = try sample(slideID: 707, slideIndex: 8)
    await provider.emit(sequenceNumber: 3, signal: .available(reorderedSameSlide))
    try await waitUntil { model.boardScene.slideNumber == 8 }
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.elements.count == 1)

    await model.stopWindowCapture()
  }

  @Test func confirmedSemanticTransitionCountsAndClearsThePreviousBoard() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)

    await model.startWindowCapture()
    #expect(model.captureStatus == .capturing)

    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }
    #expect(model.slideChangeCount == 0)

    model.boardScene = BoardScene(
      slideNumber: 1,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1),
          text: "Previous slide"
        )
      ]
    )

    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }

    #expect(model.slideIdentityState == .identified)
    #expect(model.slideIdentitySampleCount == 4)
    #expect(model.slideIdentityContinuityBreakCount == 0)
    #expect(model.boardScene.slideNumber == 2)
    #expect(model.boardScene.elements.isEmpty)

    let snapshot = RuntimeVerificationSnapshotProjector.makeSnapshot(
      from: model,
      timestamp: Date(timeIntervalSince1970: 0),
      elapsedMilliseconds: 1_000,
      screenRecordingPermission: .authorized
    )
    #expect(snapshot.slideChangeCount == 1)
    #expect(snapshot.slideIdentityState == .identified)
    #expect(snapshot.slideIdentityFrameSyncState == .waiting)
    #expect(snapshot.slideIdentitySampleCount == 4)
    #expect(snapshot.slideIdentityContinuityBreakCount == 0)

    await model.stopWindowCapture()
  }

  @Test func confirmedTransitionDoesNotReplayAcceptedTranscriptFromThePreviousSlide() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = CountingSlideIdentityAnalyzer(
      title: "Sustainability and Resilience",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let model = makeModel(capture: capture, provider: provider, analyzer: analyzer)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()
    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }

    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: image,
        coarseFingerprint: fingerprints.coarse,
        contentFingerprint: fingerprints.content
      )
    )
    for sequenceNumber in 2...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: fingerprints.coarse,
          contentFingerprint: fingerprints.content
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    receiveConfirmedDefinition(on: model)
    #expect(!model.boardScene.elements.isEmpty)

    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }
    #expect(model.boardScene.slideNumber == 2)
    #expect(model.boardScene.elements.isEmpty)

    await capture.emit(
      frame(
        sequenceNumber: 4,
        image: image,
        coarseFingerprint: fingerprints.coarse,
        contentFingerprint: fingerprints.content
      )
    )
    for sequenceNumber in 5...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: fingerprints.coarse,
          contentFingerprint: fingerprints.content
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }

    model.receive(
      TranscriptSegment(
        text: "This is a brief aside.",
        startTime: 7,
        endTime: 8,
        language: .englishUS,
        confidence: 0.95,
        emphasis: 0
      )
    )
    #expect(model.boardScene.elements.isEmpty)

    receiveConfirmedDefinition(
      text: "Resilience means retaining function while conditions change.",
      startTime: 9,
      endTime: 14,
      on: model
    )
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func delayedSpeechTaskCannotCrossAConfirmedSemanticSlideBoundary() async throws {
    let capture = SlideIdentityFrameCapture()
    let identityProvider = ControllableSlideIdentityProvider()
    let transcriptionProvider = ControllableTranscriptionProvider()
    let analyzer = CountingSlideIdentityAnalyzer(
      title: "Sustainability",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let model = makeModel(
      capture: capture,
      provider: identityProvider,
      analyzer: analyzer,
      transcriptionProvider: transcriptionProvider
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()

    await model.startWindowCapture()
    await identityProvider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await identityProvider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    await emitStableFrames(
      capture: capture,
      image: image,
      fingerprints: fingerprints,
      sequenceNumbers: 1...3
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }

    await model.startTranscription()
    #expect(transcriptionProvider.startCount == 1)
    #expect(model.status == .listening)
    #expect(model.transcriptionLifecycleState == .listening)

    await identityProvider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await identityProvider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }
    #expect(transcriptionProvider.stopCount == 1)
    #expect(model.status == .ready)
    #expect(model.transcriptionLifecycleState == .waitingForContext)
    #expect(model.liveTranscript.isEmpty)

    await emitStableFrames(
      capture: capture,
      image: image,
      fingerprints: fingerprints,
      sequenceNumbers: 4...6
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    try await waitUntil { transcriptionProvider.startCount == 2 }
    #expect(model.status == .listening)
    #expect(model.transcriptionLifecycleState == .listening)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: definitionSegment(),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript.isEmpty)
    #expect(model.boardScene.elements.isEmpty)

    transcriptionProvider.emit(
      startIndex: 1,
      observation: TranscriptionObservation(
        segment: definitionSegment(),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == definitionSegment().text)
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func manualStopDuringSemanticBoundaryPreventsAutomaticTranscriptionResume() async throws {
    let capture = SlideIdentityFrameCapture()
    let identityProvider = ControllableSlideIdentityProvider()
    let transcriptionProvider = ControllableTranscriptionProvider()
    let analyzer = CountingSlideIdentityAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let model = makeModel(
      capture: capture,
      provider: identityProvider,
      analyzer: analyzer,
      transcriptionProvider: transcriptionProvider
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()

    await model.startWindowCapture()
    await identityProvider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await identityProvider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    await emitStableFrames(
      capture: capture,
      image: image,
      fingerprints: fingerprints,
      sequenceNumbers: 1...3
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }

    await model.startTranscription()
    #expect(transcriptionProvider.startCount == 1)

    await identityProvider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await identityProvider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }
    model.stopTranscription()

    await emitStableFrames(
      capture: capture,
      image: image,
      fingerprints: fingerprints,
      sequenceNumbers: 4...6
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    await drainMainActorQueue()

    #expect(transcriptionProvider.startCount == 1)
    #expect(model.status == .ready)

    await model.stopWindowCapture()
  }

  @Test func temporaryCaptureGapResumesRequestedTranscriptionAfterFreshAnalysis() async throws {
    let capture = SlideIdentityFrameCapture()
    let identityProvider = ControllableSlideIdentityProvider()
    let transcriptionProvider = ControllableTranscriptionProvider()
    let analyzer = CountingSlideIdentityAnalyzer(
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let model = makeModel(
      capture: capture,
      provider: identityProvider,
      analyzer: analyzer,
      transcriptionProvider: transcriptionProvider
    )
    let slide = try sample(slideID: 101, slideIndex: 1)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()

    await model.startWindowCapture()
    await identityProvider.emit(sequenceNumber: 1, signal: .available(slide))
    await identityProvider.emit(sequenceNumber: 2, signal: .available(slide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    await emitStableFrames(
      capture: capture,
      image: image,
      fingerprints: fingerprints,
      sequenceNumbers: 1...3
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    await model.startTranscription()

    await capture.emitContentUnavailable(sequenceNumber: 4)
    try await waitUntil { transcriptionProvider.stopCount == 1 }
    #expect(model.status == .ready)

    await emitStableFrames(
      capture: capture,
      image: image,
      fingerprints: fingerprints,
      sequenceNumbers: 5...7
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    try await waitUntil { transcriptionProvider.startCount == 2 }

    #expect(model.status == .listening)

    await model.stopWindowCapture()
  }

  @Test func stoppedSpeechTaskCannotEnterARestartedTranscription() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    await model.startTranscription()
    model.stopTranscription()
    await model.startTranscription()
    #expect(transcriptionProvider.startCount == 2)
    #expect(model.status == .listening)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "stale operation"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript.isEmpty)

    transcriptionProvider.emit(
      startIndex: 1,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "current operation"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == "current operation")

    model.stopTranscription()
  }

  @Test func currentSpeechTerminalEventClearsListeningStateAndRejectsRetainedResults()
    async throws
  {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    await model.startTranscription()
    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "accepted before failure"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == "accepted before failure")
    #expect(model.liveTranscriptPhase == .partial)

    transcriptionProvider.emitTerminal(
      startIndex: 0,
      error: .recognitionFinalizationTimedOut
    )

    #expect(
      model.status
        == .error(TranscriptionError.recognitionFinalizationTimedOut.localizedDescription)
    )
    #expect(
      model.transcriptionLifecycleState
        == .failed(TranscriptionError.recognitionFinalizationTimedOut.localizedDescription)
    )
    #expect(model.liveTranscript.isEmpty)
    #expect(model.liveTranscriptPhase == .empty)
    #expect(transcriptionProvider.stopCount == 0)
    #expect(transcriptionProvider.startCount == 1)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "retained after failure"),
        sourceMachTime: mach_absolute_time()
      )
    )
    await drainMainActorQueue()
    #expect(model.liveTranscript.isEmpty)
    #expect(model.liveTranscriptPhase == .empty)
    #expect(transcriptionProvider.startCount == 1)
  }

  @Test func retryAfterSpeechFailureRestartsWithoutKeepingStaleAppError() async {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    await model.startTranscription()
    transcriptionProvider.emitTerminal(
      startIndex: 0,
      error: .recognitionFinalizationTimedOut
    )
    #expect(
      model.status
        == .error(TranscriptionError.recognitionFinalizationTimedOut.localizedDescription)
    )

    await model.requestTranscriptionStart()

    #expect(model.status == .listening)
    #expect(model.transcriptionLifecycleState == .listening)
    #expect(transcriptionProvider.startCount == 2)
    #expect(model.canRequestTranscriptionStop)

    model.requestTranscriptionStop()
  }

  @Test func immediateRetryDoesNotHideANewerPowerPointScanError() async {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider,
      scanner: FailingSlideIdentityWindowScanner()
    )

    await model.startTranscription()
    transcriptionProvider.emitTerminal(
      startIndex: 0,
      error: .recognitionFinalizationTimedOut
    )
    await model.refreshPowerPointWindows()
    #expect(
      model.status
        == .error(SlideIdentityWindowScanError.controlled.localizedDescription)
    )

    await model.requestTranscriptionStart()

    #expect(
      model.status
        == .error(SlideIdentityWindowScanError.controlled.localizedDescription)
    )
    #expect(model.transcriptionLifecycleState == .listening)
    #expect(transcriptionProvider.startCount == 2)
    #expect(model.canRequestTranscriptionStop)

    model.requestTranscriptionStop()
    #expect(
      model.status
        == .error(SlideIdentityWindowScanError.controlled.localizedDescription)
    )
    #expect(model.transcriptionLifecycleState == .idle)
  }

  @Test func transcriptPhaseTracksAcceptedPartialFinalAndNewOperationReset() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    await model.startTranscription()
    #expect(model.liveTranscriptPhase == .empty)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "partial segment"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == "partial segment")
    #expect(model.liveTranscriptPhase == .partial)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: "final segment"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == "final segment")
    #expect(model.liveTranscriptPhase == .final)

    await model.startTranscription()
    #expect(model.liveTranscript.isEmpty)
    #expect(model.liveTranscriptPhase == .empty)
    #expect(transcriptionProvider.startCount == 2)

    model.stopTranscription()
  }

  @Test func manualStopAcceptsTheFinalTailBeforeCompletingAndPreservesIt() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    transcriptionProvider.automaticallyCompletesGracefulStop = false
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    await model.startTranscription()
    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "unfinished tail"),
        sourceMachTime: mach_absolute_time()
      )
    )
    model.stopTranscription()
    #expect(model.status == .finalizingTranscription)
    #expect(model.transcriptionLifecycleState == .finalizing)
    #expect(model.liveTranscript == "unfinished tail")
    #expect(model.liveTranscriptPhase == .partial)
    #expect(transcriptionProvider.stopCount == 1)

    #expect(!model.canRequestTranscriptionStart)
    #expect(!model.canRequestTranscriptionStop)
    await model.requestTranscriptionStart()
    model.requestTranscriptionStop()
    #expect(transcriptionProvider.startCount == 1)
    #expect(transcriptionProvider.stopCount == 1)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: TranscriptSegment(
          text: "finalized tail",
          startTime: 0,
          endTime: 2,
          language: .englishUS,
          confidence: 0,
          isFinal: true,
          emphasis: 0.5
        ),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == "finalized tail")
    #expect(model.liveTranscriptPhase == .final)
    transcriptionProvider.emitGracefulCompletion(startIndex: 0)

    #expect(model.status == .ready)
    #expect(model.transcriptionLifecycleState == .idle)
    #expect(model.liveTranscript == "finalized tail")
    #expect(model.liveTranscriptPhase == .final)
    #expect(model.canRequestTranscriptionStart)
    #expect(!model.canRequestTranscriptionStop)
    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "stale after completion"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == "finalized tail")
  }

  @Test func manualStopWhileProviderStartIsSuspendedCompletesWithoutHanging() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    transcriptionProvider.suspendStart = true
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    #expect(model.canRequestTranscriptionStart)
    #expect(!model.canRequestTranscriptionStop)
    model.requestTranscriptionStop()
    #expect(transcriptionProvider.stopCount == 0)

    let startTask = Task { await model.startTranscription() }
    try await waitUntil { transcriptionProvider.startCount == 1 }
    #expect(model.transcriptionLifecycleState == .starting)
    #expect(!model.canRequestTranscriptionStart)
    #expect(model.canRequestTranscriptionStop)
    await model.requestTranscriptionStart()
    #expect(transcriptionProvider.startCount == 1)
    model.requestTranscriptionStop()

    #expect(model.status == .ready)
    #expect(model.transcriptionLifecycleState == .idle)
    #expect(transcriptionProvider.stopCount == 1)
    await startTask.value
    #expect(model.status == .ready)
    #expect(transcriptionProvider.startCount == 1)
    #expect(transcriptionProvider.stopCount == 1)
    #expect(model.canRequestTranscriptionStart)
    #expect(!model.canRequestTranscriptionStop)
  }

  @Test func staleAndDuplicateSpeechTerminalEventsCannotStopANewerSession() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: SlideIdentityFrameCapture(),
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    await model.startTranscription()
    model.stopTranscription()
    await model.startTranscription()
    #expect(model.status == .listening)
    #expect(transcriptionProvider.startCount == 2)
    #expect(transcriptionProvider.stopCount == 1)

    transcriptionProvider.emitTerminal(
      startIndex: 0,
      error: .recognitionInterrupted
    )
    #expect(model.status == .listening)
    #expect(transcriptionProvider.stopCount == 1)

    transcriptionProvider.emit(
      startIndex: 1,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "current operation"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript == "current operation")

    transcriptionProvider.emitTerminal(
      startIndex: 1,
      error: .onDeviceRecognitionUnavailable
    )
    #expect(
      model.status
        == .error(TranscriptionError.onDeviceRecognitionUnavailable.localizedDescription)
    )
    #expect(model.liveTranscript.isEmpty)
    #expect(transcriptionProvider.stopCount == 1)

    model.stopTranscription()
    transcriptionProvider.emitTerminal(
      startIndex: 1,
      error: .recognitionInterrupted
    )
    #expect(model.status == .ready)
    #expect(transcriptionProvider.stopCount == 1)
  }

  @Test func oneGroundedMinimumAcceptedConfidenceFinalReachesThePublicScene() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider
    )

    let text =
      "Sustainability means meeting present needs without undermining future possibilities."
    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: text),
        sourceMachTime: mach_absolute_time()
      )
    )

    #expect(transcriptionProvider.startCount == 1)
    #expect(!model.boardScene.elements.isEmpty)
    #expect(!model.lectureSessionScenes.isEmpty)
    await model.stopWindowCapture()
  }

  @Test func groundedZeroConfidenceFinalDefinitionRemainsInternal() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider
    )

    let text =
      "Sustainability means meeting present needs without undermining future possibilities."
    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: text, confidence: 0),
        sourceMachTime: mach_absolute_time()
      )
    )

    #expect(model.boardScene.elements.isEmpty)
    #expect(model.lectureSessionScenes.isEmpty)
    await model.stopWindowCapture()
  }

  @Test func partialGroundedProviderStrengthDefinitionRemainsInternal() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider
    )
    let text =
      "Sustainability means meeting present needs without undermining future possibilities."

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: text, isFinal: false),
        sourceMachTime: mach_absolute_time()
      )
    )

    #expect(model.liveTranscript == text)
    #expect(model.boardScene.elements.isEmpty)
    #expect(model.lectureSessionScenes.isEmpty)
    await model.stopWindowCapture()
  }

  @Test func twoStablePartialRevisionsCanReachThePublicSceneBeforeFinal() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider
    )
    let segmentID = UUID()
    let text =
      "Sustainability means meeting present needs without undermining future possibilities."

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: text, id: segmentID, isFinal: false),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscriptPhase == .partial)
    #expect(model.boardScene.elements.isEmpty)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: text, id: segmentID, isFinal: false),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscriptPhase == .partial)
    #expect(!model.boardScene.elements.isEmpty)
    #expect(!model.lectureSessionScenes.isEmpty)
    let sceneAfterPartialCommit = model.boardScene

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: text, id: segmentID),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscriptPhase == .final)
    #expect(model.boardScene == sceneAfterPartialCommit)
    await model.stopWindowCapture()
  }

  @Test func punctuationFreeJapaneseImportancePartialReachesPublicSceneAfterPause() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let pauseWaiter = ControllableStablePartialTranscriptPauseWaiter()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider,
      stablePartialTranscriptPauseWaiter: pauseWaiter
    )
    let text = "ここで重要なのはテストです"

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: TranscriptSegment(
          text: text,
          startTime: 0,
          endTime: 3,
          language: .japanese,
          confidence: 0.8,
          isFinal: false,
          emphasis: 0.5
        ),
        sourceMachTime: mach_absolute_time()
      )
    )

    try await pauseWaiter.waitForInvocationCount(1)
    #expect(model.liveTranscript == text)
    #expect(model.liveTranscriptPhase == .partial)
    #expect(model.boardScene.elements.isEmpty)

    await pauseWaiter.resume(invocation: 0)
    try await waitUntil { !model.boardScene.elements.isEmpty }
    #expect(!model.lectureSessionScenes.isEmpty)
    #expect(model.liveTranscriptPhase == .partial)
    await model.stopWindowCapture()
  }

  @Test func unchangedPartialTextCommitsLatestObservationWithoutRestartingPause() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let pauseWaiter = ControllableStablePartialTranscriptPauseWaiter()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider,
      stablePartialTranscriptPauseWaiter: pauseWaiter
    )
    let segmentID = UUID()
    let text = "ここで重要なのはテストです"

    func observation(endTime: TimeInterval, sourceMachTime: UInt64) -> TranscriptionObservation {
      TranscriptionObservation(
        segment: TranscriptSegment(
          id: segmentID,
          text: text,
          startTime: 0,
          endTime: endTime,
          language: .japanese,
          confidence: 0.8,
          isFinal: false,
          emphasis: 0.5
        ),
        sourceMachTime: sourceMachTime
      )
    }

    transcriptionProvider.emit(
      startIndex: 0,
      observation: observation(endTime: 1, sourceMachTime: 1)
    )
    try await pauseWaiter.waitForInvocationCount(1)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: observation(endTime: 2, sourceMachTime: 2)
    )
    transcriptionProvider.emit(
      startIndex: 0,
      observation: observation(endTime: 3, sourceMachTime: UInt64.max)
    )
    await drainMainActorQueue()
    #expect(await pauseWaiter.invocationCount == 1)

    await pauseWaiter.resume(invocation: 0)
    try await waitUntil { !model.boardScene.elements.isEmpty }
    #expect(model.liveTranscript == text)
    #expect(model.liveTranscriptPhase == .partial)
    await model.stopWindowCapture()
  }

  @Test func supersededPauseCannotCommitAnOlderImportancePartial() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let pauseWaiter = ControllableStablePartialTranscriptPauseWaiter()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider,
      stablePartialTranscriptPauseWaiter: pauseWaiter
    )
    let segmentID = UUID()

    func observation(text: String, endTime: TimeInterval) -> TranscriptionObservation {
      TranscriptionObservation(
        segment: TranscriptSegment(
          id: segmentID,
          text: text,
          startTime: 0,
          endTime: endTime,
          language: .japanese,
          confidence: 0.8,
          isFinal: false,
          emphasis: 0.5
        ),
        sourceMachTime: mach_absolute_time()
      )
    }

    transcriptionProvider.emit(
      startIndex: 0,
      observation: observation(text: "ここで重要なのはテストです", endTime: 2)
    )
    try await pauseWaiter.waitForInvocationCount(1)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: observation(text: "ここで重要なのはテストですが", endTime: 3)
    )
    try await pauseWaiter.waitForInvocationCount(2)

    await pauseWaiter.resume(invocation: 0)
    await drainMainActorQueue()
    #expect(model.boardScene.elements.isEmpty)

    await pauseWaiter.resume(invocation: 1)
    await drainMainActorQueue()
    #expect(model.boardScene.elements.isEmpty)
    await model.stopWindowCapture()
  }

  @Test func manualStopCancelsPendingImportancePartial() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    transcriptionProvider.automaticallyCompletesGracefulStop = false
    let pauseWaiter = ControllableStablePartialTranscriptPauseWaiter()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider,
      stablePartialTranscriptPauseWaiter: pauseWaiter
    )

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: TranscriptSegment(
          text: "ここで重要なのはテストです",
          startTime: 0,
          endTime: 3,
          language: .japanese,
          confidence: 0.8,
          isFinal: false,
          emphasis: 0.5
        ),
        sourceMachTime: mach_absolute_time()
      )
    )
    try await pauseWaiter.waitForInvocationCount(1)

    model.stopTranscription()
    await pauseWaiter.resume(invocation: 0)
    await drainMainActorQueue()

    #expect(model.transcriptionLifecycleState == .finalizing)
    #expect(model.boardScene.elements.isEmpty)
    transcriptionProvider.emitGracefulCompletion(startIndex: 0)
    await model.stopWindowCapture()
  }

  @Test func finalObservationSupersedesItsPendingPartialPause() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let pauseWaiter = ControllableStablePartialTranscriptPauseWaiter()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider,
      stablePartialTranscriptPauseWaiter: pauseWaiter
    )
    let segmentID = UUID()
    let text = "ここで重要なのはテストです"

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: TranscriptSegment(
          id: segmentID,
          text: text,
          startTime: 0,
          endTime: 2,
          language: .japanese,
          confidence: 0.8,
          isFinal: false,
          emphasis: 0.5
        ),
        sourceMachTime: mach_absolute_time()
      )
    )
    try await pauseWaiter.waitForInvocationCount(1)

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: TranscriptSegment(
          id: segmentID,
          text: text,
          startTime: 0,
          endTime: 2,
          language: .japanese,
          confidence: 0.8,
          isFinal: true,
          emphasis: 0.5
        ),
        sourceMachTime: mach_absolute_time()
      )
    )
    try await waitUntil { !model.boardScene.elements.isEmpty }
    let elementsAfterFinal = model.boardScene.elements

    await pauseWaiter.resume(invocation: 0)
    await drainMainActorQueue()
    #expect(model.boardScene.elements == elementsAfterFinal)
    await model.stopWindowCapture()
  }

  @Test func captureBoundaryCancelsPendingImportancePartial() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let pauseWaiter = ControllableStablePartialTranscriptPauseWaiter()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider,
      stablePartialTranscriptPauseWaiter: pauseWaiter
    )

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: TranscriptSegment(
          text: "ここで重要なのはテストです",
          startTime: 0,
          endTime: 3,
          language: .japanese,
          confidence: 0.8,
          isFinal: false,
          emphasis: 0.5
        ),
        sourceMachTime: mach_absolute_time()
      )
    )
    try await pauseWaiter.waitForInvocationCount(1)

    await model.stopWindowCapture()
    await pauseWaiter.resume(invocation: 0)
    await drainMainActorQueue()
    #expect(model.boardScene.elements.isEmpty)
  }

  @Test func groundedProviderStrengthDefinitionQuestionRemainsInternal() async throws {
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = try await makeGroundedDefinitionModel(
      transcriptionProvider: transcriptionProvider
    )
    let text = "What does Sustainability mean?"

    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: providerStrengthSegment(text: text),
        sourceMachTime: mach_absolute_time()
      )
    )

    #expect(model.liveTranscript == text)
    #expect(model.boardScene.elements.isEmpty)
    #expect(model.lectureSessionScenes.isEmpty)
    await model.stopWindowCapture()
  }

  @Test func captureLifecycleInvalidatesEachActiveTranscriptionOperation() async throws {
    let capture = SlideIdentityFrameCapture()
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: capture,
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider
    )

    await model.startTranscription()
    await model.startWindowCapture()
    #expect(transcriptionProvider.stopCount == 1)
    #expect(model.status == .ready)
    transcriptionProvider.emit(
      startIndex: 0,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "before capture"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript.isEmpty)

    await model.startTranscription()
    await capture.emitError("Controlled capture error")
    try await waitUntil {
      if case .error = model.captureStatus { return true }
      return false
    }
    #expect(transcriptionProvider.stopCount == 2)
    transcriptionProvider.emit(
      startIndex: 1,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "before capture error"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript.isEmpty)

    await model.stopWindowCapture()
    await model.startWindowCapture()
    await model.startTranscription()
    await model.stopWindowCapture()
    #expect(transcriptionProvider.stopCount == 3)
    transcriptionProvider.emit(
      startIndex: 2,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "before capture stop"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript.isEmpty)
  }

  @Test func everyManualCanvasBoundaryRequiresATranscriptionRestart() async throws {
    let capture = SlideIdentityFrameCapture()
    let transcriptionProvider = ControllableTranscriptionProvider()
    let model = makeModel(
      capture: capture,
      provider: ControllableSlideIdentityProvider(),
      transcriptionProvider: transcriptionProvider,
      slideCanvasConfirmationMode: .userConfirmed
    )
    let image = try #require(makeImage(width: 80, height: 40))
    let geometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 0, y: 0, width: 80, height: 40),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: 80,
        outputPixelHeight: 40
      )
    )
    let changedGeometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 1, y: 0, width: 79, height: 40),
        scaleFactor: 2,
        contentScale: 1,
        outputPixelWidth: 80,
        outputPixelHeight: 40
      )
    )
    let fullFrameRegion = try #require(
      SlideCanvasRegion(
        NormalizedRect(x: 0, y: 0, width: 1, height: 1)
      )
    )

    await model.startWindowCapture()
    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: image,
        coarseFingerprint: frameFingerprints().coarse,
        contentFingerprint: frameFingerprints().content,
        captureSurfaceGeometry: geometry
      )
    )
    try await waitUntil { model.slideCanvasStatus == .needsConfirmation }

    await model.startTranscription()
    model.beginSlideCanvasSelection()
    #expect(transcriptionProvider.stopCount == 1)

    await model.startTranscription()
    #expect(model.confirmSlideCanvasSelection(fullFrameRegion))
    #expect(transcriptionProvider.stopCount == 2)

    await model.startTranscription()
    model.beginSlideCanvasSelection()
    #expect(transcriptionProvider.stopCount == 3)

    await model.startTranscription()
    model.cancelSlideCanvasSelection()
    #expect(transcriptionProvider.stopCount == 4)

    model.beginSlideCanvasSelection()
    #expect(model.confirmSlideCanvasSelection(fullFrameRegion))
    await model.startTranscription()
    await capture.emit(
      frame(
        sequenceNumber: 2,
        image: image,
        coarseFingerprint: frameFingerprints().coarse,
        contentFingerprint: frameFingerprints().content,
        captureSurfaceGeometry: changedGeometry
      )
    )
    try await waitUntil { model.slideCanvasStatus == .invalidated }
    #expect(transcriptionProvider.stopCount == 5)

    transcriptionProvider.emit(
      startIndex: 4,
      observation: TranscriptionObservation(
        segment: partialSegment(text: "before geometry invalidation"),
        sourceMachTime: mach_absolute_time()
      )
    )
    #expect(model.liveTranscript.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func emptyOccupiedAnalysisKeepsTranscriptBoardProposalsClosed() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }

    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: image,
        coarseFingerprint: fingerprints.coarse,
        contentFingerprint: fingerprints.content
      )
    )
    for sequenceNumber in 2...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: fingerprints.coarse,
          contentFingerprint: fingerprints.content
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(model.latestSlideAnalysis?.occupiedRegions.isEmpty == true)

    model.receive(definitionSegment())
    #expect(model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func rejectsDuplicateOutOfOrderAndWrongTargetObservations() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let candidateSlide = try sample(slideID: 202, slideIndex: 2)
    let wrongIdentity = try #require(
      PowerPointWindowIdentity(
        windowID: 43,
        ownerProcessID: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
      )
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    await provider.emit(sequenceNumber: 4, signal: .available(candidateSlide))
    try await waitUntil { model.slideIdentityState == .establishing }
    await provider.emit(sequenceNumber: 4, signal: .available(candidateSlide))
    await provider.emit(sequenceNumber: 3, signal: .available(candidateSlide))
    await provider.emit(
      sequenceNumber: 5,
      signal: .available(candidateSlide),
      targetIdentity: wrongIdentity
    )
    await drainMainActorQueue()

    #expect(model.slideIdentityState == .establishing)
    #expect(model.slideIdentitySampleCount == 3)
    #expect(model.slideChangeCount == 0)

    await provider.emit(sequenceNumber: 5, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }
    #expect(model.slideIdentitySampleCount == 4)
    #expect(model.slideChangeCount == 0)

    await model.stopWindowCapture()
  }

  @Test func unavailableGapRequiresANewBaselineWithoutInferringAChange() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    await provider.emit(sequenceNumber: 3, signal: .unavailable)
    try await waitUntil { model.slideIdentityState == .interrupted }
    #expect(model.slideIdentityContinuityBreakCount == 1)

    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 5, signal: .available(secondSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    #expect(model.slideIdentitySampleCount == 5)
    #expect(model.slideIdentityContinuityBreakCount == 1)
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 2)
    #expect(model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func candidateIdentityQuarantinesAnalysisAndBoardUpdatesUntilConfirmed() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = CountingSlideIdentityAnalyzer(
      title: "Sustainability",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let model = makeModel(capture: capture, provider: provider, analyzer: analyzer)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let coarseFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: 100, count: 32 * 18)
    )
    let contentFingerprint = ContentFingerprint(
      sampleColumns: 160,
      sampleRows: 90,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 160 * 90
      )
    )
    let definitionSegment = TranscriptSegment(
      text:
        "Sustainability means meeting present needs without undermining future possibilities.",
      startTime: 0,
      endTime: 6,
      language: .englishUS,
      confidence: 0.95,
      emphasis: 0.8
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

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
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(await analyzer.analysisCount == 1)

    model.boardScene = markerScene(slideNumber: 1)
    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    try await waitUntil { model.slideIdentityState == .establishing }
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)

    for sequenceNumber in 4...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    model.receive(definitionSegment)
    await drainMainActorQueue()

    #expect(await analyzer.analysisCount == 1)
    #expect(model.boardScene.slideNumber == 1)
    #expect(model.boardScene.elements.count == 1)

    let preConfirmationTranscriptMachTime = mach_absolute_time()
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }
    #expect(model.boardScene.slideNumber == 2)
    #expect(model.boardScene.elements.isEmpty)

    model.receive(definitionSegment)
    #expect(model.boardScene.elements.isEmpty)

    for sequenceNumber in 7...8 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    await drainMainActorQueue()
    #expect(await analyzer.analysisCount == 1)
    #expect(model.slideAnalysisStatus == .idle)

    await capture.emit(
      frame(
        sequenceNumber: 9,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    for sequenceNumber in 10...11 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(await analyzer.analysisCount == 2)

    model.receive(
      TranscriptionObservation(
        segment: definitionSegment,
        sourceMachTime: preConfirmationTranscriptMachTime
      )
    )
    #expect(model.boardScene.elements.isEmpty)
    #expect(!SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 0, after: nil))
    #expect(SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 1, after: nil))
    #expect(!SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 99, after: 100))
    #expect(!SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 100, after: 100))
    #expect(SlideIdentityTranscriptBoundary.accepts(sourceMachTime: 101, after: 100))

    receiveConfirmedDefinition(on: model)
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func currentSelectionMustStillMatchBeforeAcceptingAnIdentity() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    model.selectedPowerPointWindowID = 43
    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    await drainMainActorQueue()

    #expect(model.slideIdentitySampleCount == 2)
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 1)

    await model.stopWindowCapture()
  }

  @Test func observationsFromAStoppedSessionCannotEnterTheRestartedSession() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let staleSlide = try sample(slideID: 999, slideIndex: 9)

    await model.startWindowCapture()
    await model.stopWindowCapture()
    #expect(model.slideIdentityState == .unavailable)
    await model.startWindowCapture()

    #expect(await provider.startCount == 2)
    await provider.emit(
      startIndex: 0,
      sequenceNumber: 100,
      signal: .available(staleSlide)
    )
    await provider.emit(
      startIndex: 0,
      sequenceNumber: 101,
      signal: .available(staleSlide)
    )
    await drainMainActorQueue()
    #expect(model.slideIdentitySampleCount == 0)

    await provider.emit(startIndex: 1, sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(startIndex: 1, sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    #expect(model.slideIdentitySampleCount == 2)
    #expect(model.slideChangeCount == 0)
    #expect(model.boardScene.slideNumber == 1)

    await model.stopWindowCapture()
  }

  @Test func captureFailuresInterruptOnlyEstablishedIdentityContinuity() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(capture: capture, provider: provider)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    await capture.emitError("controlled capture failure")
    try await waitUntil {
      model.captureStatus == .error("controlled capture failure")
    }

    #expect(model.slideIdentityState == .interrupted)
    #expect(model.slideIdentitySampleCount == 2)
    #expect(model.slideChangeCount == 0)

    let unavailableCapture = SlideIdentityFrameCapture()
    let unavailableProvider = ControllableSlideIdentityProvider()
    let unavailableModel = makeModel(
      capture: unavailableCapture,
      provider: unavailableProvider
    )
    await unavailableModel.startWindowCapture()
    await unavailableCapture.emitError("failure without identity continuity")
    try await waitUntil {
      unavailableModel.captureStatus == .error("failure without identity continuity")
    }
    #expect(unavailableModel.slideIdentityState == .unavailable)
    #expect(unavailableModel.slideIdentitySampleCount == 0)

    let failingProvider = ControllableSlideIdentityProvider()
    let failingModel = makeModel(
      capture: FailingSlideIdentityFrameCapture(),
      provider: failingProvider
    )
    await failingModel.startWindowCapture()
    guard case .error = failingModel.captureStatus else {
      Issue.record("A controlled capture-start failure must be visible.")
      return
    }
    #expect(failingModel.slideIdentityState == .unavailable)
    #expect(failingModel.slideIdentitySampleCount == 0)
  }

  @Test func preConfirmationFramesCannotEstablishTheNewSlideAfterATransition() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = CountingSlideIdentityAnalyzer()
    let model = makeModel(capture: capture, provider: provider, analyzer: analyzer)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let coarseFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: 100, count: 32 * 18)
    )
    let contentFingerprint = ContentFingerprint(
      sampleColumns: 160,
      sampleRows: 90,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 160 * 90
      )
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    let preConfirmationDisplayTime = mach_absolute_time()
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }

    await capture.emit(
      CapturedPowerPointFrame(
        windowID: 42,
        sequenceNumber: 1,
        capturedAt: Date(),
        displayTime: nil,
        deliveryKind: .new,
        image: image,
        fingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 2,
        displayTime: 0,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 3,
        displayTime: preConfirmationDisplayTime,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await capture.emit(
      frame(
        sequenceNumber: 4,
        deliveryKind: .idleRepeat,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    await drainMainActorQueue()
    #expect(model.capturedFrameCount == 4)
    #expect(model.stableFrameCount == 0)
    #expect(await analyzer.analysisCount == 0)

    await capture.emit(
      frame(
        sequenceNumber: 5,
        deliveryKind: .new,
        image: image,
        coarseFingerprint: coarseFingerprint,
        contentFingerprint: contentFingerprint
      )
    )
    for sequenceNumber in 6...7 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(model.stableFrameCount == 1)
    #expect(await analyzer.analysisCount == 1)

    await model.stopWindowCapture()
  }

  @Test func confirmedTransitionRejectsAnInFlightAnalysisFromThePreviousSlide() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = SuspendedSlideIdentityAnalyzer()
    let model = makeModel(capture: capture, provider: provider, analyzer: analyzer)
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)
    let image = try #require(makeImage())
    let coarseFingerprint = FrameFingerprint(
      sampleColumns: 32,
      sampleRows: 18,
      luminance: Array(repeating: 100, count: 32 * 18)
    )
    let contentFingerprint = ContentFingerprint(
      sampleColumns: 160,
      sampleRows: 90,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: 160 * 90
      )
    )

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityState == .identified }

    for sequenceNumber in 1...3 {
      await capture.emit(
        CapturedPowerPointFrame(
          windowID: 42,
          sequenceNumber: UInt64(sequenceNumber),
          capturedAt: Date().addingTimeInterval(TimeInterval(sequenceNumber)),
          displayTime: mach_absolute_time() + UInt64(sequenceNumber),
          deliveryKind: .new,
          image: image,
          fingerprint: coarseFingerprint,
          contentFingerprint: contentFingerprint
        )
      )
    }
    try await analyzer.waitForInvocation(sequenceNumber: 3)
    #expect(model.slideAnalysisStatus == .analyzing)

    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideChangeCount == 1 }
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.latestSlideAnalysis == nil)

    try await analyzer.succeed(sequenceNumber: 3, title: "Stale slide")
    await drainMainActorQueue()

    #expect(model.latestSlideAnalysis == nil)
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.boardScene.slideNumber == 2)

    await model.stopWindowCapture()
  }

  @Test func postBoundaryTimeoutStaysFailClosedAndRecoversOnANewerFrame() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let analyzer = CountingSlideIdentityAnalyzer(
      title: "Sustainability",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let timeoutWaiter = ControllableSlideIdentityFrameTimeoutWaiter()
    let model = makeModel(
      capture: capture,
      provider: provider,
      analyzer: analyzer,
      timeoutWaiter: timeoutWaiter
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    try await timeoutWaiter.waitForInvocationCount(1)

    for sequenceNumber in 1...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: fingerprints.coarse,
          contentFingerprint: fingerprints.content
        )
      )
    }
    model.receive(definitionSegment())
    await drainMainActorQueue()

    #expect(model.capturedFrameCount == 3)
    #expect(model.stableFrameCount == 0)
    #expect(model.slideAnalysisStatus == .idle)
    #expect(model.boardScene.elements.isEmpty)
    #expect(await analyzer.analysisCount == 0)

    await timeoutWaiter.resume(invocation: 0)
    try await waitUntil { model.slideIdentityFrameSyncState == .timedOut }
    #expect(model.slideIdentityState == .identified)
    #expect(model.boardScene.elements.isEmpty)

    await capture.emit(
      frame(
        sequenceNumber: 4,
        deliveryKind: .new,
        image: image,
        coarseFingerprint: fingerprints.coarse,
        contentFingerprint: fingerprints.content
      )
    )
    try await waitUntil { model.slideIdentityFrameSyncState == .synchronized }
    for sequenceNumber in 5...6 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: fingerprints.coarse,
          contentFingerprint: fingerprints.content
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }
    #expect(await analyzer.analysisCount == 1)

    receiveConfirmedDefinition(on: model)
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
    #expect(model.slideIdentityFrameSyncState == .notRequired)
  }

  @Test func transcriptProducedWhileWaitingStaysRejectedAfterFrameSynchronization() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let model = makeModel(
      capture: capture,
      provider: provider,
      analyzer: ImmediateSlideIdentityAnalyzer(
        title: "Sustainability",
        occupiedRegions: boardProposalOccupiedRegions()
      )
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }

    let waitingTranscriptMachTime = mach_absolute_time()
    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: image,
        coarseFingerprint: fingerprints.coarse,
        contentFingerprint: fingerprints.content
      )
    )
    try await waitUntil { model.slideIdentityFrameSyncState == .synchronized }

    model.receive(
      TranscriptionObservation(
        segment: definitionSegment(),
        sourceMachTime: waitingTranscriptMachTime
      )
    )
    #expect(model.boardScene.elements.isEmpty)

    for sequenceNumber in 2...3 {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: .idleRepeat,
          image: image,
          coarseFingerprint: fingerprints.coarse,
          contentFingerprint: fingerprints.content
        )
      )
    }
    try await waitUntil { model.slideAnalysisStatus == .ready }

    receiveConfirmedDefinition(on: model)
    #expect(!model.boardScene.elements.isEmpty)

    await model.stopWindowCapture()
  }

  @Test func staleBoundaryTimeoutCannotChangeANewerWait() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let timeoutWaiter = ControllableSlideIdentityFrameTimeoutWaiter()
    let model = makeModel(
      capture: capture,
      provider: provider,
      timeoutWaiter: timeoutWaiter
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let secondSlide = try sample(slideID: 202, slideIndex: 2)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    try await timeoutWaiter.waitForInvocationCount(1)

    await provider.emit(sequenceNumber: 3, signal: .available(secondSlide))
    try await waitUntil { model.slideIdentityState == .establishing }
    #expect(model.slideIdentityFrameSyncState == .notRequired)

    await provider.emit(sequenceNumber: 4, signal: .available(secondSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    try await timeoutWaiter.waitForInvocationCount(2)

    await timeoutWaiter.resume(invocation: 0)
    await drainMainActorQueue()
    #expect(model.slideIdentityFrameSyncState == .waiting)

    await timeoutWaiter.resume(invocation: 1)
    try await waitUntil { model.slideIdentityFrameSyncState == .timedOut }

    await model.stopWindowCapture()
    #expect(model.slideIdentityFrameSyncState == .notRequired)
  }

  @Test func acceptedFreshFrameCancelsItsPendingTimeout() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let timeoutWaiter = ControllableSlideIdentityFrameTimeoutWaiter()
    let model = makeModel(
      capture: capture,
      provider: provider,
      timeoutWaiter: timeoutWaiter
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)
    let image = try #require(makeImage())
    let fingerprints = frameFingerprints()

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    try await timeoutWaiter.waitForInvocationCount(1)

    await capture.emit(
      frame(
        sequenceNumber: 1,
        image: image,
        coarseFingerprint: fingerprints.coarse,
        contentFingerprint: fingerprints.content
      )
    )
    try await waitUntil { model.slideIdentityFrameSyncState == .synchronized }

    await timeoutWaiter.resume(invocation: 0)
    await drainMainActorQueue()
    #expect(model.slideIdentityFrameSyncState == .synchronized)

    await model.stopWindowCapture()
  }

  @Test func stopInvalidatesAPendingFrameTimeout() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let timeoutWaiter = ControllableSlideIdentityFrameTimeoutWaiter()
    let model = makeModel(
      capture: capture,
      provider: provider,
      timeoutWaiter: timeoutWaiter
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    try await timeoutWaiter.waitForInvocationCount(1)

    await model.stopWindowCapture()
    #expect(model.slideIdentityFrameSyncState == .notRequired)

    await timeoutWaiter.resume(invocation: 0)
    await drainMainActorQueue()
    #expect(model.slideIdentityFrameSyncState == .notRequired)
  }

  @Test func captureErrorAndRestartInvalidateTheOldFrameTimeout() async throws {
    let capture = SlideIdentityFrameCapture()
    let provider = ControllableSlideIdentityProvider()
    let timeoutWaiter = ControllableSlideIdentityFrameTimeoutWaiter()
    let model = makeModel(
      capture: capture,
      provider: provider,
      timeoutWaiter: timeoutWaiter
    )
    let firstSlide = try sample(slideID: 101, slideIndex: 1)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    try await timeoutWaiter.waitForInvocationCount(1)

    await capture.emitError("Controlled capture error")
    try await waitUntil {
      if case .error = model.captureStatus { return true }
      return false
    }
    #expect(model.slideIdentityFrameSyncState == .notRequired)

    await model.startWindowCapture()
    await provider.emit(sequenceNumber: 1, signal: .available(firstSlide))
    await provider.emit(sequenceNumber: 2, signal: .available(firstSlide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    try await timeoutWaiter.waitForInvocationCount(2)

    await timeoutWaiter.resume(invocation: 0)
    await drainMainActorQueue()
    #expect(model.slideIdentityFrameSyncState == .waiting)

    await model.stopWindowCapture()
    await timeoutWaiter.resume(invocation: 1)
    await drainMainActorQueue()
    #expect(model.slideIdentityFrameSyncState == .notRequired)
  }

  @Test func unavailableDefaultProviderNeverStartsAFrameWait() async throws {
    let capture = SlideIdentityFrameCapture()
    let timeoutWaiter = ControllableSlideIdentityFrameTimeoutWaiter()
    let model = makeModel(
      capture: capture,
      provider: UnavailablePowerPointSlideIdentityProvider(),
      timeoutWaiter: timeoutWaiter
    )

    await model.startWindowCapture()
    try await waitUntil { model.slideIdentitySampleCount == 1 }

    #expect(model.slideIdentityState == .unavailable)
    #expect(model.slideIdentityFrameSyncState == .notRequired)
    #expect(await timeoutWaiter.invocationCount == 0)

    await model.stopWindowCapture()
  }

  private func makeModel(
    capture: any PowerPointWindowCapturing,
    provider: any PowerPointSlideIdentityProviding,
    analyzer: any SlideVisualAnalyzing = ImmediateSlideIdentityAnalyzer(),
    transcriptionProvider: any TranscriptionProvider = ControllableTranscriptionProvider(),
    slideCanvasConfirmationMode: SlideCanvasConfirmationMode =
      .testOnlyUseFullCapturedFrame,
    timeoutWaiter: any SlideIdentityFrameTimeoutWaiting =
      TaskSlideIdentityFrameTimeoutWaiter(),
    stablePartialTranscriptPauseWaiter: any StablePartialTranscriptPauseWaiting =
      TaskStablePartialTranscriptPauseWaiter(),
    scanner: any PowerPointWindowScanning = EmptySlideIdentityWindowScanner()
  ) -> AppModel {
    let model = AppModel(
      permissionService: PermissionService(
        screenCaptureClient: SlideIdentityAuthorizedPermissionClient()
      ),
      windowCapture: capture,
      scanner: scanner,
      transcriptionProvider: transcriptionProvider,
      slideIdentityProvider: provider,
      slideVisionAnalyzer: analyzer,
      slideCanvasConfirmationMode: slideCanvasConfirmationMode,
      slideIdentityFrameTimeout: .seconds(2),
      slideIdentityFrameTimeoutWaiter: timeoutWaiter,
      stablePartialTranscriptPauseWaiter: stablePartialTranscriptPauseWaiter
    )
    model.powerPointWindows = [
      PowerPointWindowDescriptor(
        id: 42,
        title: "Synthetic slide identity window",
        applicationName: "Microsoft PowerPoint",
        ownerProcessID: 700,
        bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier,
        frame: .zero
      )
    ]
    model.selectedPowerPointWindowID = 42
    return model
  }

  private func makeGroundedDefinitionModel(
    transcriptionProvider: ControllableTranscriptionProvider,
    stablePartialTranscriptPauseWaiter: any StablePartialTranscriptPauseWaiting =
      TaskStablePartialTranscriptPauseWaiter()
  ) async throws -> AppModel {
    let capture = SlideIdentityFrameCapture()
    let identityProvider = ControllableSlideIdentityProvider()
    let analyzer = CountingSlideIdentityAnalyzer(
      title: "Sustainability",
      occupiedRegions: boardProposalOccupiedRegions()
    )
    let model = makeModel(
      capture: capture,
      provider: identityProvider,
      analyzer: analyzer,
      transcriptionProvider: transcriptionProvider,
      stablePartialTranscriptPauseWaiter: stablePartialTranscriptPauseWaiter
    )
    let slide = try sample(slideID: 101, slideIndex: 1)
    let image = try #require(makeImage())

    await model.startWindowCapture()
    await identityProvider.emit(sequenceNumber: 1, signal: .available(slide))
    await identityProvider.emit(sequenceNumber: 2, signal: .available(slide))
    try await waitUntil { model.slideIdentityFrameSyncState == .waiting }
    await emitStableFrames(
      capture: capture,
      image: image,
      fingerprints: frameFingerprints(),
      sequenceNumbers: 1...3
    )
    try await waitUntil { model.slideAnalysisStatus == .ready }
    await model.startTranscription()
    return model
  }

  private func sample(slideID: Int, slideIndex: Int) throws -> SlideIdentitySample {
    try #require(
      SlideIdentitySample(
        presentationSessionToken: "ephemeral-test-session",
        slideID: slideID,
        slideIndex: slideIndex
      )
    )
  }

  private func makeImage(width: Int = 2, height: Int = 2) -> CGImage? {
    CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )?.makeImage()
  }

  private func frameFingerprints() -> (
    coarse: FrameFingerprint,
    content: ContentFingerprint
  ) {
    (
      FrameFingerprint(
        sampleColumns: 32,
        sampleRows: 18,
        luminance: Array(repeating: 100, count: 32 * 18)
      ),
      ContentFingerprint(
        sampleColumns: 160,
        sampleRows: 90,
        cells: Array(
          repeating: RGBContentCell(red: 255, green: 255, blue: 255),
          count: 160 * 90
        )
      )
    )
  }

  private func definitionSegment(
    text: String =
      "Sustainability means meeting present needs without undermining future possibilities.",
    startTime: TimeInterval = 0,
    endTime: TimeInterval = 6
  ) -> TranscriptSegment {
    TranscriptSegment(
      text: text,
      startTime: startTime,
      endTime: endTime,
      language: .englishUS,
      confidence: 0.95,
      emphasis: 0.8
    )
  }

  private func receiveConfirmedDefinition(
    text: String =
      "Sustainability means meeting present needs without undermining future possibilities.",
    startTime: TimeInterval = 0,
    endTime: TimeInterval = 6,
    on model: AppModel
  ) {
    model.receive(definitionSegment(text: text, startTime: startTime, endTime: endTime))
  }

  private func partialSegment(text: String) -> TranscriptSegment {
    TranscriptSegment(
      text: text,
      startTime: 0,
      endTime: 1,
      language: .englishUS,
      confidence: 0.95,
      isFinal: false,
      emphasis: 0.5
    )
  }

  private func providerStrengthSegment(
    text: String,
    id: UUID = UUID(),
    isFinal: Bool = true,
    confidence: Double = 0.5
  ) -> TranscriptSegment {
    TranscriptSegment(
      id: id,
      text: text,
      startTime: 0,
      endTime: 8,
      language: .englishUS,
      confidence: confidence,
      isFinal: isFinal,
      emphasis: 0.5
    )
  }

  private func emitStableFrames(
    capture: SlideIdentityFrameCapture,
    image: CGImage,
    fingerprints: (coarse: FrameFingerprint, content: ContentFingerprint),
    sequenceNumbers: ClosedRange<Int>
  ) async {
    for sequenceNumber in sequenceNumbers {
      await capture.emit(
        frame(
          sequenceNumber: UInt64(sequenceNumber),
          deliveryKind: sequenceNumber == sequenceNumbers.lowerBound ? .new : .idleRepeat,
          image: image,
          coarseFingerprint: fingerprints.coarse,
          contentFingerprint: fingerprints.content
        )
      )
    }
  }

  private func boardProposalOccupiedRegions() -> [NormalizedRect] {
    [NormalizedRect(x: 0.05, y: 0.05, width: 0.2, height: 0.15)]
  }

  private func frame(
    sequenceNumber: UInt64,
    deliveryKind: CapturedFrameDeliveryKind = .new,
    displayTime: UInt64? = nil,
    image: CGImage,
    coarseFingerprint: FrameFingerprint,
    contentFingerprint: ContentFingerprint,
    captureSurfaceGeometry: CaptureSurfaceGeometry? = nil
  ) -> CapturedPowerPointFrame {
    CapturedPowerPointFrame(
      windowID: 42,
      sequenceNumber: sequenceNumber,
      capturedAt: Date().addingTimeInterval(TimeInterval(sequenceNumber)),
      displayTime: displayTime ?? mach_absolute_time() + sequenceNumber,
      deliveryKind: deliveryKind,
      captureSurfaceGeometry: captureSurfaceGeometry,
      image: image,
      fingerprint: coarseFingerprint,
      contentFingerprint: contentFingerprint
    )
  }

  private func markerScene(slideNumber: Int) -> BoardScene {
    BoardScene(
      slideNumber: slideNumber,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1),
          text: "Existing board content"
        )
      ]
    )
  }

  private func waitUntil(_ predicate: @escaping @MainActor () -> Bool) async throws {
    for _ in 0..<10_000 {
      if predicate() { return }
      await Task.yield()
    }
    throw AppSlideIdentityIntegrationTestError.timedOut
  }

  private func drainMainActorQueue() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }
}

@MainActor
private final class ControllableTranscriptionProvider: TranscriptionProvider {
  private struct Start {
    let operationID: TranscriptionOperationID
    let observationHandler: @MainActor (TranscriptionObservation) -> Void
    let terminalEventHandler: @MainActor (TranscriptionTerminalEvent) -> Void
  }

  private var starts: [Start] = []
  private var suspendedStarts:
    [(
      operationID: TranscriptionOperationID,
      continuation: CheckedContinuation<Void, Never>
    )] = []
  private(set) var stopCount = 0
  var automaticallyCompletesGracefulStop = true
  var suspendStart = false

  var startCount: Int { starts.count }

  func start(
    operationID: TranscriptionOperationID,
    language: LanguageTag,
    onObservation: @escaping @MainActor (TranscriptionObservation) -> Void,
    onTerminalEvent: @escaping @MainActor (TranscriptionTerminalEvent) -> Void
  ) async throws {
    starts.append(
      Start(
        operationID: operationID,
        observationHandler: onObservation,
        terminalEventHandler: onTerminalEvent
      )
    )
    guard suspendStart else { return }
    await withCheckedContinuation { continuation in
      suspendedStarts.append((operationID, continuation))
    }
    throw CancellationError()
  }

  func stop(operationID: TranscriptionOperationID) {
    stopCount += 1
  }

  func finishCurrentSegment(operationID: TranscriptionOperationID) {
    stopCount += 1
    guard automaticallyCompletesGracefulStop else { return }
    guard let start = starts.last(where: { $0.operationID == operationID }) else {
      return
    }
    start.terminalEventHandler(
      TranscriptionTerminalEvent(
        operationID: operationID,
        outcome: .gracefulStopCompleted
      )
    )
    if let continuationIndex = suspendedStarts.lastIndex(where: {
      $0.operationID == operationID
    }) {
      suspendedStarts.remove(at: continuationIndex).continuation.resume()
    }
  }

  func emit(startIndex: Int, observation: TranscriptionObservation) {
    guard starts.indices.contains(startIndex) else { return }
    starts[startIndex].observationHandler(observation)
  }

  func emitTerminal(startIndex: Int, error: TranscriptionError) {
    guard starts.indices.contains(startIndex) else { return }
    let start = starts[startIndex]
    start.terminalEventHandler(
      TranscriptionTerminalEvent(
        operationID: start.operationID,
        error: error
      )
    )
  }

  func emitGracefulCompletion(startIndex: Int) {
    guard starts.indices.contains(startIndex) else { return }
    let start = starts[startIndex]
    start.terminalEventHandler(
      TranscriptionTerminalEvent(
        operationID: start.operationID,
        outcome: .gracefulStopCompleted
      )
    )
  }
}

private struct SlideIdentityProviderStart: Sendable {
  let operationID: CaptureOperationID
  let identity: PowerPointWindowIdentity
  let handler: PowerPointSlideIdentityObservationHandler
}

private actor ControllableSlideIdentityProvider: PowerPointSlideIdentityProviding {
  private var starts: [SlideIdentityProviderStart] = []
  private var stops: [CaptureOperationID] = []

  var startCount: Int { starts.count }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onObservation: @escaping PowerPointSlideIdentityObservationHandler
  ) async {
    starts.append(
      SlideIdentityProviderStart(
        operationID: operationID,
        identity: identity,
        handler: onObservation
      )
    )
  }

  func stop(operationID: CaptureOperationID) async {
    stops.append(operationID)
  }

  func emit(
    startIndex: Int? = nil,
    sequenceNumber: UInt64,
    signal: SlideIdentitySignal,
    targetIdentity: PowerPointWindowIdentity? = nil
  ) {
    guard !starts.isEmpty else { return }
    let index = startIndex ?? starts.index(before: starts.endIndex)
    guard starts.indices.contains(index) else { return }
    let start = starts[index]
    start.handler(
      PowerPointSlideIdentityObservation(
        sequenceNumber: sequenceNumber,
        observedAt: Date(),
        targetIdentity: targetIdentity ?? start.identity,
        signal: signal
      )
    )
  }
}

private actor ControllableSlideIdentityFrameTimeoutWaiter:
  SlideIdentityFrameTimeoutWaiting
{
  private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var nextInvocation = 0

  var invocationCount: Int { nextInvocation }

  func wait(for duration: Duration) async {
    let invocation = nextInvocation
    nextInvocation += 1
    await withCheckedContinuation { continuation in
      continuations[invocation] = continuation
    }
  }

  func waitForInvocationCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if nextInvocation >= expectedCount { return }
      await Task.yield()
    }
    throw AppSlideIdentityIntegrationTestError.timedOut
  }

  func resume(invocation: Int) {
    continuations.removeValue(forKey: invocation)?.resume()
  }
}

private actor ControllableStablePartialTranscriptPauseWaiter:
  StablePartialTranscriptPauseWaiting
{
  private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
  private var nextInvocation = 0

  var invocationCount: Int { nextInvocation }

  func wait(for duration: Duration) async {
    let invocation = nextInvocation
    nextInvocation += 1
    await withCheckedContinuation { continuation in
      continuations[invocation] = continuation
    }
  }

  func waitForInvocationCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if nextInvocation >= expectedCount { return }
      await Task.yield()
    }
    throw AppSlideIdentityIntegrationTestError.timedOut
  }

  func resume(invocation: Int) {
    continuations.removeValue(forKey: invocation)?.resume()
  }
}

private actor SlideIdentityFrameCapture: PowerPointWindowCapturing {
  private var frameHandler: CaptureFrameHandler?
  private var contentUnavailableHandler: CaptureContentUnavailableHandler?
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

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler
  ) async throws {
    frameHandler = onFrame
    contentUnavailableHandler = onContentUnavailable
    errorHandler = { message in
      onFailure(CaptureFailureEventFactory.unclassified(message: message))
    }
  }

  func stop(operationID: CaptureOperationID) async {
    frameHandler = nil
    contentUnavailableHandler = nil
    errorHandler = nil
  }

  func emit(_ frame: CapturedPowerPointFrame) {
    frameHandler?(frame)
  }

  func emitError(_ message: String) {
    errorHandler?(message)
  }

  func emitContentUnavailable(sequenceNumber: UInt64) {
    contentUnavailableHandler?(sequenceNumber)
  }
}

private struct FailingSlideIdentityFrameCapture: PowerPointWindowCapturing {
  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    throw AppSlideIdentityIntegrationTestError.controlledCaptureStartFailure
  }

  func stop(operationID: CaptureOperationID) async {}
}

private struct ImmediateSlideIdentityAnalyzer: SlideVisualAnalyzing {
  var title = ""
  var occupiedRegions: [NormalizedRect] = []

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    SlideVisualAnalysis(title: title, occupiedRegions: occupiedRegions)
  }
}

private actor CountingSlideIdentityAnalyzer: SlideVisualAnalyzing {
  private(set) var analysisCount = 0
  private let title: String
  private let occupiedRegions: [NormalizedRect]

  init(
    title: String = "Current analysis",
    occupiedRegions: [NormalizedRect] = []
  ) {
    self.title = title
    self.occupiedRegions = occupiedRegions
  }

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    analysisCount += 1
    return SlideVisualAnalysis(
      title: title,
      occupiedRegions: occupiedRegions
    )
  }
}

private enum AppSlideIdentityIntegrationTestError: Error {
  case controlledCaptureStartFailure
  case timedOut
  case missingAnalysis(UInt64)
}

private actor SuspendedSlideIdentityAnalyzer: SlideVisualAnalyzing {
  private var invocations: Set<UInt64> = []
  private var continuations: [UInt64: CheckedContinuation<SlideVisualAnalysis, any Error>] = [:]

  func analyze(_ frame: CapturedSlideCanvasFrame) async throws -> SlideVisualAnalysis {
    invocations.insert(frame.sequenceNumber)
    return try await withCheckedThrowingContinuation { continuation in
      continuations[frame.sequenceNumber] = continuation
    }
  }

  func waitForInvocation(sequenceNumber: UInt64) async throws {
    for _ in 0..<10_000 {
      if invocations.contains(sequenceNumber) { return }
      await Task.yield()
    }
    throw AppSlideIdentityIntegrationTestError.timedOut
  }

  func succeed(sequenceNumber: UInt64, title: String) throws {
    guard let continuation = continuations.removeValue(forKey: sequenceNumber) else {
      throw AppSlideIdentityIntegrationTestError.missingAnalysis(sequenceNumber)
    }
    continuation.resume(returning: SlideVisualAnalysis(title: title))
  }
}

private struct EmptySlideIdentityWindowScanner: PowerPointWindowScanning {
  func scan() async throws -> [PowerPointWindowDescriptor] { [] }
}

private struct FailingSlideIdentityWindowScanner: PowerPointWindowScanning {
  func scan() async throws -> [PowerPointWindowDescriptor] {
    throw SlideIdentityWindowScanError.controlled
  }
}

private enum SlideIdentityWindowScanError: LocalizedError {
  case controlled

  var errorDescription: String? {
    "Controlled PowerPoint scan failure"
  }
}

@MainActor
private struct SlideIdentityAuthorizedPermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }

  func requestAccess() -> Bool { true }
}
