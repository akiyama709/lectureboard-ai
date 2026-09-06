import Foundation
import LectureBoardCore

struct TranscriptionObservation: Sendable {
  let segment: TranscriptSegment
  /// Locally sampled mach absolute time when the speech callback delivered this result.
  let sourceMachTime: UInt64
}

enum TranscriptionTerminalOutcome: Equatable, Sendable {
  case gracefulStopCompleted
  case failure(TranscriptionError)
}

struct TranscriptionTerminalEvent: Equatable, Sendable {
  let operationID: TranscriptionOperationID
  let outcome: TranscriptionTerminalOutcome

  init(
    operationID: TranscriptionOperationID,
    outcome: TranscriptionTerminalOutcome
  ) {
    self.operationID = operationID
    self.outcome = outcome
  }

  init(operationID: TranscriptionOperationID, error: TranscriptionError) {
    self.init(operationID: operationID, outcome: .failure(error))
  }
}

/// An opaque identifier for one transcription start operation.
///
/// Callers deliberately cannot construct or inspect identifiers. A retained callback must
/// present the identifier that was current when the callback was installed, preventing a
/// delayed result from a stopped recognizer from entering a later transcription context.
struct TranscriptionOperationID: Equatable, Hashable, Sendable {
  let rawValue: UInt64
}

struct TranscriptionOperationGate: Sendable {
  private var nextRawValue: UInt64 = 0
  private(set) var activeOperationID: TranscriptionOperationID?

  var hasActiveOperation: Bool {
    activeOperationID != nil
  }

  mutating func begin() -> TranscriptionOperationID {
    precondition(
      nextRawValue < UInt64.max,
      "Transcription operation identifier exhausted."
    )
    nextRawValue += 1
    let operationID = TranscriptionOperationID(rawValue: nextRawValue)
    activeOperationID = operationID
    return operationID
  }

  func accepts(_ operationID: TranscriptionOperationID) -> Bool {
    activeOperationID == operationID
  }

  mutating func invalidate() {
    activeOperationID = nil
  }

  @discardableResult
  mutating func invalidate(ifCurrent operationID: TranscriptionOperationID) -> Bool {
    guard accepts(operationID) else { return false }
    invalidate()
    return true
  }
}

@MainActor
protocol TranscriptionProvider: AnyObject {
  func start(
    operationID: TranscriptionOperationID,
    language: LanguageTag,
    onObservation: @escaping @MainActor (TranscriptionObservation) -> Void,
    onTerminalEvent: @escaping @MainActor (TranscriptionTerminalEvent) -> Void
  ) async throws
  func finishCurrentSegment(operationID: TranscriptionOperationID)
  func stop(operationID: TranscriptionOperationID)
}

enum TranscriptionError: LocalizedError, Equatable, Sendable {
  case authorizationDenied
  case recognizerUnavailable
  case onDeviceRecognitionUnavailable
  case noAudioInput
  case recognitionInterrupted
  case recognitionFinalizationTimedOut
  case rapidRestartLimitReached

  var errorDescription: String? {
    switch self {
    case .authorizationDenied:
      return String(localized: "error.authorizationDenied")
    case .recognizerUnavailable:
      return String(localized: "error.recognizerUnavailable")
    case .onDeviceRecognitionUnavailable:
      return String(localized: "error.onDeviceRecognitionUnavailable")
    case .noAudioInput:
      return String(localized: "error.noAudioInput")
    case .recognitionInterrupted:
      return String(localized: "error.recognitionInterrupted")
    case .recognitionFinalizationTimedOut:
      return String(localized: "error.recognitionFinalizationTimedOut")
    case .rapidRestartLimitReached:
      return String(localized: "error.rapidRestartLimitReached")
    }
  }
}
