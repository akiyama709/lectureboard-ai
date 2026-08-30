import Foundation
import Testing

@testable import LectureBoardCore

struct RuntimeVerificationConfigurationTests {
  @Test func parsesValidArguments() throws {
    let parsed = try RuntimeVerificationArguments.parse([
      "/Applications/LectureBoard AI.app/Contents/MacOS/LectureBoard AI",
      "--runtime-verification",
      "-NSDocumentRevisionsDebugMode",
      "YES",
      "--window-title-contains",
      "  LectureBoard Runtime Verification  ",
      "--observation-seconds",
      "12.5",
      "--output-path",
      "/tmp/lectureboard-runtime.json",
      "--request-screen-recording",
    ])
    let configuration = try #require(parsed)

    #expect(configuration.targetWindowTitleSubstring == "LectureBoard Runtime Verification")
    #expect(configuration.observationDurationSeconds == 12.5)
    #expect(configuration.outputPath == "/tmp/lectureboard-runtime.json")
    #expect(configuration.requestsScreenRecordingPermission)
  }

  @Test func defaultsScreenRecordingRequestToFalse() throws {
    let parsed = try RuntimeVerificationArguments.parse([
      "--runtime-verification",
      "--window-title-contains",
      "Verification",
      "--observation-seconds",
      "10",
      "--output-path",
      "/tmp/result.json",
    ])

    #expect(try #require(parsed).requestsScreenRecordingPermission == false)
  }

  @Test func reportsMissingOptionAndValue() {
    assertParseError(
      [
        "--runtime-verification",
        "--window-title-contains",
        "Verification",
        "--observation-seconds",
        "10",
      ],
      equals: .missingRequiredOption(.outputPath)
    )
    assertParseError(
      [
        "--runtime-verification",
        "--window-title-contains",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .missingValue(.windowTitleSubstring)
    )
  }

  @Test(
    arguments: ["0", "-1", "nan", "inf", "3600.1", "not-a-number"]
  )
  func rejectsInvalidObservationDuration(_ duration: String) {
    assertParseError(
      [
        "--runtime-verification",
        "--window-title-contains",
        "Verification",
        "--observation-seconds",
        duration,
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .invalidObservationDuration
    )
  }

  @Test func remainsDisabledWithoutActivationFlag() throws {
    let parsed = try RuntimeVerificationArguments.parse([
      "LectureBoardAI",
      "--window-title-contains",
      "Verification",
      "--observation-seconds",
    ])

    #expect(parsed == nil)
  }

  @Test func rejectsDuplicateOptions() {
    assertParseError(
      [
        "--runtime-verification",
        "--window-title-contains",
        "First",
        "--window-title-contains",
        "Second",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .duplicateOption(.windowTitleSubstring)
    )
  }

  @Test func rejectsEmptyWindowTitleAndRelativeOutputPath() {
    assertParseError(
      [
        "--runtime-verification",
        "--window-title-contains",
        "  \n",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .invalidWindowTitleSubstring
    )
    assertParseError(
      [
        "--runtime-verification",
        "--window-title-contains",
        "Verification",
        "--observation-seconds",
        "10",
        "--output-path",
        "relative/result.json",
      ],
      equals: .invalidOutputPath
    )
  }

  private func assertParseError(
    _ arguments: [String],
    equals expectedError: RuntimeVerificationArgumentError,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    do {
      _ = try RuntimeVerificationArguments.parse(arguments)
      Issue.record("Expected argument parsing to fail", sourceLocation: sourceLocation)
    } catch let error as RuntimeVerificationArgumentError {
      #expect(error == expectedError, sourceLocation: sourceLocation)
    } catch {
      Issue.record("Unexpected error type: \(error)", sourceLocation: sourceLocation)
    }
  }
}
