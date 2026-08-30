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

    #expect(configuration.targetWindow == .titleSubstring("LectureBoard Runtime Verification"))
    #expect(configuration.observationDurationSeconds == 12.5)
    #expect(configuration.outputPath == "/tmp/lectureboard-runtime.json")
    #expect(configuration.requestsScreenRecordingPermission)
  }

  @Test func parsesMaximumWindowID() throws {
    let parsed = try RuntimeVerificationArguments.parse([
      "--runtime-verification",
      "--window-id",
      String(UInt32.max),
      "--observation-seconds",
      "1",
      "--output-path",
      "/tmp/result.json",
    ])

    #expect(try #require(parsed).targetWindow == .windowID(UInt32.max))
  }

  @Test func parsesLeadingZeroWindowIDAsDecimal() throws {
    let parsed = try RuntimeVerificationArguments.parse([
      "--runtime-verification",
      "--window-id",
      "00042",
      "--observation-seconds",
      "1",
      "--output-path",
      "/tmp/result.json",
    ])

    #expect(try #require(parsed).targetWindow == .windowID(42))
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
    assertParseError(
      [
        "--runtime-verification",
        "--window-id",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .missingValue(.windowID)
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

    assertParseError(
      [
        "--runtime-verification",
        "--window-id",
        "1",
        "--window-id",
        "2",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .duplicateOption(.windowID)
    )
  }

  @Test func requiresExactlyOneWindowSelectionMode() {
    assertParseError(
      [
        "--runtime-verification",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .missingWindowSelection
    )

    assertParseError(
      [
        "--runtime-verification",
        "--window-title-contains",
        "Verification",
        "--window-id",
        "42",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .conflictingWindowSelectionOptions
    )

    assertParseError(
      [
        "--runtime-verification",
        "--window-id",
        "42",
        "--window-title-contains",
        "Verification",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .conflictingWindowSelectionOptions
    )
  }

  @Test(
    arguments: [
      "0",
      "0000",
      "-1",
      "+1",
      "1.0",
      "1e2",
      "0x2A",
      " 1",
      "1 ",
      "１",
      "42\0",
      "4294967296",
      "not-a-number",
    ]
  )
  func rejectsInvalidWindowID(_ windowID: String) {
    assertParseError(
      [
        "--runtime-verification",
        "--window-id",
        windowID,
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .invalidWindowID
    )
  }

  @Test func rejectsUnknownLongOption() {
    assertParseError(
      [
        "--runtime-verification",
        "--window-id",
        "42",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
        "--unexpected-runtime-option",
      ],
      equals: .unknownOption("--unexpected-runtime-option")
    )

    assertParseError(
      [
        "--runtime-verification",
        "--unexpected-runtime-option",
        "--window-id",
        "42",
        "--observation-seconds",
        "10",
        "--output-path",
        "/tmp/result.json",
      ],
      equals: .unknownOption("--unexpected-runtime-option")
    )

    do {
      let parsed = try RuntimeVerificationArguments.parse([
        "LectureBoardAI",
        "--unexpected-runtime-option",
      ])
      #expect(parsed == nil)
    } catch {
      Issue.record("Runtime-only options must be ignored without activation: \(error)")
    }
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
