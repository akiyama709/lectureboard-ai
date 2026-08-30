@preconcurrency import AVFoundation
import Darwin
import Foundation
import LectureBoardCore
@preconcurrency import Speech

@MainActor
final class AppleSpeechRecognizerProvider: TranscriptionProvider {
  private let audioEngine = AVAudioEngine()
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var startedAt: Date?
  private var tapInstalled = false

  func start(
    language: LanguageTag,
    onObservation: @escaping @MainActor (TranscriptionObservation) -> Void
  ) async throws {
    stop()

    guard await requestAuthorization() else {
      throw TranscriptionError.authorizationDenied
    }

    guard
      let recognizer = SFSpeechRecognizer(
        locale: Locale(identifier: language.rawValue)
      ),
      recognizer.isAvailable
    else {
      throw TranscriptionError.recognizerUnavailable
    }

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.addsPunctuation = true
    recognitionRequest = request
    startedAt = Date()

    let inputNode = audioEngine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      throw TranscriptionError.noAudioInput
    }

    inputNode.installTap(
      onBus: 0,
      bufferSize: 1_024,
      format: format
    ) { [weak request] buffer, _ in
      request?.append(buffer)
    }
    tapInstalled = true

    recognitionTask = recognizer.recognitionTask(with: request) {
      [weak self] result, error in
      let sourceMachTime = mach_absolute_time()
      Task { @MainActor [weak self] in
        guard let self else { return }

        if let result {
          let elapsed =
            self.startedAt.map {
              Date().timeIntervalSince($0)
            } ?? 0
          let segment = TranscriptSegment(
            text: result.bestTranscription.formattedString,
            startTime: 0,
            endTime: elapsed,
            language: language,
            confidence: self.confidence(
              from: result.bestTranscription
            ),
            isFinal: result.isFinal,
            emphasis: 0.5
          )
          onObservation(
            TranscriptionObservation(
              segment: segment,
              sourceMachTime: sourceMachTime
            )
          )
        }

        if error != nil {
          self.stop()
        }
      }
    }

    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch {
      stop()
      throw TranscriptionError.noAudioInput
    }
  }

  func stop() {
    if audioEngine.isRunning {
      audioEngine.stop()
    }
    if tapInstalled {
      audioEngine.inputNode.removeTap(onBus: 0)
      tapInstalled = false
    }
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionRequest = nil
    recognitionTask = nil
    startedAt = nil
  }

  private func requestAuthorization() async -> Bool {
    let microphone = await AVCaptureDevice.requestAccess(for: .audio)
    guard microphone else { return false }

    let speech: Bool = await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
    return speech
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
