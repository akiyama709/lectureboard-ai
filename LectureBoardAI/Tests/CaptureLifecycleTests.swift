import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import LectureBoardCore
import ScreenCaptureKit
import Synchronization
import Testing

@testable import LectureBoard_AI

struct CaptureFailureEventFactoryTests {
  @Test func mapsOnlyTheNamedSDKStreamErrorCodes() {
    let cases: [(SCStreamError.Code, RuntimeSCStreamErrorCode)] = [
      (.userDeclined, .userDeclined),
      (.failedToStart, .failedToStart),
      (.missingEntitlements, .missingEntitlements),
      (.failedApplicationConnectionInvalid, .failedApplicationConnectionInvalid),
      (.failedApplicationConnectionInterrupted, .failedApplicationConnectionInterrupted),
      (.failedNoMatchingApplicationContext, .failedNoMatchingApplicationContext),
      (.attemptToStartStreamState, .attemptToStartStreamState),
      (.attemptToStopStreamState, .attemptToStopStreamState),
      (.attemptToUpdateFilterState, .attemptToUpdateFilterState),
      (.attemptToConfigState, .attemptToConfigState),
      (.internalError, .internalError),
      (.invalidParameter, .invalidParameter),
      (.noWindowList, .noWindowList),
      (.noDisplayList, .noDisplayList),
      (.noCaptureSource, .noCaptureSource),
      (.removingStream, .removingStream),
      (.userStopped, .userStopped),
      (.failedToStartAudioCapture, .failedToStartAudioCapture),
      (.failedToStopAudioCapture, .failedToStopAudioCapture),
      (.failedToStartMicrophoneCapture, .failedToStartMicrophoneCapture),
      (.systemStoppedStream, .systemStoppedStream),
    ]

    #expect(cases.count == 21)
    for (sdkCode, reportCode) in cases {
      #expect(RuntimeSCStreamErrorCodeNormalizer.normalize(sdkCode.rawValue) == reportCode)
    }
    #expect(RuntimeSCStreamErrorCodeNormalizer.normalize(-99_999) == nil)
  }

  @Test func classifiesDelegateAndStartErrorsWithoutRetainingUnboundedMetadata() {
    let privateSentinel = "private-provider-detail"
    let known = NSError(
      domain: SCStreamErrorDomain,
      code: SCStreamError.Code.internalError.rawValue,
      userInfo: [NSLocalizedDescriptionKey: privateSentinel, "private-key": privateSentinel]
    )
    let unknownSC = NSError(
      domain: SCStreamErrorDomain,
      code: -99_999,
      userInfo: [NSLocalizedDescriptionKey: privateSentinel]
    )
    let other = NSError(
      domain: "private.example.error",
      code: SCStreamError.Code.internalError.rawValue,
      userInfo: [NSLocalizedDescriptionKey: privateSentinel]
    )

    let knownDelegate = CaptureFailureEventFactory.delegateStopped(error: known)
    #expect(knownDelegate.source == .delegateStoppedWithKnownSCError)
    #expect(knownDelegate.scStreamErrorCode == .internalError)
    #expect(knownDelegate.message == privateSentinel)

    let unknownSCDelegate = CaptureFailureEventFactory.delegateStopped(error: unknownSC)
    #expect(unknownSCDelegate.source == .delegateStoppedWithUnknownSCError)
    #expect(unknownSCDelegate.scStreamErrorCode == nil)

    let otherDelegate = CaptureFailureEventFactory.delegateStopped(error: other)
    #expect(otherDelegate.source == .delegateStoppedWithUnknownError)
    #expect(otherDelegate.scStreamErrorCode == nil)

    let knownStart = CaptureFailureEventFactory.startFailed(error: known)
    #expect(knownStart.source == .startFailedWithKnownSCError)
    #expect(knownStart.scStreamErrorCode == .internalError)

    let unknownSCStart = CaptureFailureEventFactory.startFailed(error: unknownSC)
    #expect(unknownSCStart.source == .startFailedWithUnknownSCError)
    #expect(unknownSCStart.scStreamErrorCode == nil)

    let otherStart = CaptureFailureEventFactory.startFailed(error: other)
    #expect(otherStart.source == .startFailedWithUnknownError)
    #expect(otherStart.scStreamErrorCode == nil)
  }

  @Test func classifiesBoundedTerminalSignalsWithoutAnErrorCode() {
    let stopped = CaptureFailureEventFactory.sampleStatusStopped(message: "stopped")
    #expect(stopped.source == .sampleStatusStopped)
    #expect(stopped.scStreamErrorCode == nil)

    let inactive = CaptureFailureEventFactory.delegateBecameInactive(message: "inactive")
    #expect(inactive.source == .delegateBecameInactive)
    #expect(inactive.scStreamErrorCode == nil)

    let unclassified = CaptureFailureEventFactory.unclassified(message: "unknown")
    #expect(unclassified.source == .unclassifiedCaptureFailure)
    #expect(unclassified.scStreamErrorCode == nil)
  }
}

struct CaptureTerminalFailureGateTests {
  @Test func firstTerminalCallbackWinsSynchronouslyForEveryBackToBackOrdering() {
    let events = terminalFailureEvents()

    for firstIndex in events.indices {
      let gate = CaptureTerminalFailureGate()
      let recorder = CaptureFailureEventRecorder()
      let remainingEvents = events.enumerated().compactMap { index, event in
        index == firstIndex ? nil : event
      }
      let orderedEvents = [events[firstIndex]] + remainingEvents

      let accepted = orderedEvents.map { event in
        gate.report(event, to: recorder.record)
      }

      #expect(accepted == [true, false, false])
      #expect(recorder.events == [events[firstIndex]])
    }
  }

  @Test func routerSharesOneGateAcrossEveryCaptureOutputTerminalEntry() {
    let delegateError = NSError(
      domain: SCStreamErrorDomain,
      code: SCStreamError.Code.internalError.rawValue,
      userInfo: [NSLocalizedDescriptionKey: "delegate stopped"]
    )
    let expectedEvents = [
      CaptureFailureEventFactory.sampleStatusStopped(message: "sample stopped"),
      CaptureFailureEventFactory.delegateStopped(error: delegateError),
      CaptureFailureEventFactory.delegateBecameInactive(message: "inactive"),
    ]

    for firstIndex in expectedEvents.indices {
      let recorder = CaptureFailureEventRecorder()
      let router = CaptureTerminalFailureRouter(failureHandler: recorder.record)
      let actions: [() -> Bool] = [
        { router.reportSampleStatusStopped(message: "sample stopped") },
        { router.reportDelegateStopped(error: delegateError) },
        { router.reportDelegateBecameInactive(message: "inactive") },
      ]
      let remainingIndices = expectedEvents.indices.filter { $0 != firstIndex }
      let orderedIndices = [firstIndex] + remainingIndices

      let accepted = orderedIndices.map { actions[$0]() }

      #expect(accepted == [true, false, false])
      #expect(recorder.events == [expectedEvents[firstIndex]])
    }
  }

  @Test func exactlyOneConcurrentTerminalCallbackPassesTheSynchronousBoundary() async {
    for _ in 0..<100 {
      let events = terminalFailureEvents()
      let gate = CaptureTerminalFailureGate()
      let recorder = CaptureFailureEventRecorder()
      let barrier = CaptureFailureAsyncBarrier(participantCount: events.count)

      let acceptedCount = await withTaskGroup(of: Bool.self) { group in
        for event in events {
          group.addTask {
            await barrier.arriveAndWait()
            return gate.report(event, to: recorder.record)
          }
        }

        var count = 0
        for await accepted in group where accepted {
          count += 1
        }
        return count
      }

      #expect(acceptedCount == 1)
      #expect(recorder.events.count == 1)
      if let recordedEvent = recorder.events.first {
        #expect(events.contains(recordedEvent))
      }
    }
  }

  private func terminalFailureEvents() -> [CaptureFailureEvent] {
    [
      CaptureFailureEventFactory.sampleStatusStopped(message: "sample stopped"),
      CaptureFailureEventFactory.delegateStopped(
        error: NSError(
          domain: SCStreamErrorDomain,
          code: SCStreamError.Code.internalError.rawValue,
          userInfo: [NSLocalizedDescriptionKey: "delegate stopped"]
        )
      ),
      CaptureFailureEventFactory.delegateBecameInactive(message: "inactive"),
    ]
  }
}

struct CaptureSessionLifecycleTests {
  @Test func rejectsAStartThatArrivesAfterANewerStop() {
    var lifecycle = CaptureSessionLifecycle()

    let acceptedStop = lifecycle.acceptStop(CaptureOperationID(rawValue: 2))
    let acceptedOldStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 1))
    #expect(acceptedStop)
    #expect(acceptedOldStart == false)
    #expect(lifecycle.activeSessionID == nil)
    #expect(lifecycle.latestOperationID == CaptureOperationID(rawValue: 2))
  }

  @Test func rejectsAnOldStopThatArrivesAfterANewerStart() {
    var lifecycle = CaptureSessionLifecycle()

    let acceptedFirstStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 1))
    let acceptedStop = lifecycle.acceptStop(CaptureOperationID(rawValue: 2))
    let acceptedSecondStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 3))
    let acceptedOldStop = lifecycle.acceptStop(CaptureOperationID(rawValue: 2))
    #expect(acceptedFirstStart)
    #expect(acceptedStop)
    #expect(acceptedSecondStart)
    #expect(acceptedOldStop == false)
    #expect(lifecycle.activeSessionID == CaptureOperationID(rawValue: 3))
  }

  @Test func anOldStartFailureCannotClearTheNewSession() {
    var lifecycle = CaptureSessionLifecycle()

    let acceptedFirstStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 1))
    let acceptedSecondStart = lifecycle.acceptStart(CaptureOperationID(rawValue: 2))
    lifecycle.finishFailedStart(CaptureOperationID(rawValue: 1))

    #expect(acceptedFirstStart)
    #expect(acceptedSecondStart)
    #expect(lifecycle.activeSessionID == CaptureOperationID(rawValue: 2))
  }
}

struct FreshSampleCaptureLifecycleTests {
  @Test func acceptsOnlyOneRequestForTheExactActiveCapture() throws {
    var lifecycle = FreshSampleCaptureLifecycle()
    let operationID = CaptureOperationID(rawValue: 7)
    let identity = try #require(makeIdentity(windowID: 71, processID: 701))
    let firstRequestID = FreshSampleRequestID()
    let secondRequestID = FreshSampleRequestID()

    lifecycle.activate(operationID: operationID, identity: identity)

    let acceptedFirstRequest = lifecycle.beginRequest(
      firstRequestID,
      operationID: operationID,
      identity: identity
    )
    let acceptedSecondRequest = lifecycle.beginRequest(
      secondRequestID,
      operationID: operationID,
      identity: identity
    )
    #expect(acceptedFirstRequest)
    #expect(!acceptedSecondRequest)
    #expect(
      lifecycle.acceptsCompletion(
        requestID: firstRequestID,
        operationID: operationID,
        identity: identity
      )
    )
  }

  @Test func rejectsOperationAndIdentityMismatches() throws {
    var lifecycle = FreshSampleCaptureLifecycle()
    let operationID = CaptureOperationID(rawValue: 8)
    let identity = try #require(makeIdentity(windowID: 81, processID: 801))
    let otherIdentity = try #require(makeIdentity(windowID: 81, processID: 802))
    let requestID = FreshSampleRequestID()

    lifecycle.activate(operationID: operationID, identity: identity)

    let acceptedWrongOperation = lifecycle.beginRequest(
      requestID,
      operationID: CaptureOperationID(rawValue: 9),
      identity: identity
    )
    let acceptedWrongIdentity = lifecycle.beginRequest(
      requestID,
      operationID: operationID,
      identity: otherIdentity
    )
    #expect(!acceptedWrongOperation)
    #expect(!acceptedWrongIdentity)
    #expect(lifecycle.inFlightRequestID == nil)
  }

  @Test func invalidatedInFlightRequestKeepsTheProviderBusyUntilItReturns() throws {
    var lifecycle = FreshSampleCaptureLifecycle()
    let oldOperationID = CaptureOperationID(rawValue: 10)
    let newOperationID = CaptureOperationID(rawValue: 11)
    let oldIdentity = try #require(makeIdentity(windowID: 101, processID: 1_001))
    let newIdentity = try #require(makeIdentity(windowID: 111, processID: 1_101))
    let oldRequestID = FreshSampleRequestID()
    let newRequestID = FreshSampleRequestID()

    lifecycle.activate(operationID: oldOperationID, identity: oldIdentity)
    let acceptedOldRequest = lifecycle.beginRequest(
      oldRequestID,
      operationID: oldOperationID,
      identity: oldIdentity
    )
    #expect(acceptedOldRequest)

    lifecycle.deactivate()
    lifecycle.activate(operationID: newOperationID, identity: newIdentity)

    #expect(
      !lifecycle.acceptsCompletion(
        requestID: oldRequestID,
        operationID: oldOperationID,
        identity: oldIdentity
      )
    )
    let acceptedNewRequestWhileOldIsInFlight = lifecycle.beginRequest(
      newRequestID,
      operationID: newOperationID,
      identity: newIdentity
    )
    #expect(!acceptedNewRequestWhileOldIsInFlight)

    lifecycle.finishRequest(oldRequestID)
    let acceptedNewRequestAfterOldFinished = lifecycle.beginRequest(
      newRequestID,
      operationID: newOperationID,
      identity: newIdentity
    )
    #expect(acceptedNewRequestAfterOldFinished)
  }

  @Test func staleFinishCannotReleaseANewerRequest() throws {
    var lifecycle = FreshSampleCaptureLifecycle()
    let operationID = CaptureOperationID(rawValue: 12)
    let identity = try #require(makeIdentity(windowID: 121, processID: 1_201))
    let staleRequestID = FreshSampleRequestID()
    let currentRequestID = FreshSampleRequestID()

    lifecycle.activate(operationID: operationID, identity: identity)
    let acceptedCurrentRequest = lifecycle.beginRequest(
      currentRequestID,
      operationID: operationID,
      identity: identity
    )
    #expect(acceptedCurrentRequest)

    lifecycle.finishRequest(staleRequestID)

    #expect(lifecycle.inFlightRequestID == currentRequestID)
  }

  private func makeIdentity(
    windowID: CGWindowID,
    processID: pid_t
  ) -> PowerPointWindowIdentity? {
    PowerPointWindowIdentity(
      windowID: windowID,
      ownerProcessID: processID,
      bundleIdentifier: PowerPointWindowIdentity.expectedBundleIdentifier
    )
  }
}

struct FreshPowerPointSampleBufferConverterTests {
  @Test func acceptsOnlyANewBGRAFrameWithCompleteSurfaceGeometry() throws {
    let capturedAt = Date(timeIntervalSince1970: 123)
    let sampleBuffer = try #require(
      makeSampleBuffer(status: .complete, includesSurfaceGeometry: true)
    )

    let surface = try #require(
      FreshPowerPointSampleBufferConverter.makeSurface(
        from: sampleBuffer,
        capturedAt: capturedAt
      )
    )

    #expect(surface.capturedAt == capturedAt)
    #expect(surface.image.width == 4)
    #expect(surface.image.height == 2)
    #expect(surface.captureSurfaceGeometry.outputPixelWidth == 4)
    #expect(surface.captureSurfaceGeometry.outputPixelHeight == 2)
    #expect(surface.captureSurfaceGeometry.contentRect == CGRect(x: 0, y: 0, width: 4, height: 2))
  }

  @Test func rejectsIdleOrIncompleteSurfaceEvidence() throws {
    let idle = try #require(
      makeSampleBuffer(status: .idle, includesSurfaceGeometry: true)
    )
    let missingGeometry = try #require(
      makeSampleBuffer(status: .complete, includesSurfaceGeometry: false)
    )
    let wrongPixelFormat = try #require(
      makeSampleBuffer(
        status: .complete,
        includesSurfaceGeometry: true,
        pixelFormat: kCVPixelFormatType_32ARGB
      )
    )

    #expect(
      FreshPowerPointSampleBufferConverter.makeSurface(
        from: idle,
        capturedAt: .distantPast
      ) == nil
    )
    #expect(
      FreshPowerPointSampleBufferConverter.makeSurface(
        from: missingGeometry,
        capturedAt: .distantPast
      ) == nil
    )
    #expect(
      FreshPowerPointSampleBufferConverter.makeSurface(
        from: wrongPixelFormat,
        capturedAt: .distantPast
      ) == nil
    )
  }

  private func makeSampleBuffer(
    status: SCFrameStatus,
    includesSurfaceGeometry: Bool,
    pixelFormat: OSType = kCVPixelFormatType_32BGRA
  ) -> CMSampleBuffer? {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    guard
      CVPixelBufferCreate(
        kCFAllocatorDefault,
        4,
        2,
        pixelFormat,
        attributes as CFDictionary,
        &pixelBuffer
      ) == kCVReturnSuccess,
      let pixelBuffer
    else {
      return nil
    }

    var formatDescription: CMVideoFormatDescription?
    guard
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescriptionOut: &formatDescription
      ) == noErr,
      let formatDescription
    else {
      return nil
    }

    var timing = CMSampleTimingInfo(
      duration: .invalid,
      presentationTimeStamp: .zero,
      decodeTimeStamp: .invalid
    )
    var sampleBuffer: CMSampleBuffer?
    guard
      CMSampleBufferCreateReadyWithImageBuffer(
        allocator: kCFAllocatorDefault,
        imageBuffer: pixelBuffer,
        formatDescription: formatDescription,
        sampleTiming: &timing,
        sampleBufferOut: &sampleBuffer
      ) == noErr,
      let sampleBuffer,
      let attachmentArray = CMSampleBufferGetSampleAttachmentsArray(
        sampleBuffer,
        createIfNecessary: true
      ) as NSArray?,
      let attachments = attachmentArray.firstObject as? NSMutableDictionary
    else {
      return nil
    }

    attachments[SCStreamFrameInfo.status] = NSNumber(value: status.rawValue)
    if includesSurfaceGeometry {
      attachments[SCStreamFrameInfo.contentRect] = NSValue(
        rect: CGRect(x: 0, y: 0, width: 4, height: 2)
      )
      attachments[SCStreamFrameInfo.scaleFactor] = NSNumber(value: 2.0)
      attachments[SCStreamFrameInfo.contentScale] = NSNumber(value: 1.0)
    }
    return sampleBuffer
  }
}

struct FrameFingerprintSamplerTests {
  @Test func authoritativePixelCropUsesInwardScaledBoundsWithoutChangingLegacySampling() throws {
    let pixelBuffer = try #require(
      makeFingerprintPixelBuffer(
        width: 8,
        height: 4,
        whiteRegion: CGRect(x: 1, y: 0, width: 5, height: 4)
      )
    )
    let geometry = try #require(
      CaptureSurfaceGeometry(
        contentRect: CGRect(x: 0.25, y: 0, width: 3, height: 2.000_000_1),
        scaleFactor: 2,
        contentScale: 0.022_222_22,
        outputPixelWidth: 8,
        outputPixelHeight: 4
      )
    )
    let crop = try #require(FrameFingerprintSampler.PixelCrop(surfaceGeometry: geometry))
    #expect(crop.x == 1)
    #expect(crop.y == 0)
    #expect(crop.width == 5)
    #expect(crop.height == 4)

    let cropped = try #require(
      FrameFingerprintSampler.makeFingerprint(from: pixelBuffer, pixelCrop: crop)
    )
    let legacy = try #require(FrameFingerprintSampler.makeFingerprint(from: pixelBuffer))
    #expect(cropped.luminance.allSatisfy { $0 == 255 })
    #expect(legacy.luminance.contains(0))
    #expect(legacy.luminance.contains(255))
  }
}

private func makeFingerprintPixelBuffer(
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
      let isWhite = whiteRegion.contains(CGPoint(x: CGFloat(x), y: CGFloat(y)))
      let value: UInt8 = isWhite ? 255 : 0
      let offset = y * bytesPerRow + x * 4
      bytes[offset] = value
      bytes[offset + 1] = value
      bytes[offset + 2] = value
      bytes[offset + 3] = 255
    }
  }
  return pixelBuffer
}

@MainActor
struct AppModelCaptureLifecycleTests {
  @Test func terminationCleanupDoesNotStopProvidersAgainWhenAlreadyStopped() async {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    #expect(await model.prepareForApplicationTermination())
    let stopInvocationCount = await capture.stopInvocationCount
    #expect(stopInvocationCount == 0)
    #expect(model.captureStatus == .stopped)
  }

  @Test func terminationCleanupDoesNotRepeatProviderStopForCleanedErrorState() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)
    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.failStart(start.operationID)
    await startTask.value

    guard case .error = model.captureStatus else {
      Issue.record("Expected a provider-cleaned capture error state")
      return
    }
    let stopsBeforeTermination = await capture.stopInvocationCount
    #expect(stopsBeforeTermination == 1)

    #expect(await model.prepareForApplicationTermination())
    let stopsAfterTermination = await capture.stopInvocationCount
    #expect(stopsAfterTermination == stopsBeforeTermination)
  }

  @Test func terminationLatchRejectsAQueuedStartWhileProviderStopIsSuspended() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let model = makeModel(capture: capture)
    let initialStartTask = Task { await model.startWindowCapture() }
    let initialStart = try await capture.startInvocation(at: 0)
    await capture.resumeStart(initialStart.operationID)
    await initialStartTask.value

    let terminationTask = Task { await model.prepareForApplicationTermination() }
    let terminatingStop = try await capture.stopInvocation(at: 0)
    let queuedStart = Task { await model.startWindowCapture() }
    await queuedStart.value

    let startsWhileTerminationIsSuspended = await capture.startInvocationCount
    #expect(startsWhileTerminationIsSuspended == 1)
    await capture.resumeStop(terminatingStop)
    #expect(await terminationTask.value)
    #expect(await capture.startInvocationCount == 1)
  }

  @Test func supersededStartCannotStopOrOverwriteTheNewCapture() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    let firstStartTask = Task { await model.startWindowCapture() }
    let firstStart = try await capture.startInvocation(at: 0)

    await model.stopWindowCapture()
    #expect(model.captureStatus == .stopped)

    let secondStartTask = Task { await model.startWindowCapture() }
    let secondStart = try await capture.startInvocation(at: 1)
    await capture.resumeStart(secondStart.operationID)
    await secondStartTask.value
    #expect(model.captureStatus == .capturing)

    await capture.resumeStart(firstStart.operationID)
    await firstStartTask.value

    #expect(model.captureStatus == .capturing)
    let stopInvocationCount = await capture.stopInvocationCount
    #expect(stopInvocationCount == 1)
    #expect(firstStart.operationID < secondStart.operationID)

    await model.stopWindowCapture()
  }

  @Test func completedStartStopsWhenItsSelectedWindowChanged() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    model.selectedPowerPointWindowID = 43
    await capture.resumeStart(start.operationID)
    await startTask.value

    #expect(model.captureStatus == .stopped)
    let stopOperationID = try await capture.stopInvocation(at: 0)
    #expect(start.operationID < stopOperationID)
  }

  @Test func startPassesTheFrozenWindowIdentityToCapture() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)

    #expect(start.identity.windowID == 42)
    #expect(start.identity.ownerProcessID == 700)
    #expect(
      start.identity.bundleIdentifier
        == PowerPointWindowIdentity.expectedBundleIdentifier
    )

    await capture.resumeStart(start.operationID)
    await startTask.value
    #expect(model.captureStatus == .capturing)
    await model.stopWindowCapture()
  }

  @Test func completedStartStopsAfterSameWindowIDChangesOwnerProcess() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    model.powerPointWindows = [makeWindow(id: 42, ownerProcessID: 701)]
    await capture.resumeStart(start.operationID)
    await startTask.value

    #expect(start.identity.ownerProcessID == 700)
    #expect(model.captureStatus == .stopped)
    let stopOperationID = try await capture.stopInvocation(at: 0)
    #expect(start.operationID < stopOperationID)
  }

  @Test func refreshStopsCaptureAfterSameWindowIDChangesOwnerProcess() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let replacement = makeWindow(id: 42, ownerProcessID: 701)
    let model = makeModel(
      capture: capture,
      scanner: FixedWindowScanner(windows: [replacement])
    )

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value
    #expect(model.captureStatus == .capturing)

    await model.refreshPowerPointWindows()

    #expect(model.captureStatus == .stopped)
    #expect(model.selectedWindow?.identity == replacement.identity)
    let stopOperationID = try await capture.stopInvocation(at: 0)
    #expect(start.operationID < stopOperationID)
  }

  @Test func refreshPreservesCaptureForTheSameExactWindowIdentity() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let sameWindow = makeWindow(id: 42, ownerProcessID: 700)
    let model = makeModel(
      capture: capture,
      scanner: FixedWindowScanner(windows: [sameWindow])
    )

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value
    let sessionBeforeRefresh = try #require(model.activeCaptureSessionID(for: 42))

    await model.refreshPowerPointWindows()

    let stopInvocationCount = await capture.stopInvocationCount
    #expect(model.captureStatus == .capturing)
    #expect(model.activeCaptureSessionID(for: 42) == sessionBeforeRefresh)
    #expect(stopInvocationCount == 0)

    await model.stopWindowCapture()
  }

  @Test func sceneActivationRefreshDoesNotScanOrStopAnActiveCapture() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let scanner = ControllableWindowScanner()
    let model = makeModel(capture: capture, scanner: scanner)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value
    #expect(model.captureStatus == .capturing)

    await model.refreshPowerPointWindowsAfterSceneActivation()

    let scanInvocationCount = await scanner.invocationCount
    let stopInvocationCount = await capture.stopInvocationCount
    #expect(scanInvocationCount == 0)
    #expect(stopInvocationCount == 0)
    #expect(model.captureStatus == .capturing)
    #expect(model.activeCaptureSessionID(for: 42) == start.operationID)

    await model.stopWindowCapture()
  }

  @Test func sceneActivationRefreshCannotMutateOrStopACaptureStartedDuringScan() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let scanner = ControllableWindowScanner()
    let model = makeModel(capture: capture, scanner: scanner)

    let refreshTask = Task { await model.refreshPowerPointWindowsAfterSceneActivation() }
    try await scanner.waitForInvocationCount(1)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value
    #expect(model.captureStatus == .capturing)

    await scanner.resumeScan(at: 0, with: [makeWindow(id: 43, ownerProcessID: 701)])
    await refreshTask.value

    let stopInvocationCount = await capture.stopInvocationCount
    #expect(stopInvocationCount == 0)
    #expect(model.powerPointWindows.map(\.id) == [42])
    #expect(model.selectedPowerPointWindowID == 42)
    #expect(model.captureStatus == .capturing)
    #expect(model.activeCaptureSessionID(for: 42) == start.operationID)

    await model.stopWindowCapture()
  }

  @Test func startRejectsAnIDMissingFromTheLatestWindowList() async {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)
    model.powerPointWindows = []

    await model.startWindowCapture()

    guard case .error = model.captureStatus else {
      Issue.record("Expected a missing selected window to produce a capture error.")
      return
    }
    let startInvocationCount = await capture.startInvocationCount
    #expect(startInvocationCount == 0)
  }

  @Test func anOldStopCompletionCannotOverwriteTheNewCapture() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let model = makeModel(capture: capture)

    let firstStartTask = Task { await model.startWindowCapture() }
    let firstStart = try await capture.startInvocation(at: 0)
    await capture.resumeStart(firstStart.operationID)
    await firstStartTask.value
    #expect(model.captureStatus == .capturing)
    let delayedSelectionStopSessionID = model.activeCaptureSessionID(for: 42)

    let firstStopTask = Task { await model.stopWindowCapture() }
    let firstStop = try await capture.stopInvocation(at: 0)
    #expect(model.captureStatus == .stopped)

    let secondStartTask = Task { await model.startWindowCapture() }
    let secondStart = try await capture.startInvocation(at: 1)
    await capture.resumeStart(secondStart.operationID)
    await secondStartTask.value
    #expect(model.captureStatus == .capturing)

    if let delayedSelectionStopSessionID {
      await model.stopWindowCapture(ifCurrentSessionID: delayedSelectionStopSessionID)
    }
    let stopInvocationCount = await capture.stopInvocationCount
    #expect(stopInvocationCount == 1)
    #expect(model.captureStatus == .capturing)

    await capture.resumeStop(firstStop)
    await firstStopTask.value
    #expect(model.captureStatus == .capturing)
    #expect(firstStart.operationID < firstStop)
    #expect(firstStop < secondStart.operationID)

    let cleanupTask = Task { await model.stopWindowCapture() }
    let cleanupStop = try await capture.stopInvocation(at: 1)
    await capture.resumeStop(cleanupStop)
    await cleanupTask.value
  }

  @Test func olderRefreshCannotOverwriteANewerWindowListAndSelection() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let scanner = ControllableWindowScanner()
    let model = makeModel(capture: capture, scanner: scanner)

    let firstRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(1)
    await scanner.resumeScan(at: 0, with: [makeWindow(id: 43)])
    let firstRefreshStop = try await capture.stopInvocation(at: 0)

    let secondRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(2)
    await scanner.resumeScan(
      at: 1,
      with: [makeWindow(id: 42), makeWindow(id: 44)]
    )
    await secondRefreshTask.value

    await capture.resumeStop(firstRefreshStop)
    await firstRefreshTask.value

    #expect(model.powerPointWindows.map(\.id) == [42, 44])
    #expect(model.selectedPowerPointWindowID == 42)
    #expect(model.status == .ready)
  }

  @Test func olderRefreshErrorCannotOverwriteANewerSuccess() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let scanner = ControllableWindowScanner()
    let model = makeModel(capture: capture, scanner: scanner)

    let firstRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(1)
    let secondRefreshTask = Task { await model.refreshPowerPointWindows() }
    try await scanner.waitForInvocationCount(2)

    await scanner.resumeScan(at: 1, with: [makeWindow(id: 42)])
    await secondRefreshTask.value
    await scanner.failScan(at: 0)
    await firstRefreshTask.value

    #expect(model.powerPointWindows.map(\.id) == [42])
    #expect(model.selectedPowerPointWindowID == 42)
    #expect(model.status == .ready)
  }

  @Test func captureErrorIsVisibleBeforeAsynchronousStopCompletes() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value
    #expect(model.captureStatus == .capturing)

    await capture.emitError("controlled capture failure", for: start.operationID)
    let errorStop = try await capture.stopInvocation(at: 0)

    #expect(model.captureStatus == .error("controlled capture failure"))
    #expect(model.captureFailureSource == .unclassifiedCaptureFailure)
    #expect(model.captureSCStreamErrorCode == nil)

    let recoveryTask = Task { await model.startWindowCapture() }
    let recoveryStart = try await capture.startInvocation(at: 1)
    #expect(model.captureFailureSource == nil)
    #expect(model.captureSCStreamErrorCode == nil)
    await capture.resumeStart(recoveryStart.operationID)
    await recoveryTask.value
    #expect(model.captureStatus == .capturing)
    #expect(model.captureFailureSource == nil)
    #expect(model.captureSCStreamErrorCode == nil)

    await capture.emitFailure(
      CaptureFailureEvent(
        message: "stale private provider detail",
        source: .delegateStoppedWithKnownSCError,
        scStreamErrorCode: .internalError
      ),
      for: start.operationID
    )
    await waitForMainActorQueueDrain()
    #expect(model.captureStatus == .capturing)
    #expect(model.captureFailureSource == nil)
    #expect(model.captureSCStreamErrorCode == nil)

    await capture.resumeStop(errorStop)
    #expect(model.captureStatus == .capturing)

    let cleanupTask = Task { await model.stopWindowCapture() }
    let cleanupStop = try await capture.stopInvocation(at: 1)
    await capture.resumeStop(cleanupStop)
    await cleanupTask.value
  }

  @Test func firstDetailedTerminalFailureWinsAndManualStopClearsTelemetry() async throws {
    let capture = ControllableWindowCapture(suspendsStops: false)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value

    await capture.emitFailure(
      CaptureFailureEvent(
        message: "first failure",
        source: .delegateStoppedWithKnownSCError,
        scStreamErrorCode: .internalError
      ),
      for: start.operationID
    )
    _ = try await capture.stopInvocation(at: 0)
    #expect(model.captureStatus == .error("first failure"))
    #expect(model.captureFailureSource == .delegateStoppedWithKnownSCError)
    #expect(model.captureSCStreamErrorCode == .internalError)

    await capture.emitFailure(
      CaptureFailureEvent(
        message: "later failure",
        source: .delegateBecameInactive,
        scStreamErrorCode: nil
      ),
      for: start.operationID
    )
    await waitForMainActorQueueDrain()
    #expect(model.captureStatus == .error("first failure"))
    #expect(model.captureFailureSource == .delegateStoppedWithKnownSCError)
    #expect(model.captureSCStreamErrorCode == .internalError)

    await model.stopWindowCapture()
    #expect(model.captureStatus == .stopped)
    #expect(model.captureFailureSource == nil)
    #expect(model.captureSCStreamErrorCode == nil)
  }

  @Test func manualStopClearsTelemetryBeforeProviderShutdownCompletes() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let model = makeModel(capture: capture)

    let startTask = Task { await model.startWindowCapture() }
    let start = try await capture.startInvocation(at: 0)
    await capture.resumeStart(start.operationID)
    await startTask.value

    await capture.emitFailure(
      CaptureFailureEvent(
        message: "controlled detailed failure",
        source: .delegateStoppedWithKnownSCError,
        scStreamErrorCode: .internalError
      ),
      for: start.operationID
    )
    let failureStop = try await capture.stopInvocation(at: 0)
    #expect(model.captureFailureSource == .delegateStoppedWithKnownSCError)
    #expect(model.captureSCStreamErrorCode == .internalError)

    let manualStopTask = Task { await model.stopWindowCapture() }
    let manualStop = try await capture.stopInvocation(at: 1)
    #expect(model.captureStatus == .stopped)
    #expect(model.captureFailureSource == nil)
    #expect(model.captureSCStreamErrorCode == nil)

    await capture.resumeStop(manualStop)
    await manualStopTask.value
    await capture.resumeStop(failureStop)
  }

  private func waitForMainActorQueueDrain() async {
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }
  }

  @Test func refreshCannotChangeSelectionAfterANewerCaptureStarts() async throws {
    let capture = ControllableWindowCapture(suspendsStops: true)
    let replacementWindows = [makeWindow(id: 43), makeWindow(id: 44)]
    let model = makeModel(
      capture: capture,
      scanner: FixedWindowScanner(windows: replacementWindows)
    )

    let firstStartTask = Task { await model.startWindowCapture() }
    let firstStart = try await capture.startInvocation(at: 0)
    await capture.resumeStart(firstStart.operationID)
    await firstStartTask.value

    let refreshTask = Task { await model.refreshPowerPointWindows() }
    let refreshStop = try await capture.stopInvocation(at: 0)
    #expect(model.captureStatus == .stopped)

    model.selectedPowerPointWindowID = 44
    let secondStartTask = Task { await model.startWindowCapture() }
    let secondStart = try await capture.startInvocation(at: 1)
    await capture.resumeStart(secondStart.operationID)
    await secondStartTask.value
    #expect(model.captureStatus == .capturing)

    await capture.resumeStop(refreshStop)
    await refreshTask.value

    #expect(model.captureStatus == .capturing)
    #expect(model.selectedPowerPointWindowID == 44)

    let cleanupTask = Task { await model.stopWindowCapture() }
    let cleanupStop = try await capture.stopInvocation(at: 1)
    await capture.resumeStop(cleanupStop)
    await cleanupTask.value
  }

  private func makeModel(
    capture: ControllableWindowCapture,
    scanner: any PowerPointWindowScanning = FixedWindowScanner(windows: [])
  ) -> AppModel {
    let permissionService = PermissionService(
      screenCaptureClient: AuthorizedScreenCapturePermissionClient()
    )
    let model = AppModel(
      permissionService: permissionService,
      windowCapture: capture,
      scanner: scanner
    )
    model.selectedPowerPointWindowID = 42
    model.powerPointWindows = [makeWindow(id: 42)]
    return model
  }

  private func makeWindow(
    id: CGWindowID,
    ownerProcessID: pid_t = 700
  ) -> PowerPointWindowDescriptor {
    PowerPointWindowDescriptor(
      id: id,
      title: "Controlled window",
      applicationName: "Microsoft PowerPoint",
      ownerProcessID: ownerProcessID,
      bundleIdentifier: "com.microsoft.Powerpoint",
      frame: .zero
    )
  }
}

private final class CaptureFailureEventRecorder: Sendable {
  private let storage = Mutex<[CaptureFailureEvent]>([])

  var events: [CaptureFailureEvent] {
    storage.withLock { $0 }
  }

  func record(_ event: CaptureFailureEvent) {
    storage.withLock { events in
      events.append(event)
    }
  }
}

private actor CaptureFailureAsyncBarrier {
  private let participantCount: Int
  private var continuations: [CheckedContinuation<Void, Never>] = []
  private var isOpen = false

  init(participantCount: Int) {
    precondition(participantCount > 0)
    self.participantCount = participantCount
  }

  func arriveAndWait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
      guard continuations.count == participantCount else { return }
      isOpen = true
      let continuations = self.continuations
      self.continuations.removeAll(keepingCapacity: false)
      for continuation in continuations {
        continuation.resume()
      }
    }
  }
}

private struct CaptureInvocation: Sendable {
  let operationID: CaptureOperationID
  let identity: PowerPointWindowIdentity
}

private enum CaptureLifecycleTestError: Error {
  case timedOutWaitingForStart(Int)
  case timedOutWaitingForStop(Int)
  case timedOutWaitingForScan(Int)
  case controlledScanFailure
  case controlledStartFailure
}

private actor ControllableWindowCapture: PowerPointWindowCapturing {
  private let suspendsStops: Bool
  private var startInvocations: [CaptureInvocation] = []
  private var stopInvocations: [CaptureOperationID] = []
  private var pendingStarts: [CaptureOperationID: CheckedContinuation<Void, any Error>] = [:]
  private var pendingStops: [CaptureOperationID: CheckedContinuation<Void, Never>] = [:]
  private var errorHandlers: [CaptureOperationID: CaptureErrorHandler] = [:]
  private var failureHandlers: [CaptureOperationID: CaptureFailureHandler] = [:]

  init(suspendsStops: Bool) {
    self.suspendsStops = suspendsStops
  }

  var stopInvocationCount: Int {
    stopInvocations.count
  }

  var startInvocationCount: Int {
    startInvocations.count
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onError: @escaping CaptureErrorHandler
  ) async throws {
    errorHandlers[operationID] = onError
    startInvocations.append(
      CaptureInvocation(operationID: operationID, identity: identity)
    )
    try await withCheckedThrowingContinuation { continuation in
      pendingStarts[operationID] = continuation
    }
  }

  func start(
    operationID: CaptureOperationID,
    identity: PowerPointWindowIdentity,
    onFrame: @escaping CaptureFrameHandler,
    onContentUnavailable: @escaping CaptureContentUnavailableHandler,
    onFailure: @escaping CaptureFailureHandler
  ) async throws {
    failureHandlers[operationID] = onFailure
    startInvocations.append(
      CaptureInvocation(operationID: operationID, identity: identity)
    )
    try await withCheckedThrowingContinuation { continuation in
      pendingStarts[operationID] = continuation
    }
  }

  func stop(operationID: CaptureOperationID) async {
    stopInvocations.append(operationID)
    guard suspendsStops else { return }
    await withCheckedContinuation { continuation in
      pendingStops[operationID] = continuation
    }
  }

  func startInvocation(at index: Int) async throws -> CaptureInvocation {
    for _ in 0..<10_000 {
      if startInvocations.indices.contains(index) {
        return startInvocations[index]
      }
      await Task.yield()
    }
    throw CaptureLifecycleTestError.timedOutWaitingForStart(index)
  }

  func stopInvocation(at index: Int) async throws -> CaptureOperationID {
    for _ in 0..<10_000 {
      if stopInvocations.indices.contains(index) {
        return stopInvocations[index]
      }
      await Task.yield()
    }
    throw CaptureLifecycleTestError.timedOutWaitingForStop(index)
  }

  func resumeStart(_ operationID: CaptureOperationID) {
    pendingStarts.removeValue(forKey: operationID)?.resume(returning: ())
  }

  func failStart(_ operationID: CaptureOperationID) {
    pendingStarts.removeValue(forKey: operationID)?.resume(
      throwing: CaptureLifecycleTestError.controlledStartFailure
    )
  }

  func resumeStop(_ operationID: CaptureOperationID) {
    pendingStops.removeValue(forKey: operationID)?.resume()
  }

  func emitError(_ message: String, for operationID: CaptureOperationID) {
    if let failureHandler = failureHandlers[operationID] {
      failureHandler(CaptureFailureEventFactory.unclassified(message: message))
    } else {
      errorHandlers[operationID]?(message)
    }
  }

  func emitFailure(_ event: CaptureFailureEvent, for operationID: CaptureOperationID) {
    failureHandlers[operationID]?(event)
  }
}

private struct FixedWindowScanner: PowerPointWindowScanning {
  let windows: [PowerPointWindowDescriptor]

  func scan() async throws -> [PowerPointWindowDescriptor] {
    windows
  }
}

private actor ControllableWindowScanner: PowerPointWindowScanning {
  private var pendingScans: [CheckedContinuation<[PowerPointWindowDescriptor], any Error>] = []

  var invocationCount: Int { pendingScans.count }

  func scan() async throws -> [PowerPointWindowDescriptor] {
    try await withCheckedThrowingContinuation { continuation in
      pendingScans.append(continuation)
    }
  }

  func waitForInvocationCount(_ expectedCount: Int) async throws {
    for _ in 0..<10_000 {
      if pendingScans.count >= expectedCount { return }
      await Task.yield()
    }
    throw CaptureLifecycleTestError.timedOutWaitingForScan(expectedCount)
  }

  func resumeScan(
    at index: Int,
    with windows: [PowerPointWindowDescriptor]
  ) {
    pendingScans[index].resume(returning: windows)
  }

  func failScan(at index: Int) {
    pendingScans[index].resume(throwing: CaptureLifecycleTestError.controlledScanFailure)
  }
}

@MainActor
private struct AuthorizedScreenCapturePermissionClient: ScreenCapturePermissionClient {
  var isAuthorized: Bool { true }

  func requestAccess() -> Bool { true }
}
