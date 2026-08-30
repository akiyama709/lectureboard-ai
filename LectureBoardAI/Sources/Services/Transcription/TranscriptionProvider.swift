import Foundation
import LectureBoardCore

struct TranscriptionObservation: Sendable {
  let segment: TranscriptSegment
  /// Locally sampled mach absolute time when the speech callback delivered this result.
  let sourceMachTime: UInt64
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
