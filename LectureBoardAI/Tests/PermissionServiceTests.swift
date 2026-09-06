import AVFoundation
import Foundation
import Speech
import Testing

@testable import LectureBoard_AI

@MainActor
struct PermissionServiceTests {
  @Test func audioCallbackAcceptsBufferOnBackgroundQueueWithoutActorInheritance() async {
    let frames: AVAudioFrameCount = await withCheckedContinuation { continuation in
      let callback = SpeechRecognitionAudioCallback.make { buffer in
        continuation.resume(returning: buffer.frameLength)
      }
      DispatchQueue.global().async {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1),
          let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 64)
        else {
          continuation.resume(returning: 0)
          return
        }
        buffer.frameLength = 64
        callback(buffer, AVAudioTime(sampleTime: 0, atRate: 8_000))
      }
    }
    #expect(frames == 64)
  }

  @Test func speechAuthorizationCallbackResumesFromBackgroundWithoutActorInheritance() async {
    for status in [
      SFSpeechRecognizerAuthorizationStatus.authorized, .denied, .restricted,
      .notDetermined,
    ] {
      let authorized = await withCheckedContinuation { continuation in
        let callback = SpeechRecognitionAuthorizationCallback.make(continuation: continuation)
        DispatchQueue.global().async { callback(status) }
      }
      #expect(authorized == (status == .authorized))
    }
  }

  @Test
  func onDeviceSpeechPolicyRequiresAnAvailableLocalRecognizer() {
    #expect(
      OnDeviceSpeechRecognitionPolicy.decision(
        recognizerAvailable: true,
        supportsOnDeviceRecognition: true
      ) == .accept
    )
    #expect(
      OnDeviceSpeechRecognitionPolicy.decision(
        recognizerAvailable: false,
        supportsOnDeviceRecognition: true
      ) == .recognizerUnavailable
    )
    #expect(
      OnDeviceSpeechRecognitionPolicy.decision(
        recognizerAvailable: true,
        supportsOnDeviceRecognition: false
      ) == .onDeviceRecognitionUnavailable
    )
  }

  @Test
  func onDeviceSpeechPolicyConfiguresANetworkProhibitedRequest() {
    let request = OnDeviceSpeechRecognitionPolicy.makeRequest()

    #expect(request.requiresOnDeviceRecognition)
    #expect(request.shouldReportPartialResults)
    #expect(request.addsPunctuation)
  }

  @Test
  func speechCallbackErrorPolicyAcceptsOnlyTheExactNoSpeechError() {
    #expect(SpeechRecognitionCallbackErrorPolicy.category(for: nil) == .none)
    #expect(
      SpeechRecognitionCallbackErrorPolicy.category(
        for: NSError(domain: "kAFAssistantErrorDomain", code: 1_110)
      ) == .noSpeech
    )
    #expect(
      SpeechRecognitionCallbackErrorPolicy.category(
        for: NSError(domain: "different.domain", code: 1_110)
      ) == .terminal
    )
    #expect(
      SpeechRecognitionCallbackErrorPolicy.category(
        for: NSError(domain: "kAFAssistantErrorDomain", code: 1_100)
      ) == .terminal
    )
    #expect(
      SpeechRecognitionCallbackErrorPolicy.category(
        for: NSError(domain: "kAFAssistantErrorDomain", code: 1_101)
      ) == .terminal
    )
  }

  @Test
  func finalHandoffRoutesEveryNumberedBufferExactlyOnceInOrder() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [NumberedSpeechRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<NumberedSpeechRequest, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 10,
        maximumConsecutiveRapidFinals: 2,
        initialBackoffNanoseconds: 1,
        maximumBackoffNanoseconds: 2
      ),
      makeRequest: {
        let request = NumberedSpeechRequest(id: requests.count)
        requests.append(request)
        return request
      },
      appendBuffer: { request, buffer in request.buffers.append(buffer) }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The speech handoff did not start.")
      return
    }
    #expect(
      handoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 100
      )
    )

    #expect(handoff.append(1))
    #expect(handoff.append(2))
    let action = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 110
    )
    guard case .rollover(let rollover) = action else {
      Issue.record("An accepted final did not activate the precreated request.")
      return
    }
    #expect(rollover.shouldEndCompletedRequest)
    #expect(handoff.append(3))
    #expect(handoff.append(4))

    #expect(rollover.completed.request === requests[0])
    #expect(rollover.activated.request === requests[1])
    #expect(requests[0].buffers == [1, 2])
    #expect(requests[1].buffers == [3, 4])
    #expect(requests.flatMap(\.buffers) == [1, 2, 3, 4])

    let duplicateFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 111
    )
    guard case .reject = duplicateFinal else {
      Issue.record("A duplicate callback from the completed task was accepted.")
      return
    }
  }

  @Test
  func cycleTimerHandsOffAudioBeforeEndAndFinalDoesNotEndTwice() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [NumberedSpeechRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<NumberedSpeechRequest, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 5,
        maximumConsecutiveRapidFinals: 1,
        initialBackoffNanoseconds: 0,
        maximumBackoffNanoseconds: 0
      ),
      makeRequest: {
        let request = NumberedSpeechRequest(id: requests.count)
        requests.append(request)
        return request
      },
      appendBuffer: { request, buffer in request.buffers.append(buffer) }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The timed speech session did not start.")
      return
    }
    #expect(
      handoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 100
      )
    )
    #expect(handoff.append(1))
    #expect(handoff.append(2))

    let timer = handoff.requestCycleEnd(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 108
    )
    guard case .handoff(let timedHandoff) = timer else {
      Issue.record("The cycle timer did not activate the standby audio request.")
      return
    }
    #expect(handoff.append(3))
    #expect(handoff.append(4))
    #expect(requests[0].buffers == [1, 2])
    #expect(requests[1].buffers == [3, 4])
    #expect(requests.flatMap(\.buffers) == [1, 2, 3, 4])

    var events: [String] = []
    SpeechRecognitionResourceTransition.finish(
      request: timedHandoff.completed.request,
      task: Optional<Int>.none,
      endRequest: { events.append("end:\($0.id)") },
      cancelTask: { events.append("cancel:\($0)") }
    )
    let duplicateTimer = handoff.requestCycleEnd(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 109
    )
    guard case .reject = duplicateTimer else {
      Issue.record("The same cycle accepted endAudio more than once.")
      return
    }

    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 110
    )
    guard case .rollover(let rollover) = final else {
      Issue.record("The timer-ended cycle did not accept its final result.")
      return
    }
    #expect(!rollover.shouldEndCompletedRequest)
    let newTask = SpeechRecognitionResourceTransition.rollover(
      completedRequest: rollover.completed.request,
      completedTask: 0,
      activatedRequest: rollover.activated.request,
      shouldEndCompletedRequest: rollover.shouldEndCompletedRequest,
      endRequest: { events.append("end:\($0.id)") },
      cancelTask: { events.append("cancel:\($0)") },
      startTask: {
        events.append("start:\($0.id)")
        return $0.id
      }
    )

    #expect(newTask == 1)
    #expect(events == ["end:0", "cancel:0", "start:1"])
    #expect(timedHandoff.buffering.request === rollover.activated.request)
  }

  @Test
  func finalBeforeTimerEndsOnceAndRejectsTheRetainedTimer() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 1,
        maximumConsecutiveRapidFinals: 1,
        initialBackoffNanoseconds: 0,
        maximumBackoffNanoseconds: 0
      ),
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The final-before-timer session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 10
    )
    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 11
    )
    guard case .rollover(let rollover) = final else {
      Issue.record("The final-before-timer callback did not roll over.")
      return
    }
    #expect(rollover.shouldEndCompletedRequest)
    let staleTimer = handoff.requestCycleEnd(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 12
    )
    guard case .reject = staleTimer else {
      Issue.record("A retained timer ended a completed cycle again.")
      return
    }
  }

  @Test
  func stopBeforeTimerRejectsEveryTimerAndCallbackWithoutRestarting() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The stop-before-timer session did not start.")
      return
    }
    #expect(handoff.stop(operationID: operationID).count == 2)

    let timer = handoff.requestCycleEnd(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 1
    )
    guard case .reject = timer else {
      Issue.record("A stopped operation accepted its retained cycle timer.")
      return
    }
    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 2
    )
    guard case .reject = final else {
      Issue.record("A stopped operation accepted its retained final callback.")
      return
    }
    #expect(nextRequest == 2)
  }

  @Test
  func finalizationTimeoutTerminatesAndRejectsLateFinal() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The finalization-timeout session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 0
    )
    guard
      case .handoff = handoff.requestCycleEnd(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 8
      )
    else {
      Issue.record("The finalization-timeout session did not enter handoff.")
      return
    }
    let termination = handoff.acceptFinalizationTimeout(
      operationID: operationID,
      cycleID: session.active.cycleID
    )
    #expect(termination?.error == .recognitionFinalizationTimedOut)
    #expect(termination?.requests.count == 2)
    #expect(!handoff.append(1))

    let lateFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 9
    )
    guard case .reject = lateFinal else {
      Issue.record("A final callback was accepted after its timeout terminal event.")
      return
    }
    #expect(handoff.stopAll().count == 2)
  }

  @Test
  func errorAfterTimedHandoffWinsAndSuppressesTimeoutAndFinal() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The timer-error session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 0
    )
    guard
      case .handoff = handoff.requestCycleEnd(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 8
      )
    else {
      Issue.record("The timer-error session did not enter handoff.")
      return
    }
    let error = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: false,
      isFinal: false,
      hasError: true,
      arrivedAtNanoseconds: 9
    )
    guard case .terminate(let termination) = error else {
      Issue.record("An error after timed handoff did not terminate.")
      return
    }
    #expect(termination.error == .recognitionInterrupted)
    #expect(termination.requests.count == 2)
    #expect(
      handoff.acceptFinalizationTimeout(
        operationID: operationID,
        cycleID: session.active.cycleID
      ) == nil
    )
    let lateFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 10
    )
    guard case .reject = lateFinal else {
      Issue.record("A final callback displaced the accepted terminal error.")
      return
    }
  }

  @Test
  func gracefulStopRejectsNewAudioAndCompletesOnlyAfterTheCurrentFinal() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [NumberedSpeechRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<NumberedSpeechRequest, Int>(
      makeRequest: {
        let request = NumberedSpeechRequest(id: requests.count)
        requests.append(request)
        return request
      },
      appendBuffer: { request, buffer in request.buffers.append(buffer) }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The graceful-stop session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 0
    )
    #expect(handoff.append(1))

    let stop = handoff.requestGracefulStop(
      operationID: operationID,
      recognitionTaskCycleID: session.active.cycleID,
      permitEmptyCompletion: false
    )
    guard
      case .awaitFinal(let completed, let shouldEndCompletedRequest) = stop
    else {
      Issue.record("A graceful stop did not wait for the current final result.")
      return
    }
    #expect(completed.request === requests[0])
    #expect(shouldEndCompletedRequest)
    #expect(!handoff.append(2))
    let duplicateStop = handoff.requestGracefulStop(
      operationID: operationID,
      recognitionTaskCycleID: session.active.cycleID,
      permitEmptyCompletion: false
    )
    guard case .reject = duplicateStop else {
      Issue.record("A repeated graceful stop requested endAudio again.")
      return
    }

    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .complete(let completion) = final else {
      Issue.record("The graceful final tried to restart recognition.")
      return
    }
    #expect(completion.shouldDeliverResult)
    #expect(completion.requests.count == 2)
    #expect(requests[0].buffers == [1])

    let staleFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 2
    )
    guard case .reject = staleFinal else {
      Issue.record("A retained callback was accepted after graceful completion.")
      return
    }
    #expect(handoff.stopAll().count == 2)
  }

  @Test
  func gracefulStopAfterTimerFinalizesTheBufferedTailWithoutDuplicateAudio() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [NumberedSpeechRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<NumberedSpeechRequest, Int>(
      makeRequest: {
        let request = NumberedSpeechRequest(id: requests.count)
        requests.append(request)
        return request
      },
      appendBuffer: { request, buffer in request.buffers.append(buffer) }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The timer-graceful-stop session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 0
    )
    #expect(handoff.append(1))
    guard
      case .handoff = handoff.requestCycleEnd(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 8
      )
    else {
      Issue.record("The cycle timer did not create a buffered tail.")
      return
    }
    #expect(handoff.append(2))
    let stop = handoff.requestGracefulStop(
      operationID: operationID,
      recognitionTaskCycleID: session.active.cycleID,
      permitEmptyCompletion: false
    )
    guard case .awaitFinal(_, let shouldEndOldRequest) = stop else {
      Issue.record("The graceful stop did not retain the timer-ended recognition task.")
      return
    }
    #expect(!shouldEndOldRequest)
    #expect(
      handoff.acceptFinalizationTimeout(
        operationID: operationID,
        cycleID: session.active.cycleID
      ) == nil
    )
    #expect(!handoff.append(3))

    let oldFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 9
    )
    guard case .rollover(let rollover) = oldFinal else {
      Issue.record("The buffered tail was discarded after the old final result.")
      return
    }
    #expect(!rollover.shouldEndCompletedRequest)
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: rollover.activated.cycleID,
      atNanoseconds: 10
    )
    let tailStop = handoff.requestGracefulStop(
      operationID: operationID,
      recognitionTaskCycleID: rollover.activated.cycleID,
      permitEmptyCompletion: true
    )
    guard case .awaitFinal(_, let shouldEndTailRequest) = tailStop else {
      Issue.record("The buffered tail was not finalized.")
      return
    }
    #expect(shouldEndTailRequest)
    let tailFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: rollover.activated.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 11
    )
    guard case .complete(let completion) = tailFinal else {
      Issue.record("The finalized buffered tail restarted recognition.")
      return
    }
    #expect(completion.shouldDeliverResult)
    #expect(requests[0].buffers == [1])
    #expect(requests[1].buffers == [2])
    #expect(requests.flatMap(\.buffers) == [1, 2])
    let duplicateTailFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: rollover.activated.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 12
    )
    guard case .reject = duplicateTailFinal else {
      Issue.record("A buffered tail completed graceful stop more than once.")
      return
    }
  }

  @Test
  func gracefulStopDuringAcceptedFinalHandoffWaitsForTheBufferedTailTask() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [NumberedSpeechRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<NumberedSpeechRequest, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 1,
        maximumConsecutiveRapidFinals: 1,
        initialBackoffNanoseconds: 0,
        maximumBackoffNanoseconds: 0
      ),
      makeRequest: {
        let request = NumberedSpeechRequest(id: requests.count)
        requests.append(request)
        return request
      },
      appendBuffer: { request, buffer in request.buffers.append(buffer) }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The accepted-final graceful-stop session did not start.")
      return
    }
    #expect(
      handoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 0
      )
    )
    #expect(handoff.append(1))
    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .rollover(let rollover) = final else {
      Issue.record("The accepted final did not hand off to the buffered tail.")
      return
    }
    #expect(handoff.append(2))

    let deferredStop = handoff.requestGracefulStop(
      operationID: operationID,
      recognitionTaskCycleID: session.active.cycleID,
      permitEmptyCompletion: false
    )
    guard case .deferred = deferredStop else {
      Issue.record("The stop raced ahead of the accepted final's task handoff.")
      return
    }
    #expect(!handoff.append(3))
    #expect(
      handoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: rollover.activated.cycleID,
        atNanoseconds: 2
      )
    )
    #expect(
      handoff.installStandby(
        operationID: operationID,
        activeCycleID: rollover.activated.cycleID
      ) != nil
    )

    let tailStop = handoff.requestGracefulStop(
      operationID: operationID,
      recognitionTaskCycleID: rollover.activated.cycleID,
      permitEmptyCompletion: true
    )
    guard case .awaitFinal(_, let shouldEndTailRequest) = tailStop else {
      Issue.record("The buffered tail was not finalized after task handoff.")
      return
    }
    #expect(shouldEndTailRequest)
    let staleOldFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 3
    )
    guard case .reject = staleOldFinal else {
      Issue.record("The old task regained control during graceful finalization.")
      return
    }
    let tailFinal = handoff.acceptCallback(
      operationID: operationID,
      cycleID: rollover.activated.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 4
    )
    guard case .complete(let completion) = tailFinal else {
      Issue.record("The buffered tail did not complete the graceful stop.")
      return
    }
    #expect(completion.shouldDeliverResult)
    #expect(requests[0].buffers == [1])
    #expect(requests[1].buffers == [2])
    #expect(requests.flatMap(\.buffers) == [1, 2])
  }

  @Test
  func gracefulStopErrorOrDeadlineHardClosesTheOperation() {
    func makeHandoff() -> (
      SpeechRecognitionRollingHandoff<Int, Int>,
      TranscriptionOperationID,
      SpeechRecognitionCycleID
    )? {
      var gate = TranscriptionOperationGate()
      let operationID = gate.begin()
      var nextRequest = 0
      let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
        makeRequest: {
          defer { nextRequest += 1 }
          return nextRequest
        },
        appendBuffer: { _, _ in }
      )
      guard let session = handoff.beginSession(operationID: operationID) else {
        return nil
      }
      _ = handoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 0
      )
      guard
        case .awaitFinal = handoff.requestGracefulStop(
          operationID: operationID,
          recognitionTaskCycleID: session.active.cycleID,
          permitEmptyCompletion: false
        )
      else {
        return nil
      }
      return (handoff, operationID, session.active.cycleID)
    }

    guard let errorCase = makeHandoff() else {
      Issue.record("The graceful-stop error case did not start.")
      return
    }
    let error = errorCase.0.acceptCallback(
      operationID: errorCase.1,
      cycleID: errorCase.2,
      hasResult: false,
      isFinal: false,
      hasError: true,
      arrivedAtNanoseconds: 1
    )
    guard case .terminate(let errorTermination) = error else {
      Issue.record("An error did not win the graceful-stop race.")
      return
    }
    #expect(errorTermination.error == .recognitionInterrupted)
    #expect(!errorCase.0.append(1))

    guard let timeoutCase = makeHandoff() else {
      Issue.record("The graceful-stop timeout case did not start.")
      return
    }
    let timeout = timeoutCase.0.terminateCurrent(
      operationID: timeoutCase.1,
      error: .recognitionFinalizationTimedOut
    )
    #expect(timeout?.error == .recognitionFinalizationTimedOut)
    #expect(timeout?.requests.count == 2)
    #expect(!timeoutCase.0.append(1))
    let staleFinal = timeoutCase.0.acceptCallback(
      operationID: timeoutCase.1,
      cycleID: timeoutCase.2,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 2
    )
    guard case .reject = staleFinal else {
      Issue.record("A callback was accepted after graceful-stop timeout cleanup.")
      return
    }
  }

  @Test
  func rolloverEndsAndCancelsTheCompletedCycleBeforeStartingTheNextTask() {
    var events: [String] = []

    let task = SpeechRecognitionResourceTransition.rollover(
      completedRequest: "request-1",
      completedTask: "task-1",
      activatedRequest: "request-2",
      endRequest: { events.append("end:\($0)") },
      cancelTask: { events.append("cancel:\($0)") },
      startTask: {
        events.append("start:\($0)")
        return "task-2"
      }
    )

    #expect(task == "task-2")
    #expect(events == ["end:request-1", "cancel:task-1", "start:request-2"])
  }

  @Test
  func cycleTimingUsesABoundedEightSecondWindowAndAccountsForBufferedAudio() {
    let productionPolicy = SpeechRecognitionCycleTimingPolicy()
    #expect(productionPolicy.cycleDurationNanoseconds == 8_000_000_000)
    #expect(productionPolicy.finalizationTimeoutNanoseconds == 4_000_000_000)

    let policy = SpeechRecognitionCycleTimingPolicy(
      cycleDurationNanoseconds: 20,
      finalizationTimeoutNanoseconds: 5
    )
    #expect(
      policy.remainingCycleDuration(
        audioStartedAtNanoseconds: 100,
        nowNanoseconds: 105
      ) == 15
    )
    #expect(
      policy.remainingCycleDuration(
        audioStartedAtNanoseconds: 100,
        nowNanoseconds: 121
      ) == 0
    )
    #expect(
      policy.remainingCycleDuration(
        audioStartedAtNanoseconds: 100,
        nowNanoseconds: 99
      ) == 20
    )

    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The buffered-audio timing session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 100
    )
    guard
      case .handoff = handoff.requestCycleEnd(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: 120
      )
    else {
      Issue.record("The buffered-audio timing session did not hand off.")
      return
    }
    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 124
    )
    guard case .rollover(let rollover) = final else {
      Issue.record("The buffered-audio timing session did not roll over.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: rollover.activated.cycleID,
      atNanoseconds: 125
    )
    #expect(
      handoff.remainingCycleDuration(
        operationID: operationID,
        cycleID: rollover.activated.cycleID,
        atNanoseconds: 125,
        timingPolicy: policy
      ) == 15
    )
  }

  @Test
  func sessionElapsedTimeIsMonotonicAndOverflowSafe() {
    let start = UInt64.max - 10
    let values = [
      SpeechRecognitionSessionElapsedTime.seconds(
        startedAtNanoseconds: start,
        observedAtNanoseconds: start
      ),
      SpeechRecognitionSessionElapsedTime.seconds(
        startedAtNanoseconds: start,
        observedAtNanoseconds: start + 5
      ),
      SpeechRecognitionSessionElapsedTime.seconds(
        startedAtNanoseconds: start,
        observedAtNanoseconds: UInt64.max
      ),
      SpeechRecognitionSessionElapsedTime.seconds(
        startedAtNanoseconds: start,
        observedAtNanoseconds: 0
      ),
      SpeechRecognitionSessionElapsedTime.seconds(
        startedAtNanoseconds: start,
        observedAtNanoseconds: 5
      ),
    ]

    #expect(values == values.sorted())
    #expect(values[0] == 0)
    #expect(values[1] > values[0])
    #expect(values[2] > values[1])
    #expect(values[3] > values[2])
    #expect(values[4] > values[3])
    #expect(values.allSatisfy { value in value.isFinite })
    #expect(
      SpeechRecognitionSessionElapsedTime.seconds(
        startedAtNanoseconds: nil,
        observedAtNanoseconds: UInt64.max
      ) == 0
    )
    #expect(
      SpeechRecognitionSessionElapsedTime.seconds(
        startedAtNanoseconds: 0,
        observedAtNanoseconds: UInt64.max
      ).isFinite
    )
  }

  @Test
  func callbackPermutationsPreserveFinalAndErrorSemantics() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let makeHandoff = {
      SpeechRecognitionRollingHandoff<Int, Int>(
        restartPolicy: SpeechRecognitionRestartPolicy(
          rapidFinalThresholdNanoseconds: 10,
          maximumConsecutiveRapidFinals: 2,
          initialBackoffNanoseconds: 1,
          maximumBackoffNanoseconds: 2
        ),
        makeRequest: {
          defer { nextRequest += 1 }
          return nextRequest
        },
        appendBuffer: { _, _ in }
      )
    }

    let partialHandoff = makeHandoff()
    guard let partialSession = partialHandoff.beginSession(operationID: operationID) else {
      Issue.record("The partial-result session did not start.")
      return
    }
    let partial = partialHandoff.acceptCallback(
      operationID: operationID,
      cycleID: partialSession.active.cycleID,
      hasResult: true,
      isFinal: false,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .deliver = partial else {
      Issue.record("A healthy partial result was not delivered.")
      return
    }

    let finalHandoff = makeHandoff()
    guard let finalSession = finalHandoff.beginSession(operationID: operationID) else {
      Issue.record("The final-result session did not start.")
      return
    }
    _ = finalHandoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: finalSession.active.cycleID,
      atNanoseconds: 0
    )
    let final = finalHandoff.acceptCallback(
      operationID: operationID,
      cycleID: finalSession.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 10
    )
    guard case .rollover = final else {
      Issue.record("A final result without an error did not roll over.")
      return
    }

    let finalErrorHandoff = makeHandoff()
    guard let finalErrorSession = finalErrorHandoff.beginSession(operationID: operationID) else {
      Issue.record("The final-plus-error session did not start.")
      return
    }
    let finalError = finalErrorHandoff.acceptCallback(
      operationID: operationID,
      cycleID: finalErrorSession.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: true,
      arrivedAtNanoseconds: 1
    )
    guard case .terminate(let finalTermination) = finalError else {
      Issue.record("A result accompanied by an error did not terminate.")
      return
    }
    #expect(finalTermination.shouldDeliverResult)
    #expect(finalTermination.error == .recognitionInterrupted)

    let bareErrorHandoff = makeHandoff()
    guard let bareErrorSession = bareErrorHandoff.beginSession(operationID: operationID) else {
      Issue.record("The bare-error session did not start.")
      return
    }
    let bareError = bareErrorHandoff.acceptCallback(
      operationID: operationID,
      cycleID: bareErrorSession.active.cycleID,
      hasResult: false,
      isFinal: false,
      hasError: true,
      arrivedAtNanoseconds: 1
    )
    guard case .terminate(let bareTermination) = bareError else {
      Issue.record("A callback error did not terminate recognition.")
      return
    }
    #expect(!bareTermination.shouldDeliverResult)
    #expect(bareTermination.error == .recognitionInterrupted)

    let emptyHandoff = makeHandoff()
    guard let emptySession = emptyHandoff.beginSession(operationID: operationID) else {
      Issue.record("The empty-callback session did not start.")
      return
    }
    let empty = emptyHandoff.acceptCallback(
      operationID: operationID,
      cycleID: emptySession.active.cycleID,
      hasResult: false,
      isFinal: false,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .ignore = empty else {
      Issue.record("An empty callback was not ignored.")
      return
    }
  }

  @Test
  func noSpeechRequiresAnExplicitEndAndCompletesGracefulStopWithoutAResult() {
    var operationGate = TranscriptionOperationGate()
    let unendedOperationID = operationGate.begin()
    var nextRequest = 0
    let unendedHandoff = SpeechRecognitionRollingHandoff<Int, Int>(
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let unendedSession = unendedHandoff.beginSession(operationID: unendedOperationID) else {
      Issue.record("The unended no-speech session did not start.")
      return
    }
    _ = unendedHandoff.markRecognitionStarted(
      operationID: unendedOperationID,
      cycleID: unendedSession.active.cycleID,
      atNanoseconds: 0
    )
    let unendedNoSpeech = unendedHandoff.acceptCallback(
      operationID: unendedOperationID,
      cycleID: unendedSession.active.cycleID,
      hasResult: false,
      isFinal: false,
      errorCategory: .noSpeech,
      arrivedAtNanoseconds: 1
    )
    guard case .terminate(let unendedTermination) = unendedNoSpeech else {
      Issue.record("No-speech from an unended request did not fail closed.")
      return
    }
    #expect(unendedTermination.error == .recognitionInterrupted)
    #expect(!unendedTermination.shouldDeliverResult)

    operationGate.invalidate()
    let gracefulOperationID = operationGate.begin()
    let gracefulHandoff = SpeechRecognitionRollingHandoff<Int, Int>(
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard
      let gracefulSession = gracefulHandoff.beginSession(
        operationID: gracefulOperationID
      )
    else {
      Issue.record("The graceful no-speech session did not start.")
      return
    }
    _ = gracefulHandoff.markRecognitionStarted(
      operationID: gracefulOperationID,
      cycleID: gracefulSession.active.cycleID,
      atNanoseconds: 10
    )
    guard
      case .awaitFinal(_, let shouldEndRequest) = gracefulHandoff.requestGracefulStop(
        operationID: gracefulOperationID,
        recognitionTaskCycleID: gracefulSession.active.cycleID,
        permitEmptyCompletion: false
      )
    else {
      Issue.record("The graceful no-speech request was not ended explicitly.")
      return
    }
    #expect(shouldEndRequest)
    let gracefulNoSpeech = gracefulHandoff.acceptCallback(
      operationID: gracefulOperationID,
      cycleID: gracefulSession.active.cycleID,
      hasResult: false,
      isFinal: false,
      errorCategory: .noSpeech,
      arrivedAtNanoseconds: 11
    )
    guard case .complete(let completion) = gracefulNoSpeech else {
      Issue.record("No-speech did not complete an explicit graceful stop.")
      return
    }
    #expect(!completion.shouldDeliverResult)
    #expect(completion.requests.count == 2)

    let lateFinal = gracefulHandoff.acceptCallback(
      operationID: gracefulOperationID,
      cycleID: gracefulSession.active.cycleID,
      hasResult: true,
      isFinal: true,
      errorCategory: .none,
      arrivedAtNanoseconds: 12
    )
    guard case .reject = lateFinal else {
      Issue.record("A late final displaced graceful no-speech completion.")
      return
    }
  }

  @Test
  func stopAndNewSessionRejectEveryRetainedOldCallback() {
    var operationGate = TranscriptionOperationGate()
    let firstOperationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let firstSession = handoff.beginSession(operationID: firstOperationID) else {
      Issue.record("The first session did not start.")
      return
    }
    #expect(handoff.stop(operationID: firstOperationID).count == 2)

    operationGate.invalidate()
    let secondOperationID = operationGate.begin()
    guard let secondSession = handoff.beginSession(operationID: secondOperationID) else {
      Issue.record("The second session did not start.")
      return
    }
    #expect(handoff.stop(operationID: firstOperationID).isEmpty)

    let staleTimer = handoff.requestCycleEnd(
      operationID: firstOperationID,
      cycleID: firstSession.active.cycleID,
      atNanoseconds: 1
    )
    guard case .reject = staleTimer else {
      Issue.record("A retained timer crossed into the new session.")
      return
    }
    #expect(
      handoff.acceptFinalizationTimeout(
        operationID: firstOperationID,
        cycleID: firstSession.active.cycleID
      ) == nil
    )

    let stale = handoff.acceptCallback(
      operationID: firstOperationID,
      cycleID: firstSession.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .reject = stale else {
      Issue.record("A retained callback crossed into the new session.")
      return
    }
    let current = handoff.acceptCallback(
      operationID: secondOperationID,
      cycleID: secondSession.active.cycleID,
      hasResult: true,
      isFinal: false,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .deliver = current else {
      Issue.record("The current session was displaced by a stale stop.")
      return
    }

    var lifecycle = SpeechRecognitionProviderLifecycle()
    let acceptedFirstStart = lifecycle.acceptStart(firstOperationID)
    let acceptedSecondStart = lifecycle.acceptStart(secondOperationID)
    let acceptedStaleFinish = lifecycle.finish(firstOperationID)
    #expect(acceptedFirstStart)
    #expect(acceptedSecondStart)
    #expect(!acceptedStaleFinish)
    #expect(lifecycle.isCurrent(secondOperationID))
  }

  @Test
  func currentRestartFailureClosesOnlyTheMatchingCycle() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 1,
        maximumConsecutiveRapidFinals: 1,
        initialBackoffNanoseconds: 0,
        maximumBackoffNanoseconds: 0
      ),
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 0
    )
    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .rollover(let rollover) = final else {
      Issue.record("The accepted final did not activate its standby request.")
      return
    }

    #expect(
      handoff.terminate(
        operationID: operationID,
        cycleID: session.active.cycleID,
        error: .recognizerUnavailable
      ) == nil
    )
    let failure = handoff.terminate(
      operationID: operationID,
      cycleID: rollover.activated.cycleID,
      error: .onDeviceRecognitionUnavailable
    )
    #expect(failure?.error == .onDeviceRecognitionUnavailable)
    #expect(failure?.requests.count == 1)
    #expect(!handoff.append(99))
  }

  @Test
  func rapidFinalsBackOffThenTerminateWithoutSpinning() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var nextRequest = 0
    let handoff = SpeechRecognitionRollingHandoff<Int, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 100,
        maximumConsecutiveRapidFinals: 2,
        initialBackoffNanoseconds: 10,
        maximumBackoffNanoseconds: 20
      ),
      makeRequest: {
        defer { nextRequest += 1 }
        return nextRequest
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The rapid-final session did not start.")
      return
    }
    var cycleID = session.active.cycleID
    var cycleStart = UInt64(1_000)

    for expectedDelay in [UInt64(10), UInt64(20)] {
      #expect(
        handoff.markRecognitionStarted(
          operationID: operationID,
          cycleID: cycleID,
          atNanoseconds: cycleStart
        )
      )
      let action = handoff.acceptCallback(
        operationID: operationID,
        cycleID: cycleID,
        hasResult: true,
        isFinal: true,
        hasError: false,
        arrivedAtNanoseconds: cycleStart + 1
      )
      guard case .rollover(let rollover) = action else {
        Issue.record("A budgeted rapid final did not roll over.")
        return
      }
      #expect(rollover.restartDelayNanoseconds == expectedDelay)
      cycleID = rollover.activated.cycleID
      cycleStart += 1
      #expect(
        handoff.installStandby(
          operationID: operationID,
          activeCycleID: cycleID
        ) != nil
      )
    }

    #expect(
      handoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: cycleID,
        atNanoseconds: cycleStart
      )
    )
    let exhausted = handoff.acceptCallback(
      operationID: operationID,
      cycleID: cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: cycleStart + 1
    )
    guard case .terminate(let termination) = exhausted else {
      Issue.record("The rapid-final budget did not terminate the loop.")
      return
    }
    #expect(termination.error == .rapidRestartLimitReached)
    #expect(termination.shouldDeliverResult)
    #expect(!handoff.append(1))
  }

  @Test
  func healthyLongLectureHasBoundedLiveResourcesWithoutATotalRestartCap() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [NumberedSpeechRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<NumberedSpeechRequest, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 100,
        maximumConsecutiveRapidFinals: 2,
        initialBackoffNanoseconds: 1,
        maximumBackoffNanoseconds: 2
      ),
      makeRequest: {
        let request = NumberedSpeechRequest(id: requests.count)
        requests.append(request)
        return request
      },
      appendBuffer: { request, buffer in request.buffers.append(buffer) }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The long virtual lecture did not start.")
      return
    }
    var cycleID = session.active.cycleID
    var activeTask = 0
    var endedRequestIDs: [Int] = []
    var cancelledTasks: [Int] = []

    for cycleNumber in 0..<1_024 {
      let startTime = UInt64(cycleNumber) * 1_000
      #expect(
        handoff.markRecognitionStarted(
          operationID: operationID,
          cycleID: cycleID,
          atNanoseconds: startTime
        )
      )
      #expect(handoff.append(cycleNumber * 2))
      let timer = handoff.requestCycleEnd(
        operationID: operationID,
        cycleID: cycleID,
        atNanoseconds: startTime + 100
      )
      guard case .handoff(let timedHandoff) = timer else {
        Issue.record("A healthy virtual lecture cycle did not reach its timed boundary.")
        return
      }
      SpeechRecognitionResourceTransition.finish(
        request: timedHandoff.completed.request,
        task: Optional<Int>.none,
        endRequest: { endedRequestIDs.append($0.id) },
        cancelTask: { cancelledTasks.append($0) }
      )
      #expect(handoff.append(cycleNumber * 2 + 1))
      let action = handoff.acceptCallback(
        operationID: operationID,
        cycleID: cycleID,
        hasResult: true,
        isFinal: true,
        hasError: false,
        arrivedAtNanoseconds: startTime + 101
      )
      guard case .rollover(let rollover) = action else {
        Issue.record("A healthy virtual lecture cycle was unexpectedly capped.")
        return
      }
      #expect(rollover.restartDelayNanoseconds == 0)
      activeTask = SpeechRecognitionResourceTransition.rollover(
        completedRequest: rollover.completed.request,
        completedTask: activeTask,
        activatedRequest: rollover.activated.request,
        shouldEndCompletedRequest: rollover.shouldEndCompletedRequest,
        endRequest: { endedRequestIDs.append($0.id) },
        cancelTask: { cancelledTasks.append($0) },
        startTask: { $0.id }
      )
      cycleID = rollover.activated.cycleID
      #expect(
        handoff.installStandby(
          operationID: operationID,
          activeCycleID: cycleID
        ) != nil
      )
    }

    let remaining = handoff.stop(operationID: operationID)
    endedRequestIDs.append(contentsOf: remaining.map(\.request.id))
    cancelledTasks.append(activeTask)

    #expect(requests.count == 1_026)
    #expect(endedRequestIDs.count == requests.count)
    #expect(Set(endedRequestIDs).count == requests.count)
    #expect(cancelledTasks.count == 1_025)
    #expect(handoff.rapidFinalCount == 0)
    #expect(requests.flatMap(\.buffers) == Array(0..<2_048))
  }

  @Test
  func repeatedExplicitlyEndedNoSpeechCyclesPreserveBuffersAndBoundResources() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [NumberedSpeechRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<NumberedSpeechRequest, Int>(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 100,
        maximumConsecutiveRapidFinals: 2,
        initialBackoffNanoseconds: 1,
        maximumBackoffNanoseconds: 2
      ),
      makeRequest: {
        let request = NumberedSpeechRequest(id: requests.count)
        requests.append(request)
        return request
      },
      appendBuffer: { request, buffer in request.buffers.append(buffer) }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The long no-speech session did not start.")
      return
    }
    var cycleID = session.active.cycleID
    var activeTask = 0
    var endedRequestIDs: [Int] = []
    var cancelledTasks: [Int] = []

    for cycleNumber in 0..<1_024 {
      let startTime = UInt64(cycleNumber) * 1_000
      #expect(
        handoff.markRecognitionStarted(
          operationID: operationID,
          cycleID: cycleID,
          atNanoseconds: startTime
        )
      )
      #expect(handoff.append(cycleNumber * 2))
      let timer = handoff.requestCycleEnd(
        operationID: operationID,
        cycleID: cycleID,
        atNanoseconds: startTime + 100
      )
      guard case .handoff(let timedHandoff) = timer else {
        Issue.record("A no-speech cycle was not explicitly ended.")
        return
      }
      SpeechRecognitionResourceTransition.finish(
        request: timedHandoff.completed.request,
        task: Optional<Int>.none,
        endRequest: { endedRequestIDs.append($0.id) },
        cancelTask: { cancelledTasks.append($0) }
      )
      #expect(handoff.append(cycleNumber * 2 + 1))

      let noSpeech = handoff.acceptCallback(
        operationID: operationID,
        cycleID: cycleID,
        hasResult: false,
        isFinal: false,
        errorCategory: .noSpeech,
        arrivedAtNanoseconds: startTime + 101
      )
      guard case .rollover(let rollover) = noSpeech else {
        Issue.record("An explicitly ended no-speech cycle did not roll over.")
        return
      }
      #expect(!rollover.shouldDeliverResult)
      #expect(!rollover.shouldEndCompletedRequest)
      activeTask = SpeechRecognitionResourceTransition.rollover(
        completedRequest: rollover.completed.request,
        completedTask: activeTask,
        activatedRequest: rollover.activated.request,
        shouldEndCompletedRequest: rollover.shouldEndCompletedRequest,
        endRequest: { endedRequestIDs.append($0.id) },
        cancelTask: { cancelledTasks.append($0) },
        startTask: { $0.id }
      )
      cycleID = rollover.activated.cycleID
      #expect(
        handoff.installStandby(
          operationID: operationID,
          activeCycleID: cycleID
        ) != nil
      )
    }

    let remaining = handoff.stop(operationID: operationID)
    endedRequestIDs.append(contentsOf: remaining.map(\.request.id))
    cancelledTasks.append(activeTask)

    #expect(requests.count == 1_026)
    #expect(endedRequestIDs.count == requests.count)
    #expect(Set(endedRequestIDs).count == requests.count)
    #expect(cancelledTasks.count == 1_025)
    #expect(handoff.rapidFinalCount == 0)
    #expect(requests.flatMap(\.buffers) == Array(0..<2_048))
  }

  @Test
  func everyPrecreatedAndReplacementRequestProhibitsNetworkRecognition() {
    var operationGate = TranscriptionOperationGate()
    let operationID = operationGate.begin()
    var requests: [SFSpeechAudioBufferRecognitionRequest] = []
    let handoff = SpeechRecognitionRollingHandoff<
      SFSpeechAudioBufferRecognitionRequest,
      Int
    >(
      restartPolicy: SpeechRecognitionRestartPolicy(
        rapidFinalThresholdNanoseconds: 1,
        maximumConsecutiveRapidFinals: 1,
        initialBackoffNanoseconds: 0,
        maximumBackoffNanoseconds: 0
      ),
      makeRequest: {
        let request = OnDeviceSpeechRecognitionPolicy.makeRequest()
        requests.append(request)
        return request
      },
      appendBuffer: { _, _ in }
    )
    guard let session = handoff.beginSession(operationID: operationID) else {
      Issue.record("The on-device request session did not start.")
      return
    }
    _ = handoff.markRecognitionStarted(
      operationID: operationID,
      cycleID: session.active.cycleID,
      atNanoseconds: 0
    )
    let final = handoff.acceptCallback(
      operationID: operationID,
      cycleID: session.active.cycleID,
      hasResult: true,
      isFinal: true,
      hasError: false,
      arrivedAtNanoseconds: 1
    )
    guard case .rollover(let rollover) = final else {
      Issue.record("The on-device request did not roll over.")
      return
    }
    #expect(
      handoff.installStandby(
        operationID: operationID,
        activeCycleID: rollover.activated.cycleID
      ) != nil
    )

    #expect(requests.count == 3)
    let allRequireOnDeviceRecognition = requests.allSatisfy {
      $0.requiresOnDeviceRecognition
    }
    let allReportPartialResults = requests.allSatisfy {
      $0.shouldReportPartialResults
    }
    let allAddPunctuation = requests.allSatisfy {
      $0.addsPunctuation
    }
    #expect(allRequireOnDeviceRecognition)
    #expect(allReportPartialResults)
    #expect(allAddPunctuation)
  }

  @Test
  func callbackMailboxDeliversAcceptedArrivalsInFIFOOrder() async {
    var delivered: [Int] = []
    let mailbox = OrderedSpeechCallbackMailbox<Int> { value in
      delivered.append(value)
    }

    mailbox.enqueue(1)
    mailbox.enqueue(2)
    mailbox.enqueue(3)
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }

    #expect(delivered == [1, 2, 3])
  }

  @Test
  func callbackMailboxCoalescesOnlyConsecutivePartialsFromTheSameCycle() async {
    var delivered: [MailboxSpeechEvent] = []
    let mailbox = OrderedSpeechCallbackMailbox<MailboxSpeechEvent>(
      maximumRetainedEventCount: 4,
      coalescingKey: { event in
        guard event.kind == .partial else { return nil }
        return AnyHashable(event.cycle)
      },
      handler: { event in delivered.append(event) }
    )

    for ordinal in 0..<10_000 {
      mailbox.enqueue(MailboxSpeechEvent(cycle: 1, ordinal: ordinal, kind: .partial))
    }
    #expect(mailbox.retainedEventCount == 1)
    for ordinal in 10_000..<20_000 {
      mailbox.enqueue(MailboxSpeechEvent(cycle: 2, ordinal: ordinal, kind: .partial))
    }
    #expect(mailbox.retainedEventCount == 2)
    mailbox.enqueue(MailboxSpeechEvent(cycle: 2, ordinal: 20_000, kind: .final))
    for ordinal in 20_001..<30_001 {
      mailbox.enqueue(MailboxSpeechEvent(cycle: 2, ordinal: ordinal, kind: .partial))
    }

    #expect(mailbox.retainedEventCount == 4)
    #expect(mailbox.maximumObservedEventCount == 4)
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }

    #expect(
      delivered == [
        MailboxSpeechEvent(cycle: 1, ordinal: 9_999, kind: .partial),
        MailboxSpeechEvent(cycle: 2, ordinal: 19_999, kind: .partial),
        MailboxSpeechEvent(cycle: 2, ordinal: 20_000, kind: .final),
        MailboxSpeechEvent(cycle: 2, ordinal: 30_000, kind: .partial),
      ]
    )
  }

  @Test
  func callbackMailboxBoundsAnAdversarialTerminalFloodWithoutDroppingOrReordering() async {
    var delivered: [MailboxSpeechEvent] = []
    let mailbox = OrderedSpeechCallbackMailbox<MailboxSpeechEvent>(
      maximumRetainedEventCount: 3,
      handler: { event in delivered.append(event) }
    )
    // The producer must encounter backpressure many times without making this
    // deterministic test depend on thousands of main-thread wake-ups.
    let expected = (0..<256).map { ordinal in
      MailboxSpeechEvent(
        cycle: ordinal,
        ordinal: ordinal,
        kind: MailboxSpeechEvent.Kind.terminalKinds[ordinal % 3]
      )
    }

    for event in expected {
      mailbox.enqueue(event)
    }
    #expect(mailbox.retainedEventCount <= 3)
    #expect(mailbox.maximumObservedEventCount == 3)
    await withCheckedContinuation { continuation in
      DispatchQueue.main.async {
        continuation.resume()
      }
    }

    #expect(delivered == expected)
    #expect(mailbox.retainedEventCount == 0)
  }

  @Test
  func readsScreenCaptureStatusWithoutRequestingAccess() {
    let client = ScreenCapturePermissionClientSpy(
      isAuthorized: true,
      requestResult: false
    )
    let service = PermissionService(screenCaptureClient: client)

    #expect(service.screenCaptureAccessGranted)
    #expect(client.authorizationReadCount == 1)
    #expect(client.requestCount == 0)
  }

  @Test
  func requestsOnlyTheInjectedScreenCapturePermission() {
    let client = ScreenCapturePermissionClientSpy(
      isAuthorized: false,
      requestResult: true
    )
    let service = PermissionService(screenCaptureClient: client)

    #expect(service.requestScreenCaptureAccess())
    #expect(client.authorizationReadCount == 0)
    #expect(client.requestCount == 1)
  }

  @Test
  func preservesADeniedScreenCaptureRequestResult() {
    let client = ScreenCapturePermissionClientSpy(
      isAuthorized: false,
      requestResult: false
    )
    let service = PermissionService(screenCaptureClient: client)

    #expect(service.requestScreenCaptureAccess() == false)
    #expect(client.requestCount == 1)
  }
}

private final class NumberedSpeechRequest {
  let id: Int
  var buffers: [Int] = []

  init(id: Int) {
    self.id = id
  }
}

private struct MailboxSpeechEvent: Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case partial
    case final
    case error
    case terminal

    static let terminalKinds: [Kind] = [.final, .error, .terminal]
  }

  let cycle: Int
  let ordinal: Int
  let kind: Kind
}

@MainActor
private final class ScreenCapturePermissionClientSpy: ScreenCapturePermissionClient {
  private let authorizationResult: Bool
  private let requestResult: Bool

  private(set) var authorizationReadCount = 0
  private(set) var requestCount = 0

  init(isAuthorized: Bool, requestResult: Bool) {
    authorizationResult = isAuthorized
    self.requestResult = requestResult
  }

  var isAuthorized: Bool {
    authorizationReadCount += 1
    return authorizationResult
  }

  func requestAccess() -> Bool {
    requestCount += 1
    return requestResult
  }
}
