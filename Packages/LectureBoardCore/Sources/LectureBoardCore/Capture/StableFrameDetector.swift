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
    sampleColumns > 0
      && sampleRows > 0
      && luminance.count == sampleColumns * sampleRows
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
  public var slideChangeThreshold: Double
  public var requiredConsecutiveFrames: Int

  public init(
    stableDifferenceThreshold: Double = 0.012,
    slideChangeThreshold: Double = 0.10,
    requiredConsecutiveFrames: Int = 3
  ) {
    let stableThreshold = min(max(stableDifferenceThreshold, 0), 1)
    let changeThreshold = min(max(slideChangeThreshold, 0), 1)
    self.stableDifferenceThreshold = stableThreshold
    self.slideChangeThreshold = max(stableThreshold, changeThreshold)
    self.requiredConsecutiveFrames = max(requiredConsecutiveFrames, 1)
  }
}

public enum FrameStability: Equatable, Sendable {
  case invalid
  case collecting(consecutiveFrames: Int)
  case unchanged
  case stable
  case transitioning
  case slideChanged
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
          $0 >= configuration.slideChangeThreshold
        } ?? false
      return StableFrameObservation(
        stability: isTransitioning
          ? .transitioning
          : .collecting(consecutiveFrames: candidateCount),
        differenceFromStableFrame: differenceFromStable,
        stableFrame: stableFrame
      )
    }

    let didChangeSlide =
      differenceFromStable.map {
        $0 >= configuration.slideChangeThreshold
      } ?? false
    stableFrame = frame
    candidateFrame = nil
    candidateCount = 0

    return StableFrameObservation(
      stability: didChangeSlide ? .slideChanged : .stable,
      differenceFromStableFrame: differenceFromStable,
      stableFrame: frame
    )
  }
}
