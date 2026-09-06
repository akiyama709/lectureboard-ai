@preconcurrency import AVFoundation
import Darwin
import Foundation
import LectureBoardCore
@preconcurrency import Speech

enum SpeechRecognitionAudioCallback {
  nonisolated static func make(
    append: @escaping @Sendable (AVAudioPCMBuffer) -> Void
  ) -> @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void {
    { buffer, _ in append(buffer) }
  }
}

enum OnDeviceSpeechRecognitionPolicy {
  enum Decision: Equatable {
    case accept
    case recognizerUnavailable
    case onDeviceRecognitionUnavailable
  }

  static func decision(
    recognizerAvailable: Bool,
    supportsOnDeviceRecognition: Bool
  ) -> Decision {
    guard recognizerAvailable else { return .recognizerUnavailable }
    guard supportsOnDeviceRecognition else {
      return .onDeviceRecognitionUnavailable
    }
    return .accept
  }

  static func makeRequest() -> SFSpeechAudioBufferRecognitionRequest {
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
    return request
  }
}

struct SpeechRecognitionCycleID: Equatable, Hashable, Sendable {
  fileprivate let rawValue: UInt64
}

struct SpeechRecognitionSegmentIdentityStore: Sendable {
  private var identifiers: [SpeechRecognitionCycleID: UUID] = [:]

  mutating func identifier(for cycleID: SpeechRecognitionCycleID) -> UUID {
    if let identifier = identifiers[cycleID] { return identifier }
    let identifier = UUID()
    identifiers[cycleID] = identifier
    return identifier
  }

  mutating func reset() {
    identifiers.removeAll(keepingCapacity: true)
  }
}

struct SpeechRecognitionRestartPolicy: Equatable, Sendable {
  enum Decision: Equatable, Sendable {
    case restart(afterNanoseconds: UInt64)
    case stop
  }

  let rapidFinalThresholdNanoseconds: UInt64
  let maximumConsecutiveRapidFinals: Int
  let initialBackoffNanoseconds: UInt64
  let maximumBackoffNanoseconds: UInt64

  init(
    rapidFinalThresholdNanoseconds: UInt64 = 250_000_000,
    maximumConsecutiveRapidFinals: Int = 3,
    initialBackoffNanoseconds: UInt64 = 25_000_000,
    maximumBackoffNanoseconds: UInt64 = 100_000_000
  ) {
    precondition(
      maximumConsecutiveRapidFinals >= 0,
      "The rapid speech-final budget must not be negative."
    )
    precondition(
      initialBackoffNanoseconds <= maximumBackoffNanoseconds,
      "The initial speech backoff must not exceed its maximum."
    )
    self.rapidFinalThresholdNanoseconds = rapidFinalThresholdNanoseconds
    self.maximumConsecutiveRapidFinals = maximumConsecutiveRapidFinals
    self.initialBackoffNanoseconds = initialBackoffNanoseconds
    self.maximumBackoffNanoseconds = maximumBackoffNanoseconds
  }

  func decision(
    cycleStartedAtNanoseconds: UInt64?,
    finalArrivedAtNanoseconds: UInt64,
    consecutiveRapidFinalCount: inout Int
  ) -> Decision {
    let isHealthyCycle: Bool
    if let cycleStartedAtNanoseconds,
      finalArrivedAtNanoseconds >= cycleStartedAtNanoseconds
    {
      isHealthyCycle =
        finalArrivedAtNanoseconds - cycleStartedAtNanoseconds
        >= rapidFinalThresholdNanoseconds
    } else {
      isHealthyCycle = false
    }

    if isHealthyCycle {
      consecutiveRapidFinalCount = 0
      return .restart(afterNanoseconds: 0)
    }

    guard consecutiveRapidFinalCount < maximumConsecutiveRapidFinals else {
      return .stop
    }
    consecutiveRapidFinalCount += 1

    var delay = initialBackoffNanoseconds
    if consecutiveRapidFinalCount > 1 {
      for _ in 1..<consecutiveRapidFinalCount {
        guard delay < maximumBackoffNanoseconds else { break }
        if delay > maximumBackoffNanoseconds / 2 {
          delay = maximumBackoffNanoseconds
        } else {
          delay *= 2
        }
      }
    }
    return .restart(afterNanoseconds: min(delay, maximumBackoffNanoseconds))
  }
}

struct SpeechRecognitionRequestEndpoint<Request> {
  let cycleID: SpeechRecognitionCycleID
  let request: Request
  fileprivate var recognitionStartedAtNanoseconds: UInt64?
  fileprivate var audioStartedAtNanoseconds: UInt64?
  fileprivate var endAudioWasRequested: Bool
  fileprivate var hasAudioBuffers: Bool
}

struct SpeechRecognitionSessionStart<Request> {
  let active: SpeechRecognitionRequestEndpoint<Request>
  let standby: SpeechRecognitionRequestEndpoint<Request>
}

struct SpeechRecognitionFinalHandoff<Request> {
  let completed: SpeechRecognitionRequestEndpoint<Request>
  let activated: SpeechRecognitionRequestEndpoint<Request>
  let restartDelayNanoseconds: UInt64
  let shouldEndCompletedRequest: Bool
  let shouldDeliverResult: Bool
}

struct SpeechRecognitionTimedHandoff<Request> {
  let completed: SpeechRecognitionRequestEndpoint<Request>
  let buffering: SpeechRecognitionRequestEndpoint<Request>
}

struct SpeechRecognitionTermination<Request> {
  let error: TranscriptionError
  let shouldDeliverResult: Bool
  let requests: [SpeechRecognitionRequestEndpoint<Request>]
}

struct SpeechRecognitionGracefulCompletion<Request> {
  let shouldDeliverResult: Bool
  let requests: [SpeechRecognitionRequestEndpoint<Request>]
}

enum SpeechRecognitionCallbackAction<Request> {
  case reject
  case ignore
  case deliver
  case rollover(SpeechRecognitionFinalHandoff<Request>)
  case complete(SpeechRecognitionGracefulCompletion<Request>)
  case terminate(SpeechRecognitionTermination<Request>)
}

enum SpeechRecognitionGracefulStopAction<Request> {
  case reject
  case deferred
  case awaitFinal(
    completed: SpeechRecognitionRequestEndpoint<Request>,
    shouldEndCompletedRequest: Bool
  )
  case complete(SpeechRecognitionGracefulCompletion<Request>)
}

enum SpeechRecognitionCycleTimerAction<Request> {
  case reject
  case handoff(SpeechRecognitionTimedHandoff<Request>)
  case terminate(SpeechRecognitionTermination<Request>)
}

struct SpeechRecognitionCycleTimingPolicy: Equatable, Sendable {
  let cycleDurationNanoseconds: UInt64
  let finalizationTimeoutNanoseconds: UInt64

  init(
    cycleDurationNanoseconds: UInt64 = 8_000_000_000,
    finalizationTimeoutNanoseconds: UInt64 = 4_000_000_000
  ) {
    precondition(
      cycleDurationNanoseconds > 0,
      "The speech-recognition cycle duration must be positive."
    )
    precondition(
      finalizationTimeoutNanoseconds > 0,
      "The speech-recognition finalization timeout must be positive."
    )
    self.cycleDurationNanoseconds = cycleDurationNanoseconds
    self.finalizationTimeoutNanoseconds = finalizationTimeoutNanoseconds
  }

  func remainingCycleDuration(
    audioStartedAtNanoseconds: UInt64,
    nowNanoseconds: UInt64
  ) -> UInt64 {
    guard nowNanoseconds >= audioStartedAtNanoseconds else {
      return cycleDurationNanoseconds
    }
    let elapsed = nowNanoseconds - audioStartedAtNanoseconds
    guard elapsed < cycleDurationNanoseconds else { return 0 }
    return cycleDurationNanoseconds - elapsed
  }
}

enum SpeechRecognitionCallbackErrorCategory: Equatable, Sendable {
  case none
  case noSpeech
  case terminal
}

enum SpeechRecognitionCallbackErrorPolicy {
  private static let noSpeechDomain = "kAFAssistantErrorDomain"
  private static let noSpeechCode = 1_110

  static func category(for error: Error?) -> SpeechRecognitionCallbackErrorCategory {
    guard let error else { return .none }
    let cocoaError = error as NSError
    guard cocoaError.domain == noSpeechDomain, cocoaError.code == noSpeechCode else {
      return .terminal
    }
    return .noSpeech
  }
}

enum SpeechRecognitionSessionElapsedTime {
  private static let nanosecondsPerSecond = 1_000_000_000.0

  static func seconds(
    startedAtNanoseconds: UInt64?,
    observedAtNanoseconds: UInt64
  ) -> TimeInterval {
    guard let startedAtNanoseconds else { return 0 }
    let elapsedNanoseconds: UInt64
    if observedAtNanoseconds >= startedAtNanoseconds {
      elapsedNanoseconds = observedAtNanoseconds - startedAtNanoseconds
    } else {
      elapsedNanoseconds =
        (UInt64.max - startedAtNanoseconds) + observedAtNanoseconds + 1
    }
    return Double(elapsedNanoseconds) / nanosecondsPerSecond
  }
}

final class SpeechRecognitionRollingHandoff<Request, Buffer>: @unchecked Sendable {
  private let lock = NSRecursiveLock()
  private let restartPolicy: SpeechRecognitionRestartPolicy
  private let makeRequest: () -> Request
  private let appendBuffer: (Request, Buffer) -> Void

  private var nextCycleRawValue: UInt64 = 0
  private var operationID: TranscriptionOperationID?
  private var recognition: SpeechRecognitionRequestEndpoint<Request>?
  private var audio: SpeechRecognitionRequestEndpoint<Request>?
  private var standby: SpeechRecognitionRequestEndpoint<Request>?
  private var pendingCleanup: [SpeechRecognitionRequestEndpoint<Request>] = []
  private var consecutiveRapidFinalCount = 0
  private var acceptsAudio = false
  private var gracefulStopCycleID: SpeechRecognitionCycleID?

  init(
    restartPolicy: SpeechRecognitionRestartPolicy = SpeechRecognitionRestartPolicy(),
    makeRequest: @escaping () -> Request,
    appendBuffer: @escaping (Request, Buffer) -> Void
  ) {
    self.restartPolicy = restartPolicy
    self.makeRequest = makeRequest
    self.appendBuffer = appendBuffer
  }

  func beginSession(
    operationID: TranscriptionOperationID
  ) -> SpeechRecognitionSessionStart<Request>? {
    lock.lock()
    defer { lock.unlock() }
    guard recognition == nil, audio == nil, standby == nil, pendingCleanup.isEmpty,
      let activeCycleID = makeCycleIDLocked(),
      let standbyCycleID = makeCycleIDLocked()
    else {
      return nil
    }

    let active = SpeechRecognitionRequestEndpoint(
      cycleID: activeCycleID,
      request: makeRequest(),
      recognitionStartedAtNanoseconds: nil,
      audioStartedAtNanoseconds: nil,
      endAudioWasRequested: false,
      hasAudioBuffers: false
    )
    let standby = SpeechRecognitionRequestEndpoint(
      cycleID: standbyCycleID,
      request: makeRequest(),
      recognitionStartedAtNanoseconds: nil,
      audioStartedAtNanoseconds: nil,
      endAudioWasRequested: false,
      hasAudioBuffers: false
    )
    self.operationID = operationID
    recognition = active
    audio = active
    self.standby = standby
    consecutiveRapidFinalCount = 0
    acceptsAudio = true
    gracefulStopCycleID = nil
    return SpeechRecognitionSessionStart(active: active, standby: standby)
  }

  @discardableResult
  func append(_ buffer: Buffer) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard acceptsAudio, var audio else { return false }
    audio.hasAudioBuffers = true
    updateEndpointLocked(audio)
    appendBuffer(audio.request, buffer)
    return true
  }

  func acceptCallback(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    hasResult: Bool,
    isFinal: Bool,
    hasError: Bool,
    arrivedAtNanoseconds: UInt64
  ) -> SpeechRecognitionCallbackAction<Request> {
    acceptCallback(
      operationID: operationID,
      cycleID: cycleID,
      hasResult: hasResult,
      isFinal: isFinal,
      errorCategory: hasError ? .terminal : .none,
      arrivedAtNanoseconds: arrivedAtNanoseconds
    )
  }

  func acceptCallback(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    hasResult: Bool,
    isFinal: Bool,
    errorCategory: SpeechRecognitionCallbackErrorCategory,
    arrivedAtNanoseconds: UInt64
  ) -> SpeechRecognitionCallbackAction<Request> {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID,
      let recognition,
      recognition.cycleID == cycleID
    else {
      return .reject
    }

    switch errorCategory {
    case .terminal:
      let requests = deactivateForTerminalLocked()
      return .terminate(
        SpeechRecognitionTermination(
          error: .recognitionInterrupted,
          shouldDeliverResult: hasResult,
          requests: requests
        )
      )
    case .noSpeech:
      guard recognition.endAudioWasRequested else {
        let requests = deactivateForTerminalLocked()
        return .terminate(
          SpeechRecognitionTermination(
            error: .recognitionInterrupted,
            shouldDeliverResult: false,
            requests: requests
          )
        )
      }
      return acceptCompletedCycleLocked(
        recognition,
        arrivedAtNanoseconds: arrivedAtNanoseconds,
        shouldDeliverResult: false
      )
    case .none:
      break
    }
    guard hasResult else { return .ignore }
    guard isFinal else { return .deliver }

    return acceptCompletedCycleLocked(
      recognition,
      arrivedAtNanoseconds: arrivedAtNanoseconds,
      shouldDeliverResult: true
    )
  }

  private func acceptCompletedCycleLocked(
    _ recognition: SpeechRecognitionRequestEndpoint<Request>,
    arrivedAtNanoseconds: UInt64,
    shouldDeliverResult: Bool
  ) -> SpeechRecognitionCallbackAction<Request> {
    if gracefulStopCycleID == recognition.cycleID {
      if let audio,
        audio.cycleID != recognition.cycleID,
        audio.hasAudioBuffers
      {
        self.recognition = audio
        standby = nil
        gracefulStopCycleID = audio.cycleID
        return .rollover(
          SpeechRecognitionFinalHandoff(
            completed: recognition,
            activated: audio,
            restartDelayNanoseconds: 0,
            shouldEndCompletedRequest: false,
            shouldDeliverResult: shouldDeliverResult
          )
        )
      }
      let requests = deactivateForTerminalLocked()
      return .complete(
        SpeechRecognitionGracefulCompletion(
          shouldDeliverResult: shouldDeliverResult,
          requests: requests
        )
      )
    }

    switch restartPolicy.decision(
      cycleStartedAtNanoseconds: recognition.audioStartedAtNanoseconds,
      finalArrivedAtNanoseconds: arrivedAtNanoseconds,
      consecutiveRapidFinalCount: &consecutiveRapidFinalCount
    ) {
    case .stop:
      let requests = deactivateForTerminalLocked()
      return .terminate(
        SpeechRecognitionTermination(
          error: .rapidRestartLimitReached,
          shouldDeliverResult: shouldDeliverResult,
          requests: requests
        )
      )
    case .restart(let delay):
      var completed = recognition
      let activated: SpeechRecognitionRequestEndpoint<Request>
      let shouldEndCompletedRequest: Bool
      if let audio, audio.cycleID != recognition.cycleID {
        activated = audio
        shouldEndCompletedRequest = false
      } else {
        guard var standby else {
          let requests = deactivateForTerminalLocked()
          return .terminate(
            SpeechRecognitionTermination(
              error: .recognitionInterrupted,
              shouldDeliverResult: shouldDeliverResult,
              requests: requests
            )
          )
        }
        completed.endAudioWasRequested = true
        updateEndpointLocked(completed)
        standby.audioStartedAtNanoseconds = arrivedAtNanoseconds
        self.audio = standby
        activated = standby
        shouldEndCompletedRequest = true
      }
      self.recognition = activated
      self.standby = nil
      return .rollover(
        SpeechRecognitionFinalHandoff(
          completed: completed,
          activated: activated,
          restartDelayNanoseconds: delay,
          shouldEndCompletedRequest: shouldEndCompletedRequest,
          shouldDeliverResult: shouldDeliverResult
        )
      )
    }
  }

  func requestCycleEnd(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    atNanoseconds: UInt64
  ) -> SpeechRecognitionCycleTimerAction<Request> {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID,
      var recognition,
      recognition.cycleID == cycleID,
      let audio,
      audio.cycleID == cycleID,
      !recognition.endAudioWasRequested,
      acceptsAudio
    else {
      return .reject
    }
    guard var standby else {
      let requests = deactivateForTerminalLocked()
      return .terminate(
        SpeechRecognitionTermination(
          error: .recognitionInterrupted,
          shouldDeliverResult: false,
          requests: requests
        )
      )
    }

    recognition.endAudioWasRequested = true
    updateEndpointLocked(recognition)
    standby.audioStartedAtNanoseconds = atNanoseconds
    self.audio = standby
    self.standby = nil
    return .handoff(
      SpeechRecognitionTimedHandoff(
        completed: recognition,
        buffering: standby
      )
    )
  }

  func requestGracefulStop(
    operationID: TranscriptionOperationID,
    recognitionTaskCycleID: SpeechRecognitionCycleID?,
    permitEmptyCompletion: Bool
  ) -> SpeechRecognitionGracefulStopAction<Request> {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID, var recognition else {
      return .reject
    }

    acceptsAudio = false
    let wasAlreadyAwaitingFinal =
      gracefulStopCycleID == recognition.cycleID && recognition.endAudioWasRequested
    gracefulStopCycleID = recognition.cycleID
    guard recognitionTaskCycleID == recognition.cycleID else {
      return .deferred
    }
    guard !wasAlreadyAwaitingFinal else { return .reject }

    if permitEmptyCompletion, !recognition.hasAudioBuffers {
      let requests = deactivateForTerminalLocked()
      return .complete(
        SpeechRecognitionGracefulCompletion(
          shouldDeliverResult: false,
          requests: requests
        )
      )
    }

    let shouldEndCompletedRequest = !recognition.endAudioWasRequested
    recognition.endAudioWasRequested = true
    updateEndpointLocked(recognition)
    return .awaitFinal(
      completed: recognition,
      shouldEndCompletedRequest: shouldEndCompletedRequest
    )
  }

  func acceptFinalizationTimeout(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID
  ) -> SpeechRecognitionTermination<Request>? {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID,
      let recognition,
      recognition.cycleID == cycleID,
      recognition.endAudioWasRequested,
      audio?.cycleID != cycleID,
      gracefulStopCycleID == nil
    else {
      return nil
    }
    let requests = deactivateForTerminalLocked()
    return SpeechRecognitionTermination(
      error: .recognitionFinalizationTimedOut,
      shouldDeliverResult: false,
      requests: requests
    )
  }

  func installStandby(
    operationID: TranscriptionOperationID,
    activeCycleID: SpeechRecognitionCycleID
  ) -> SpeechRecognitionRequestEndpoint<Request>? {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID,
      recognition?.cycleID == activeCycleID,
      audio?.cycleID == activeCycleID,
      standby == nil,
      let standbyCycleID = makeCycleIDLocked()
    else {
      return nil
    }
    let endpoint = SpeechRecognitionRequestEndpoint(
      cycleID: standbyCycleID,
      request: makeRequest(),
      recognitionStartedAtNanoseconds: nil,
      audioStartedAtNanoseconds: nil,
      endAudioWasRequested: false,
      hasAudioBuffers: false
    )
    standby = endpoint
    return endpoint
  }

  @discardableResult
  func markRecognitionStarted(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    atNanoseconds: UInt64
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID,
      var recognition,
      recognition.cycleID == cycleID,
      recognition.recognitionStartedAtNanoseconds == nil
    else {
      return false
    }
    recognition.recognitionStartedAtNanoseconds = atNanoseconds
    if recognition.audioStartedAtNanoseconds == nil {
      recognition.audioStartedAtNanoseconds = atNanoseconds
    }
    updateEndpointLocked(recognition)
    return true
  }

  func remainingCycleDuration(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    atNanoseconds: UInt64,
    timingPolicy: SpeechRecognitionCycleTimingPolicy
  ) -> UInt64? {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID,
      let recognition,
      recognition.cycleID == cycleID,
      let audio,
      audio.cycleID == cycleID,
      !recognition.endAudioWasRequested,
      let audioStartedAtNanoseconds = recognition.audioStartedAtNanoseconds
    else {
      return nil
    }
    return timingPolicy.remainingCycleDuration(
      audioStartedAtNanoseconds: audioStartedAtNanoseconds,
      nowNanoseconds: atNanoseconds
    )
  }

  func isCurrent(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return self.operationID == operationID && recognition?.cycleID == cycleID
  }

  func terminate(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    error: TranscriptionError,
    shouldDeliverResult: Bool = false
  ) -> SpeechRecognitionTermination<Request>? {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID, recognition?.cycleID == cycleID else {
      return nil
    }
    let requests = deactivateForTerminalLocked()
    return SpeechRecognitionTermination(
      error: error,
      shouldDeliverResult: shouldDeliverResult,
      requests: requests
    )
  }

  func terminateCurrent(
    operationID: TranscriptionOperationID,
    error: TranscriptionError
  ) -> SpeechRecognitionTermination<Request>? {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID, recognition != nil else {
      return nil
    }
    let requests = deactivateForTerminalLocked()
    return SpeechRecognitionTermination(
      error: error,
      shouldDeliverResult: false,
      requests: requests
    )
  }

  func stop(operationID: TranscriptionOperationID) -> [SpeechRecognitionRequestEndpoint<Request>] {
    lock.lock()
    defer { lock.unlock() }
    guard self.operationID == operationID else { return [] }
    return deactivateLocked(includePendingCleanup: true)
  }

  func stopAll() -> [SpeechRecognitionRequestEndpoint<Request>] {
    lock.lock()
    defer { lock.unlock() }
    return deactivateLocked(includePendingCleanup: true)
  }

  var rapidFinalCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return consecutiveRapidFinalCount
  }

  private func makeCycleIDLocked() -> SpeechRecognitionCycleID? {
    guard nextCycleRawValue < UInt64.max else { return nil }
    nextCycleRawValue += 1
    return SpeechRecognitionCycleID(rawValue: nextCycleRawValue)
  }

  private func updateEndpointLocked(
    _ endpoint: SpeechRecognitionRequestEndpoint<Request>
  ) {
    if recognition?.cycleID == endpoint.cycleID { recognition = endpoint }
    if audio?.cycleID == endpoint.cycleID { audio = endpoint }
    if standby?.cycleID == endpoint.cycleID { standby = endpoint }
  }

  private func deactivateForTerminalLocked()
    -> [SpeechRecognitionRequestEndpoint<Request>]
  {
    let requests = deactivateLocked(includePendingCleanup: false)
    pendingCleanup = uniqueEndpoints(pendingCleanup + requests)
    return requests
  }

  private func deactivateLocked(
    includePendingCleanup: Bool
  ) -> [SpeechRecognitionRequestEndpoint<Request>] {
    var requests: [SpeechRecognitionRequestEndpoint<Request>] = []
    if let recognition { requests.append(recognition) }
    if let audio { requests.append(audio) }
    if let standby { requests.append(standby) }
    if includePendingCleanup {
      requests.append(contentsOf: pendingCleanup)
      pendingCleanup = []
    }
    recognition = nil
    audio = nil
    standby = nil
    operationID = nil
    consecutiveRapidFinalCount = 0
    acceptsAudio = false
    gracefulStopCycleID = nil
    return uniqueEndpoints(requests)
  }

  private func uniqueEndpoints(
    _ endpoints: [SpeechRecognitionRequestEndpoint<Request>]
  ) -> [SpeechRecognitionRequestEndpoint<Request>] {
    var seen: Set<SpeechRecognitionCycleID> = []
    return endpoints.filter { seen.insert($0.cycleID).inserted }
  }
}

enum SpeechRecognitionResourceTransition {
  static func finish<Request, Task>(
    request: Request,
    task: Task?,
    shouldEndRequest: Bool = true,
    endRequest: (Request) -> Void,
    cancelTask: (Task) -> Void
  ) {
    if shouldEndRequest {
      endRequest(request)
    }
    if let task {
      cancelTask(task)
    }
  }

  static func rollover<Request, Task>(
    completedRequest: Request,
    completedTask: Task?,
    activatedRequest: Request,
    shouldEndCompletedRequest: Bool = true,
    endRequest: (Request) -> Void,
    cancelTask: (Task) -> Void,
    startTask: (Request) -> Task
  ) -> Task {
    finish(
      request: completedRequest,
      task: completedTask,
      shouldEndRequest: shouldEndCompletedRequest,
      endRequest: endRequest,
      cancelTask: cancelTask
    )
    return startTask(activatedRequest)
  }
}

final class OrderedSpeechCallbackMailbox<Event>: @unchecked Sendable {
  private struct PendingEvent {
    var event: Event
    let coalescingKey: AnyHashable?
  }

  private let condition = NSCondition()
  private let maximumRetainedEventCount: Int
  private let coalescingKey: (Event) -> AnyHashable?
  private let handler: @MainActor (Event) -> Void
  private var pending: [PendingEvent] = []
  private var drainScheduled = false
  private var maximumObservedRetainedEventCount = 0

  init(
    maximumRetainedEventCount: Int = 16,
    coalescingKey: @escaping (Event) -> AnyHashable? = { _ in nil },
    handler: @escaping @MainActor (Event) -> Void
  ) {
    precondition(
      maximumRetainedEventCount > 0,
      "The speech callback mailbox capacity must be positive."
    )
    self.maximumRetainedEventCount = maximumRetainedEventCount
    self.coalescingKey = coalescingKey
    self.handler = handler
  }

  func enqueue(_ event: Event) {
    let key = coalescingKey(event)
    while true {
      let shouldSchedule: Bool
      condition.lock()
      if let key, pending.last?.coalescingKey == key {
        pending[pending.count - 1].event = event
        condition.unlock()
        return
      }

      if pending.count == maximumRetainedEventCount,
        let disposableIndex = pending.firstIndex(where: { $0.coalescingKey != nil })
      {
        pending.remove(at: disposableIndex)
      }

      if pending.count < maximumRetainedEventCount {
        pending.append(PendingEvent(event: event, coalescingKey: key))
        maximumObservedRetainedEventCount = max(
          maximumObservedRetainedEventCount,
          pending.count
        )
        if drainScheduled {
          shouldSchedule = false
        } else {
          drainScheduled = true
          shouldSchedule = true
        }
        condition.unlock()

        guard shouldSchedule else { return }
        Task { @MainActor [weak self] in
          self?.drain()
        }
        return
      }

      if Thread.isMainThread {
        condition.unlock()
        MainActor.assumeIsolated {
          drainOne()
        }
      } else {
        condition.wait()
        condition.unlock()
      }
    }
  }

  var retainedEventCount: Int {
    condition.lock()
    defer { condition.unlock() }
    return pending.count
  }

  var maximumObservedEventCount: Int {
    condition.lock()
    defer { condition.unlock() }
    return maximumObservedRetainedEventCount
  }

  @MainActor
  private func drainOne() {
    let next: Event?
    condition.lock()
    if pending.isEmpty {
      drainScheduled = false
      next = nil
    } else {
      next = pending.removeFirst().event
      condition.broadcast()
    }
    condition.unlock()

    guard let next else { return }
    handler(next)
  }

  @MainActor
  private func drain() {
    while true {
      condition.lock()
      let hasPendingEvents = !pending.isEmpty
      condition.unlock()
      guard hasPendingEvents else {
        drainOne()
        return
      }
      drainOne()
    }
  }
}

final class SerializedSpeechCallbackIngress: @unchecked Sendable {
  private let lock = NSRecursiveLock()

  func perform(_ work: () -> Void) {
    lock.lock()
    defer { lock.unlock() }
    work()
  }
}

struct SpeechRecognitionProviderLifecycle: Sendable {
  private(set) var latestOperationID: TranscriptionOperationID?
  private(set) var activeOperationID: TranscriptionOperationID?

  mutating func acceptStart(_ operationID: TranscriptionOperationID) -> Bool {
    if let latestOperationID, operationID.rawValue <= latestOperationID.rawValue {
      return false
    }
    latestOperationID = operationID
    activeOperationID = operationID
    return true
  }

  func isCurrent(_ operationID: TranscriptionOperationID) -> Bool {
    activeOperationID == operationID
  }

  @discardableResult
  mutating func finish(_ operationID: TranscriptionOperationID) -> Bool {
    guard isCurrent(operationID) else { return false }
    activeOperationID = nil
    return true
  }
}

private struct AppleSpeechCallbackEvent: @unchecked Sendable {
  let operationID: TranscriptionOperationID
  let cycleID: SpeechRecognitionCycleID
  let result: SFSpeechRecognitionResult?
  let sourceMachTime: UInt64
  let observedAtUptimeNanoseconds: UInt64
  let action: SpeechRecognitionCallbackAction<SFSpeechAudioBufferRecognitionRequest>
}

private struct AppleSpeechPartialCallbackKey: Hashable {
  let operationID: TranscriptionOperationID
  let cycleID: SpeechRecognitionCycleID
}

private struct AppleSpeechRequestCleanup {
  let request: SFSpeechAudioBufferRecognitionRequest
  let shouldEndAudio: Bool
}

@MainActor
final class AppleSpeechRecognizerProvider: TranscriptionProvider {
  private let timingPolicy = SpeechRecognitionCycleTimingPolicy()
  private let audioEngine = AVAudioEngine()
  private let rollingHandoff = SpeechRecognitionRollingHandoff<
    SFSpeechAudioBufferRecognitionRequest,
    AVAudioPCMBuffer
  >(
    makeRequest: { OnDeviceSpeechRecognitionPolicy.makeRequest() },
    appendBuffer: { request, buffer in request.append(buffer) }
  )
  private lazy var callbackMailbox = OrderedSpeechCallbackMailbox<AppleSpeechCallbackEvent>(
    maximumRetainedEventCount: 8,
    coalescingKey: { event in
      guard case .deliver = event.action else { return nil }
      return AnyHashable(
        AppleSpeechPartialCallbackKey(
          operationID: event.operationID,
          cycleID: event.cycleID
        )
      )
    },
    handler: { [weak self] event in
      self?.receiveCallbackEvent(event)
    }
  )
  private let callbackIngress = SerializedSpeechCallbackIngress()

  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionRequestHasEndedAudio = false
  private var recognitionTask: SFSpeechRecognitionTask?
  private var recognitionTaskCycleID: SpeechRecognitionCycleID?
  private var speechRecognizer: SFSpeechRecognizer?
  private var sessionLanguage: LanguageTag?
  private var observationHandler: (@MainActor (TranscriptionObservation) -> Void)?
  private var terminalEventHandler: (@MainActor (TranscriptionTerminalEvent) -> Void)?
  private var sessionStartedAtUptimeNanoseconds: UInt64?
  private var tapInstalled = false
  private var restartTask: Task<Void, Never>?
  private var cycleEndTask: Task<Void, Never>?
  private var finalizationTimeoutTask: Task<Void, Never>?
  private var gracefulStopTimeoutTask: Task<Void, Never>?
  private var gracefulStopRequestedOperationID: TranscriptionOperationID?
  private var hasBegunRecognitionSession = false
  private var lifecycle = SpeechRecognitionProviderLifecycle()
  private var segmentIdentityStore = SpeechRecognitionSegmentIdentityStore()

  func start(
    operationID: TranscriptionOperationID,
    language: LanguageTag,
    onObservation: @escaping @MainActor (TranscriptionObservation) -> Void,
    onTerminalEvent: @escaping @MainActor (TranscriptionTerminalEvent) -> Void
  ) async throws {
    guard lifecycle.acceptStart(operationID) else {
      throw CancellationError()
    }
    stopResources()

    observationHandler = onObservation
    terminalEventHandler = onTerminalEvent

    guard let authorized = await requestAuthorization(for: operationID) else {
      throw CancellationError()
    }
    guard authorized else {
      failStart(operationID: operationID)
      throw TranscriptionError.authorizationDenied
    }

    guard
      let recognizer = SFSpeechRecognizer(
        locale: Locale(identifier: language.rawValue)
      )
    else {
      failStart(operationID: operationID)
      throw TranscriptionError.recognizerUnavailable
    }

    do {
      try validate(recognizer: recognizer)
    } catch {
      failStart(operationID: operationID)
      throw error
    }

    speechRecognizer = recognizer
    sessionLanguage = language
    sessionStartedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      failStart(operationID: operationID)
      throw TranscriptionError.noAudioInput
    }

    guard let session = rollingHandoff.beginSession(operationID: operationID) else {
      failStart(operationID: operationID)
      throw TranscriptionError.recognitionInterrupted
    }
    hasBegunRecognitionSession = true

    inputNode.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: format,
      block: SpeechRecognitionAudioCallback.make { [rollingHandoff] buffer in
        rollingHandoff.append(buffer)
      }
    )
    tapInstalled = true

    recognitionRequest = session.active.request
    recognitionRequestHasEndedAudio = false
    recognitionTaskCycleID = session.active.cycleID
    recognitionTask = makeRecognitionTask(
      recognizer: recognizer,
      request: session.active.request,
      operationID: operationID,
      cycleID: session.active.cycleID
    )
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      failStart(operationID: operationID)
      throw TranscriptionError.noAudioInput
    }
    let cycleStartedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
    guard
      rollingHandoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: cycleStartedAtNanoseconds
      ),
      scheduleCycleEnd(
        operationID: operationID,
        cycleID: session.active.cycleID,
        atNanoseconds: cycleStartedAtNanoseconds
      )
    else {
      failStart(operationID: operationID)
      throw CancellationError()
    }
  }

  func stop(operationID: TranscriptionOperationID) {
    guard lifecycle.finish(operationID) else { return }
    stopResources(additionalRequests: rollingHandoff.stop(operationID: operationID))
  }

  func finishCurrentSegment(operationID: TranscriptionOperationID) {
    guard lifecycle.isCurrent(operationID) else { return }
    guard hasBegunRecognitionSession else {
      finishGracefully(operationID: operationID, additionalRequests: [])
      return
    }
    gracefulStopRequestedOperationID = operationID
    stopAudioInput()
    cycleEndTask?.cancel()
    cycleEndTask = nil
    finalizationTimeoutTask?.cancel()
    finalizationTimeoutTask = nil
    scheduleGracefulStopTimeout(operationID: operationID)
    continueGracefulStop(
      operationID: operationID,
      permitEmptyCompletion: false
    )
  }

  private func failStart(operationID: TranscriptionOperationID) {
    guard lifecycle.finish(operationID) else { return }
    stopResources(additionalRequests: rollingHandoff.stop(operationID: operationID))
  }

  private func stopResources(
    additionalRequests: [SpeechRecognitionRequestEndpoint<
      SFSpeechAudioBufferRecognitionRequest
    >] = []
  ) {
    restartTask?.cancel()
    restartTask = nil
    cycleEndTask?.cancel()
    cycleEndTask = nil
    finalizationTimeoutTask?.cancel()
    finalizationTimeoutTask = nil
    gracefulStopTimeoutTask?.cancel()
    gracefulStopTimeoutTask = nil
    let retainedRequests = rollingHandoff.stopAll()
    stopAudioInput()

    var requests = additionalRequests.map {
      AppleSpeechRequestCleanup(
        request: $0.request,
        shouldEndAudio: !$0.endAudioWasRequested
      )
    }
    requests.append(
      contentsOf: retainedRequests.map {
        AppleSpeechRequestCleanup(
          request: $0.request,
          shouldEndAudio: !$0.endAudioWasRequested
        )
      }
    )
    if let recognitionRequest {
      requests.append(
        AppleSpeechRequestCleanup(
          request: recognitionRequest,
          shouldEndAudio: !recognitionRequestHasEndedAudio
        )
      )
    }
    endUniqueRequests(requests)
    recognitionTask?.cancel()

    recognitionRequest = nil
    recognitionRequestHasEndedAudio = false
    recognitionTask = nil
    recognitionTaskCycleID = nil
    speechRecognizer = nil
    sessionLanguage = nil
    observationHandler = nil
    terminalEventHandler = nil
    sessionStartedAtUptimeNanoseconds = nil
    gracefulStopRequestedOperationID = nil
    hasBegunRecognitionSession = false
    segmentIdentityStore.reset()
  }

  private func stopAudioInput() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
  }

  private func makeRecognitionTask(
    recognizer: SFSpeechRecognizer,
    request: SFSpeechAudioBufferRecognitionRequest,
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID
  ) -> SFSpeechRecognitionTask {
    let rollingHandoff = rollingHandoff
    let callbackMailbox = callbackMailbox
    let callbackIngress = callbackIngress
    return recognizer.recognitionTask(with: request) { @Sendable result, error in
      callbackIngress.perform {
        let observedAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        let action = rollingHandoff.acceptCallback(
          operationID: operationID,
          cycleID: cycleID,
          hasResult: result != nil,
          isFinal: result?.isFinal == true,
          errorCategory: SpeechRecognitionCallbackErrorPolicy.category(for: error),
          arrivedAtNanoseconds: observedAtUptimeNanoseconds
        )
        switch action {
        case .reject, .ignore:
          return
        case .deliver, .rollover, .complete, .terminate:
          callbackMailbox.enqueue(
            AppleSpeechCallbackEvent(
              operationID: operationID,
              cycleID: cycleID,
              result: result,
              sourceMachTime: mach_absolute_time(),
              observedAtUptimeNanoseconds: observedAtUptimeNanoseconds,
              action: action
            )
          )
        }
      }
    }
  }

  private func receiveCallbackEvent(_ event: AppleSpeechCallbackEvent) {
    guard lifecycle.isCurrent(event.operationID) else { return }

    switch event.action {
    case .reject, .ignore:
      return
    case .deliver:
      guard
        deliver(
          result: event.result,
          cycleID: event.cycleID,
          sourceMachTime: event.sourceMachTime,
          observedAtUptimeNanoseconds: event.observedAtUptimeNanoseconds
        )
      else {
        terminate(
          operationID: event.operationID,
          error: .recognitionInterrupted
        )
        return
      }
    case .rollover(let handoff):
      cycleEndTask?.cancel()
      cycleEndTask = nil
      finalizationTimeoutTask?.cancel()
      finalizationTimeoutTask = nil
      let restartError = prepareRollover(
        handoff,
        operationID: event.operationID
      )
      if handoff.shouldDeliverResult {
        guard
          deliver(
            result: event.result,
            cycleID: event.cycleID,
            sourceMachTime: event.sourceMachTime,
            observedAtUptimeNanoseconds: event.observedAtUptimeNanoseconds
          )
        else {
          terminate(
            operationID: event.operationID,
            error: .recognitionInterrupted,
            additionalRequests: [handoff.completed, handoff.activated]
          )
          return
        }
      }
      if let restartError {
        terminate(
          operationID: event.operationID,
          error: restartError,
          additionalRequests: [handoff.completed, handoff.activated]
        )
        return
      }
      continueGracefulStop(
        operationID: event.operationID,
        permitEmptyCompletion: true
      )
    case .complete(let completion):
      cycleEndTask?.cancel()
      cycleEndTask = nil
      finalizationTimeoutTask?.cancel()
      finalizationTimeoutTask = nil
      guard gracefulStopRequestedOperationID == event.operationID else {
        terminate(
          operationID: event.operationID,
          error: .recognitionInterrupted,
          additionalRequests: completion.requests
        )
        return
      }
      if completion.shouldDeliverResult,
        !deliver(
          result: event.result,
          cycleID: event.cycleID,
          sourceMachTime: event.sourceMachTime,
          observedAtUptimeNanoseconds: event.observedAtUptimeNanoseconds
        )
      {
        terminate(
          operationID: event.operationID,
          error: .recognitionInterrupted,
          additionalRequests: completion.requests
        )
        return
      }
      finishGracefully(
        operationID: event.operationID,
        additionalRequests: completion.requests
      )
    case .terminate(let termination):
      cycleEndTask?.cancel()
      cycleEndTask = nil
      finalizationTimeoutTask?.cancel()
      finalizationTimeoutTask = nil
      if termination.shouldDeliverResult {
        _ = deliver(
          result: event.result,
          cycleID: event.cycleID,
          sourceMachTime: event.sourceMachTime,
          observedAtUptimeNanoseconds: event.observedAtUptimeNanoseconds
        )
      }
      terminate(
        operationID: event.operationID,
        error: termination.error,
        additionalRequests: termination.requests
      )
    }
  }

  private func prepareRollover(
    _ handoff: SpeechRecognitionFinalHandoff<SFSpeechAudioBufferRecognitionRequest>,
    operationID: TranscriptionOperationID
  ) -> TranscriptionError? {
    guard recognitionTaskCycleID == handoff.completed.cycleID,
      recognitionRequest === handoff.completed.request
    else {
      if handoff.shouldEndCompletedRequest {
        handoff.completed.request.endAudio()
      }
      return .recognitionInterrupted
    }

    SpeechRecognitionResourceTransition.finish(
      request: handoff.completed.request,
      task: recognitionTask,
      shouldEndRequest: handoff.shouldEndCompletedRequest,
      endRequest: { $0.endAudio() },
      cancelTask: { $0.cancel() }
    )
    if handoff.shouldEndCompletedRequest {
      recognitionRequestHasEndedAudio = true
    }
    recognitionRequest = nil
    recognitionRequestHasEndedAudio = false
    recognitionTask = nil
    recognitionTaskCycleID = nil

    guard let recognizer = speechRecognizer else {
      return .recognitionInterrupted
    }
    do {
      try validate(recognizer: recognizer)
    } catch let error as TranscriptionError {
      return error
    } catch {
      return .recognitionInterrupted
    }
    guard
      rollingHandoff.installStandby(
        operationID: operationID,
        activeCycleID: handoff.activated.cycleID
      ) != nil
    else {
      return .recognitionInterrupted
    }

    if handoff.restartDelayNanoseconds == 0 {
      return startActivatedCycle(
        handoff.activated,
        recognizer: recognizer,
        operationID: operationID
      )
    }

    restartTask?.cancel()
    restartTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: handoff.restartDelayNanoseconds)
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.restartTask = nil
      guard self.lifecycle.isCurrent(operationID) else { return }
      guard
        let currentRecognizer = self.speechRecognizer,
        self.rollingHandoff.isCurrent(
          operationID: operationID,
          cycleID: handoff.activated.cycleID
        )
      else {
        return
      }
      if let error = self.startActivatedCycle(
        handoff.activated,
        recognizer: currentRecognizer,
        operationID: operationID
      ) {
        self.terminate(
          operationID: operationID,
          error: error
        )
        return
      }
      self.continueGracefulStop(
        operationID: operationID,
        permitEmptyCompletion: true
      )
    }
    return nil
  }

  private func startActivatedCycle(
    _ endpoint: SpeechRecognitionRequestEndpoint<SFSpeechAudioBufferRecognitionRequest>,
    recognizer: SFSpeechRecognizer,
    operationID: TranscriptionOperationID
  ) -> TranscriptionError? {
    guard lifecycle.isCurrent(operationID),
      rollingHandoff.isCurrent(
        operationID: operationID,
        cycleID: endpoint.cycleID
      )
    else {
      return .recognitionInterrupted
    }
    do {
      try validate(recognizer: recognizer)
    } catch let error as TranscriptionError {
      return error
    } catch {
      return .recognitionInterrupted
    }

    recognitionRequest = endpoint.request
    recognitionRequestHasEndedAudio = false
    recognitionTaskCycleID = endpoint.cycleID
    recognitionTask = makeRecognitionTask(
      recognizer: recognizer,
      request: endpoint.request,
      operationID: operationID,
      cycleID: endpoint.cycleID
    )
    let recognitionStartedAtNanoseconds = DispatchTime.now().uptimeNanoseconds
    guard
      rollingHandoff.markRecognitionStarted(
        operationID: operationID,
        cycleID: endpoint.cycleID,
        atNanoseconds: recognitionStartedAtNanoseconds
      ),
      scheduleCycleEnd(
        operationID: operationID,
        cycleID: endpoint.cycleID,
        atNanoseconds: recognitionStartedAtNanoseconds
      )
    else {
      return .recognitionInterrupted
    }
    return nil
  }

  private func scheduleCycleEnd(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    atNanoseconds: UInt64
  ) -> Bool {
    guard
      let delay = rollingHandoff.remainingCycleDuration(
        operationID: operationID,
        cycleID: cycleID,
        atNanoseconds: atNanoseconds,
        timingPolicy: timingPolicy
      )
    else {
      return false
    }

    cycleEndTask?.cancel()
    cycleEndTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: delay)
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.cycleEndTask = nil
      guard self.lifecycle.isCurrent(operationID) else { return }
      self.handleCycleEnd(
        operationID: operationID,
        cycleID: cycleID,
        atNanoseconds: DispatchTime.now().uptimeNanoseconds
      )
    }
    return true
  }

  private func handleCycleEnd(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID,
    atNanoseconds: UInt64
  ) {
    switch rollingHandoff.requestCycleEnd(
      operationID: operationID,
      cycleID: cycleID,
      atNanoseconds: atNanoseconds
    ) {
    case .reject:
      return
    case .handoff(let handoff):
      guard recognitionTaskCycleID == handoff.completed.cycleID,
        recognitionRequest === handoff.completed.request
      else {
        handoff.completed.request.endAudio()
        let termination = rollingHandoff.terminate(
          operationID: operationID,
          cycleID: handoff.completed.cycleID,
          error: .recognitionInterrupted
        )
        terminate(
          operationID: operationID,
          error: .recognitionInterrupted,
          additionalRequests: termination?.requests ?? [
            handoff.completed,
            handoff.buffering,
          ]
        )
        return
      }
      handoff.completed.request.endAudio()
      recognitionRequestHasEndedAudio = true
      scheduleFinalizationTimeout(
        operationID: operationID,
        cycleID: handoff.completed.cycleID
      )
    case .terminate(let termination):
      terminate(
        operationID: operationID,
        error: termination.error,
        additionalRequests: termination.requests
      )
    }
  }

  private func scheduleFinalizationTimeout(
    operationID: TranscriptionOperationID,
    cycleID: SpeechRecognitionCycleID
  ) {
    finalizationTimeoutTask?.cancel()
    let delay = timingPolicy.finalizationTimeoutNanoseconds
    finalizationTimeoutTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: delay)
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.finalizationTimeoutTask = nil
      guard self.lifecycle.isCurrent(operationID) else { return }
      guard
        let termination = self.rollingHandoff.acceptFinalizationTimeout(
          operationID: operationID,
          cycleID: cycleID
        )
      else {
        return
      }
      self.terminate(
        operationID: operationID,
        error: termination.error,
        additionalRequests: termination.requests
      )
    }
  }

  private func continueGracefulStop(
    operationID: TranscriptionOperationID,
    permitEmptyCompletion: Bool
  ) {
    guard gracefulStopRequestedOperationID == operationID,
      lifecycle.isCurrent(operationID)
    else {
      return
    }
    cycleEndTask?.cancel()
    cycleEndTask = nil

    switch rollingHandoff.requestGracefulStop(
      operationID: operationID,
      recognitionTaskCycleID: recognitionTaskCycleID,
      permitEmptyCompletion: permitEmptyCompletion
    ) {
    case .reject, .deferred:
      return
    case .awaitFinal(let completed, let shouldEndCompletedRequest):
      guard recognitionTaskCycleID == completed.cycleID,
        recognitionRequest === completed.request
      else {
        if shouldEndCompletedRequest {
          completed.request.endAudio()
        }
        let termination = rollingHandoff.terminateCurrent(
          operationID: operationID,
          error: .recognitionInterrupted
        )
        terminate(
          operationID: operationID,
          error: .recognitionInterrupted,
          additionalRequests: termination?.requests ?? [completed]
        )
        return
      }
      if shouldEndCompletedRequest {
        completed.request.endAudio()
        recognitionRequestHasEndedAudio = true
      }
    case .complete(let completion):
      finishGracefully(
        operationID: operationID,
        additionalRequests: completion.requests
      )
    }
  }

  private func scheduleGracefulStopTimeout(
    operationID: TranscriptionOperationID
  ) {
    guard gracefulStopTimeoutTask == nil else { return }
    let delay = timingPolicy.finalizationTimeoutNanoseconds
    gracefulStopTimeoutTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(nanoseconds: delay)
      } catch {
        return
      }
      guard !Task.isCancelled, let self else { return }
      self.gracefulStopTimeoutTask = nil
      guard self.lifecycle.isCurrent(operationID),
        self.gracefulStopRequestedOperationID == operationID,
        let termination = self.rollingHandoff.terminateCurrent(
          operationID: operationID,
          error: .recognitionFinalizationTimedOut
        )
      else {
        return
      }
      self.terminate(
        operationID: operationID,
        error: termination.error,
        additionalRequests: termination.requests
      )
    }
  }

  private func deliver(
    result: SFSpeechRecognitionResult?,
    cycleID: SpeechRecognitionCycleID,
    sourceMachTime: UInt64,
    observedAtUptimeNanoseconds: UInt64
  ) -> Bool {
    guard let result else { return true }
    guard let language = sessionLanguage, let observationHandler else {
      return false
    }
    let elapsed = SpeechRecognitionSessionElapsedTime.seconds(
      startedAtNanoseconds: sessionStartedAtUptimeNanoseconds,
      observedAtNanoseconds: observedAtUptimeNanoseconds
    )
    observationHandler(
      TranscriptionObservation(
        segment: TranscriptSegment(
          id: segmentIdentityStore.identifier(for: cycleID),
          text: result.bestTranscription.formattedString,
          startTime: 0,
          endTime: elapsed,
          language: language,
          confidence: confidence(from: result.bestTranscription),
          isFinal: result.isFinal,
          emphasis: 0.5
        ),
        sourceMachTime: sourceMachTime
      )
    )
    return true
  }

  private func terminate(
    operationID: TranscriptionOperationID,
    error: TranscriptionError,
    additionalRequests: [SpeechRecognitionRequestEndpoint<
      SFSpeechAudioBufferRecognitionRequest
    >] = []
  ) {
    guard lifecycle.finish(operationID) else { return }
    let terminalEventHandler = terminalEventHandler
    stopResources(additionalRequests: additionalRequests)
    terminalEventHandler?(
      TranscriptionTerminalEvent(operationID: operationID, error: error)
    )
  }

  private func finishGracefully(
    operationID: TranscriptionOperationID,
    additionalRequests: [SpeechRecognitionRequestEndpoint<
      SFSpeechAudioBufferRecognitionRequest
    >]
  ) {
    guard lifecycle.finish(operationID) else { return }
    let terminalEventHandler = terminalEventHandler
    stopResources(additionalRequests: additionalRequests)
    terminalEventHandler?(
      TranscriptionTerminalEvent(
        operationID: operationID,
        outcome: .gracefulStopCompleted
      )
    )
  }

  private func validate(recognizer: SFSpeechRecognizer) throws {
    switch OnDeviceSpeechRecognitionPolicy.decision(
      recognizerAvailable: recognizer.isAvailable,
      supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition
    ) {
    case .accept:
      return
    case .recognizerUnavailable:
      throw TranscriptionError.recognizerUnavailable
    case .onDeviceRecognitionUnavailable:
      throw TranscriptionError.onDeviceRecognitionUnavailable
    }
  }

  private func requestAuthorization(
    for operationID: TranscriptionOperationID
  ) async -> Bool? {
    let microphone = await AVCaptureDevice.requestAccess(for: .audio)
    guard lifecycle.isCurrent(operationID) else { return nil }
    guard microphone else { return false }

    let speech: Bool = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization(
        SpeechRecognitionAuthorizationCallback.make(continuation: continuation)
      )
    }
    guard lifecycle.isCurrent(operationID) else { return nil }
    return speech
  }

  private func endUniqueRequests(_ cleanups: [AppleSpeechRequestCleanup]) {
    var requestsByIdentifier: [ObjectIdentifier: AppleSpeechRequestCleanup] = [:]
    for cleanup in cleanups {
      let identifier = ObjectIdentifier(cleanup.request)
      if let existing = requestsByIdentifier[identifier] {
        requestsByIdentifier[identifier] = AppleSpeechRequestCleanup(
          request: existing.request,
          shouldEndAudio: existing.shouldEndAudio && cleanup.shouldEndAudio
        )
      } else {
        requestsByIdentifier[identifier] = cleanup
      }
    }
    for cleanup in requestsByIdentifier.values where cleanup.shouldEndAudio {
      cleanup.request.endAudio()
    }
  }

  private func confidence(from transcription: SFTranscription) -> Double {
    guard !transcription.segments.isEmpty else { return 0.5 }
    let total = transcription.segments.reduce(0.0) { partial, segment in
      partial + Double(segment.confidence)
    }
    return min(
      max(total / Double(transcription.segments.count), 0),
      1
    )
  }
}
