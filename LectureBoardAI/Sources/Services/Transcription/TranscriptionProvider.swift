import Foundation
import LectureBoardCore

struct TranscriptionObservation: Sendable {
  let segment: TranscriptSegment
  /// Locally sampled mach absolute time when the speech callback delivered this result.
  let sourceMachTime: UInt64
}

/// An opaque identifier for one transcription start operation.
///
/// Callers deliberately cannot construct or inspect identifiers. A retained callback must
/// present the identifier that was current when the callback was installed, preventing a
/// delayed result from a stopped recognizer from entering a later transcription context.
struct TranscriptionOperationID: Equatable, Sendable {
  fileprivate let rawValue: UInt64
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
    language: LanguageTag,
    onObservation: @escaping @MainActor (TranscriptionObservation) -> Void
  ) async throws
  func stop()
}

enum TranscriptionError: LocalizedError {
  case authorizationDenied
  case recognizerUnavailable
  case noAudioInput

  var errorDescription: String? {
    switch self {
    case .authorizationDenied:
      return String(localized: "error.authorizationDenied")
    case .recognizerUnavailable:
      return String(localized: "error.recognizerUnavailable")
    case .noAudioInput:
      return String(localized: "error.noAudioInput")
    }
  }
}
