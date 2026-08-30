import Foundation

public struct RuntimeVerificationConfiguration: Equatable, Sendable {
  public let targetWindowTitleSubstring: String
  public let observationDurationSeconds: TimeInterval
  public let outputPath: String
  public let requestsScreenRecordingPermission: Bool

  public init(
    targetWindowTitleSubstring: String,
    observationDurationSeconds: TimeInterval,
    outputPath: String,
    requestsScreenRecordingPermission: Bool
  ) {
    self.targetWindowTitleSubstring = targetWindowTitleSubstring
    self.observationDurationSeconds = observationDurationSeconds
    self.outputPath = outputPath
    self.requestsScreenRecordingPermission = requestsScreenRecordingPermission
  }
}

public enum RuntimeVerificationOption: String, Equatable, Sendable {
  case windowTitleSubstring = "--window-title-contains"
  case observationDuration = "--observation-seconds"
  case outputPath = "--output-path"
}

public enum RuntimeVerificationArgumentError: Error, Equatable, Sendable {
  case missingValue(RuntimeVerificationOption)
  case missingRequiredOption(RuntimeVerificationOption)
  case duplicateOption(RuntimeVerificationOption)
  case invalidWindowTitleSubstring
  case invalidObservationDuration
  case invalidOutputPath
}

public enum RuntimeVerificationArguments {
  public static let activationFlag = "--runtime-verification"
  public static let screenRecordingRequestFlag = "--request-screen-recording"
  public static let maximumObservationDurationSeconds: TimeInterval = 3_600

  public static func parse(
    _ arguments: [String]
  ) throws -> RuntimeVerificationConfiguration? {
    guard arguments.contains(activationFlag) else { return nil }

    var values: [RuntimeVerificationOption: String] = [:]
    var requestsScreenRecordingPermission = false
    var index = arguments.startIndex

    while index < arguments.endIndex {
      let argument = arguments[index]
      if argument == screenRecordingRequestFlag {
        requestsScreenRecordingPermission = true
        index += 1
        continue
      }

      guard let option = RuntimeVerificationOption(rawValue: argument) else {
        index += 1
        continue
      }
      guard values[option] == nil else {
        throw RuntimeVerificationArgumentError.duplicateOption(option)
      }

      let valueIndex = arguments.index(after: index)
      guard valueIndex < arguments.endIndex,
        !arguments[valueIndex].hasPrefix("--")
      else {
        throw RuntimeVerificationArgumentError.missingValue(option)
      }
      values[option] = arguments[valueIndex]
      index = arguments.index(after: valueIndex)
    }

    let title = try requiredValue(for: .windowTitleSubstring, in: values)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty, !title.contains("\0") else {
      throw RuntimeVerificationArgumentError.invalidWindowTitleSubstring
    }

    let durationText = try requiredValue(for: .observationDuration, in: values)
    guard let duration = TimeInterval(durationText),
      duration.isFinite,
      duration > 0,
      duration <= maximumObservationDurationSeconds
    else {
      throw RuntimeVerificationArgumentError.invalidObservationDuration
    }

    let outputPath = try requiredValue(for: .outputPath, in: values)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !outputPath.isEmpty,
      !outputPath.contains("\0"),
      NSString(string: outputPath).isAbsolutePath
    else {
      throw RuntimeVerificationArgumentError.invalidOutputPath
    }

    return RuntimeVerificationConfiguration(
      targetWindowTitleSubstring: title,
      observationDurationSeconds: duration,
      outputPath: outputPath,
      requestsScreenRecordingPermission: requestsScreenRecordingPermission
    )
  }

  private static func requiredValue(
    for option: RuntimeVerificationOption,
    in values: [RuntimeVerificationOption: String]
  ) throws -> String {
    guard let value = values[option] else {
      throw RuntimeVerificationArgumentError.missingRequiredOption(option)
    }
    return value
  }
}
