import Foundation

public enum RuntimeVerificationWindowTarget: Equatable, Sendable {
  case titleSubstring(String)
  case windowID(UInt32)
}

public struct RuntimeVerificationConfiguration: Equatable, Sendable {
  public let targetWindow: RuntimeVerificationWindowTarget
  public let observationDurationSeconds: TimeInterval
  public let outputPath: String
  public let requestsScreenRecordingPermission: Bool

  public init(
    targetWindow: RuntimeVerificationWindowTarget,
    observationDurationSeconds: TimeInterval,
    outputPath: String,
    requestsScreenRecordingPermission: Bool
  ) {
    self.targetWindow = targetWindow
    self.observationDurationSeconds = observationDurationSeconds
    self.outputPath = outputPath
    self.requestsScreenRecordingPermission = requestsScreenRecordingPermission
  }
}

public enum RuntimeVerificationOption: String, Equatable, Sendable {
  case windowTitleSubstring = "--window-title-contains"
  case windowID = "--window-id"
  case observationDuration = "--observation-seconds"
  case outputPath = "--output-path"
}

public enum RuntimeVerificationArgumentError: Error, Equatable, Sendable {
  case missingValue(RuntimeVerificationOption)
  case missingRequiredOption(RuntimeVerificationOption)
  case duplicateOption(RuntimeVerificationOption)
  case missingWindowSelection
  case conflictingWindowSelectionOptions
  case unknownOption(String)
  case invalidWindowTitleSubstring
  case invalidWindowID
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
      if argument == activationFlag {
        index += 1
        continue
      }
      if argument == screenRecordingRequestFlag {
        requestsScreenRecordingPermission = true
        index += 1
        continue
      }

      guard let option = RuntimeVerificationOption(rawValue: argument) else {
        if argument.hasPrefix("--") {
          throw RuntimeVerificationArgumentError.unknownOption(argument)
        }
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

    let hasTitleSelection = values[.windowTitleSubstring] != nil
    let hasIDSelection = values[.windowID] != nil
    guard hasTitleSelection || hasIDSelection else {
      throw RuntimeVerificationArgumentError.missingWindowSelection
    }
    guard !(hasTitleSelection && hasIDSelection) else {
      throw RuntimeVerificationArgumentError.conflictingWindowSelectionOptions
    }

    let targetWindow: RuntimeVerificationWindowTarget
    if let titleValue = values[.windowTitleSubstring] {
      let title = titleValue.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !title.isEmpty, !title.contains("\0") else {
        throw RuntimeVerificationArgumentError.invalidWindowTitleSubstring
      }
      targetWindow = .titleSubstring(title)
    } else {
      let windowIDText = try requiredValue(for: .windowID, in: values)
      guard isUnsignedDecimal(windowIDText),
        let windowID = UInt32(windowIDText),
        windowID != 0
      else {
        throw RuntimeVerificationArgumentError.invalidWindowID
      }
      targetWindow = .windowID(windowID)
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
      targetWindow: targetWindow,
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

  private static func isUnsignedDecimal(_ value: String) -> Bool {
    !value.isEmpty
      && value.unicodeScalars.allSatisfy { scalar in
        scalar.value >= 48 && scalar.value <= 57
      }
  }
}
