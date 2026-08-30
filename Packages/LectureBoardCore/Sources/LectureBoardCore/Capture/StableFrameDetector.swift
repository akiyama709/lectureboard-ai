import Foundation

public struct FrameFingerprint: Equatable, Sendable {
  public let sampleColumns: Int
  public let sampleRows: Int
  public let luminance: [UInt8]

  public init(sampleColumns: Int, sampleRows: Int, luminance: [UInt8]) {
    self.sampleColumns = sampleColumns
    self.sampleRows = sampleRows
    self.luminance = luminance
  }

  public var isValid: Bool {
    guard sampleColumns > 0, sampleRows > 0 else { return false }
    let (expectedSampleCount, overflow) = sampleColumns.multipliedReportingOverflow(by: sampleRows)
    return !overflow && luminance.count == expectedSampleCount
  }

  public func normalizedDifference(from other: FrameFingerprint) -> Double {
    guard isValid, other.isValid else { return 1 }
    guard sampleColumns == other.sampleColumns, sampleRows == other.sampleRows else { return 1 }

    let totalDifference = zip(luminance, other.luminance).reduce(0) { partialResult, pair in
      partialResult + abs(Int(pair.0) - Int(pair.1))
    }
    return Double(totalDifference) / Double(luminance.count * 255)
  }
}

public struct StableFrameDetectorConfiguration: Equatable, Sendable {
  public var stableDifferenceThreshold: Double
  public var significantChangeThreshold: Double
  public var requiredConsecutiveFrames: Int

  public init(
    stableDifferenceThreshold: Double = 0.012,
    significantChangeThreshold: Double = 0.02,
    requiredConsecutiveFrames: Int = 3
  ) {
    let stableThreshold = Self.normalizedUnitInterval(stableDifferenceThreshold)
    let changeThreshold = Self.normalizedUnitInterval(significantChangeThreshold)
    self.stableDifferenceThreshold = stableThreshold
    self.significantChangeThreshold = max(stableThreshold, changeThreshold)
    self.requiredConsecutiveFrames = max(requiredConsecutiveFrames, 1)
  }

  private static func normalizedUnitInterval(_ value: Double) -> Double {
    if value.isNaN || value <= 0 { return 0 }
    if value >= 1 { return 1 }
    return value
  }
}

public enum FrameStability: Equatable, Sendable {
  case invalid
  case collecting(consecutiveFrames: Int)
  case unchanged
  case stable
  case transitioning
  case significantVisualChange
}

public struct StableFrameObservation: Equatable, Sendable {
  public let stability: FrameStability
  public let differenceFromStableFrame: Double?
  public let stableFrame: FrameFingerprint?

  public init(
    stability: FrameStability,
    differenceFromStableFrame: Double?,
    stableFrame: FrameFingerprint?
  ) {
    self.stability = stability
    self.differenceFromStableFrame = differenceFromStableFrame
    self.stableFrame = stableFrame
  }
}

public struct StableFrameDetector: Sendable {
  public let configuration: StableFrameDetectorConfiguration

  private var stableFrame: FrameFingerprint?
  private var candidateFrame: FrameFingerprint?
  private var candidateCount = 0

  public init(configuration: StableFrameDetectorConfiguration = .init()) {
    self.configuration = configuration
  }

  public mutating func reset() {
    stableFrame = nil
    candidateFrame = nil
    candidateCount = 0
  }

  public mutating func ingest(_ frame: FrameFingerprint) -> StableFrameObservation {
    guard frame.isValid else {
      return StableFrameObservation(
        stability: .invalid,
        differenceFromStableFrame: nil,
        stableFrame: stableFrame
      )
    }

    let differenceFromStable = stableFrame.map { frame.normalizedDifference(from: $0) }
    if let differenceFromStable,
      differenceFromStable <= configuration.stableDifferenceThreshold
    {
      candidateFrame = nil
      candidateCount = 0
      return StableFrameObservation(
        stability: .unchanged,
        differenceFromStableFrame: differenceFromStable,
        stableFrame: stableFrame
      )
    }

    if let candidateFrame,
      frame.normalizedDifference(from: candidateFrame)
        <= configuration.stableDifferenceThreshold
    {
      candidateCount += 1
    } else {
      candidateFrame = frame
      candidateCount = 1
    }

    guard candidateCount >= configuration.requiredConsecutiveFrames else {
      let isTransitioning =
        differenceFromStable.map {
          $0 >= configuration.significantChangeThreshold
        } ?? false
      return StableFrameObservation(
        stability: isTransitioning
          ? .transitioning
          : .collecting(consecutiveFrames: candidateCount),
        differenceFromStableFrame: differenceFromStable,
        stableFrame: stableFrame
      )
    }

    let isSignificantChange =
      differenceFromStable.map {
        $0 >= configuration.significantChangeThreshold
      } ?? false
    stableFrame = frame
    candidateFrame = nil
    candidateCount = 0

    return StableFrameObservation(
      stability: isSignificantChange ? .significantVisualChange : .stable,
      differenceFromStableFrame: differenceFromStable,
      stableFrame: frame
    )
  }
}
