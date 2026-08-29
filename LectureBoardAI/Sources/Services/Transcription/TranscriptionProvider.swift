import Foundation
import LectureBoardCore

@MainActor
protocol TranscriptionProvider: AnyObject {
  func start(
    language: LanguageTag,
    onSegment: @escaping @MainActor (TranscriptSegment) -> Void
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
