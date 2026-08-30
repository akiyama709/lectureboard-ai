public struct RGBContentCell: Equatable, Sendable {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8) {
    self.red = red
    self.green = green
    self.blue = blue
  }

  public func maximumChannelDifference(from other: RGBContentCell) -> UInt8 {
    let redDifference = abs(Int(red) - Int(other.red))
    let greenDifference = abs(Int(green) - Int(other.green))
    let blueDifference = abs(Int(blue) - Int(other.blue))
    return UInt8(max(redDifference, greenDifference, blueDifference))
  }
}

public struct ContentFingerprintComparison: Equatable, Sendable {
  public let maximumChannelDifferences: [UInt8]
  public let changedCellCount: Int
  public let changedCellRate: Double

  init(
    maximumChannelDifferences: [UInt8],
    changedCellCount: Int
  ) {
    self.maximumChannelDifferences = maximumChannelDifferences
    self.changedCellCount = changedCellCount
    self.changedCellRate =
      maximumChannelDifferences.isEmpty
      ? 0
      : Double(changedCellCount) / Double(maximumChannelDifferences.count)
  }
}

public struct ContentFingerprint: Equatable, Sendable {
  public let sampleColumns: Int
  public let sampleRows: Int
  public let cells: [RGBContentCell]

  public init(sampleColumns: Int, sampleRows: Int, cells: [RGBContentCell]) {
    self.sampleColumns = sampleColumns
    self.sampleRows = sampleRows
    self.cells = cells
  }

  public var isValid: Bool {
    guard sampleColumns > 0, sampleRows > 0 else { return false }
    let (expectedCellCount, overflow) = sampleColumns.multipliedReportingOverflow(by: sampleRows)
    return !overflow && cells.count == expectedCellCount
  }

  public func comparison(
    from other: ContentFingerprint,
    cellDifferenceThreshold: Double
  ) -> ContentFingerprintComparison? {
    guard isValid, other.isValid else { return nil }
    guard sampleColumns == other.sampleColumns, sampleRows == other.sampleRows else { return nil }

    let normalizedThreshold = normalizedUnitInterval(cellDifferenceThreshold)
    let channelDifferenceThreshold = normalizedThreshold * 255
    var maximumChannelDifferences: [UInt8] = []
    maximumChannelDifferences.reserveCapacity(cells.count)
    var changedCellCount = 0

    for (cell, otherCell) in zip(cells, other.cells) {
      let maximumDifference = cell.maximumChannelDifference(from: otherCell)
      maximumChannelDifferences.append(maximumDifference)
      if Double(maximumDifference) > channelDifferenceThreshold {
        changedCellCount += 1
      }
    }

    return ContentFingerprintComparison(
      maximumChannelDifferences: maximumChannelDifferences,
      changedCellCount: changedCellCount
    )
  }
}

public struct StableContentChangeDetectorConfiguration: Equatable, Sendable {
  public let cellDifferenceThreshold: Double
  public let minimumChangedCellRate: Double
  public let maximumCandidateChangedCellRate: Double
  public let requiredConsecutiveFrames: Int

  public init(
    cellDifferenceThreshold: Double = 0.08,
    minimumChangedCellRate: Double = 0.001,
    maximumCandidateChangedCellRate: Double = 0,
    requiredConsecutiveFrames: Int = 3
  ) {
    self.cellDifferenceThreshold = normalizedUnitInterval(cellDifferenceThreshold)
    self.minimumChangedCellRate = normalizedUnitInterval(minimumChangedCellRate)
    self.maximumCandidateChangedCellRate = normalizedUnitInterval(
      maximumCandidateChangedCellRate
    )
    self.requiredConsecutiveFrames = max(requiredConsecutiveFrames, 1)
  }
}

public enum StableContentChangeState: Equatable, Sendable {
  case invalid
  case collectingBaseline(consecutiveFrames: Int)
  case baselineEstablished
  case unchanged
  case contentChangePending(consecutiveFrames: Int)
  case contentChanged
}

public struct StableContentChangeObservation: Equatable, Sendable {
  public let state: StableContentChangeState
  public let comparisonFromBaseline: ContentFingerprintComparison?
  public let baselineFingerprint: ContentFingerprint?

  public init(
    state: StableContentChangeState,
    comparisonFromBaseline: ContentFingerprintComparison?,
    baselineFingerprint: ContentFingerprint?
  ) {
    self.state = state
    self.comparisonFromBaseline = comparisonFromBaseline
    self.baselineFingerprint = baselineFingerprint
  }
}

public struct StableContentChangeDetector: Sendable {
  public let configuration: StableContentChangeDetectorConfiguration

  private var baselineFingerprint: ContentFingerprint?
  private var candidateFingerprint: ContentFingerprint?
  private var candidateCount = 0

  public init(configuration: StableContentChangeDetectorConfiguration = .init()) {
    self.configuration = configuration
  }

  public mutating func reset() {
    baselineFingerprint = nil
    candidateFingerprint = nil
    candidateCount = 0
  }

  @discardableResult
  public mutating func rebase(to fingerprint: ContentFingerprint) -> Bool {
    guard fingerprint.isValid else { return false }
    baselineFingerprint = fingerprint
    clearCandidate()
    return true
  }

  public mutating func discardPendingChange() {
    clearCandidate()
  }

  public mutating func ingest(
    _ fingerprint: ContentFingerprint
  ) -> StableContentChangeObservation {
    guard fingerprint.isValid, hasExpectedDimensions(fingerprint) else {
      return observation(state: .invalid)
    }

    guard let baselineFingerprint else {
      return ingestBaselineCandidate(fingerprint)
    }

    guard
      let comparisonFromBaseline = fingerprint.comparison(
        from: baselineFingerprint,
        cellDifferenceThreshold: configuration.cellDifferenceThreshold
      )
    else {
      return observation(state: .invalid)
    }

    let differsFromBaseline =
      comparisonFromBaseline.changedCellCount > 0
      && comparisonFromBaseline.changedCellRate >= configuration.minimumChangedCellRate
    guard differsFromBaseline else {
      clearCandidate()
      return observation(
        state: .unchanged,
        comparisonFromBaseline: comparisonFromBaseline
      )
    }

    if candidateMatches(fingerprint) {
      candidateCount += 1
    } else {
      candidateFingerprint = fingerprint
      candidateCount = 1
    }

    guard candidateCount >= configuration.requiredConsecutiveFrames,
      let confirmedFingerprint = candidateFingerprint
    else {
      return observation(
        state: .contentChangePending(consecutiveFrames: candidateCount),
        comparisonFromBaseline: comparisonFromBaseline
      )
    }

    self.baselineFingerprint = confirmedFingerprint
    clearCandidate()
    return observation(
      state: .contentChanged,
      comparisonFromBaseline: comparisonFromBaseline
    )
  }

  private mutating func ingestBaselineCandidate(
    _ fingerprint: ContentFingerprint
  ) -> StableContentChangeObservation {
    if candidateMatches(fingerprint) {
      candidateCount += 1
    } else {
      candidateFingerprint = fingerprint
      candidateCount = 1
    }

    guard candidateCount >= configuration.requiredConsecutiveFrames,
      let confirmedFingerprint = candidateFingerprint
    else {
      return observation(state: .collectingBaseline(consecutiveFrames: candidateCount))
    }

    baselineFingerprint = confirmedFingerprint
    clearCandidate()
    return observation(state: .baselineEstablished)
  }

  private func hasExpectedDimensions(_ fingerprint: ContentFingerprint) -> Bool {
    let expectedFingerprint = baselineFingerprint ?? candidateFingerprint
    guard let expectedFingerprint else { return true }
    return fingerprint.sampleColumns == expectedFingerprint.sampleColumns
      && fingerprint.sampleRows == expectedFingerprint.sampleRows
  }

  private func candidateMatches(_ fingerprint: ContentFingerprint) -> Bool {
    guard let candidateFingerprint,
      let comparison = fingerprint.comparison(
        from: candidateFingerprint,
        cellDifferenceThreshold: configuration.cellDifferenceThreshold
      )
    else {
      return false
    }
    return comparison.changedCellRate <= configuration.maximumCandidateChangedCellRate
  }

  private mutating func clearCandidate() {
    candidateFingerprint = nil
    candidateCount = 0
  }

  private func observation(
    state: StableContentChangeState,
    comparisonFromBaseline: ContentFingerprintComparison? = nil
  ) -> StableContentChangeObservation {
    StableContentChangeObservation(
      state: state,
      comparisonFromBaseline: comparisonFromBaseline,
      baselineFingerprint: baselineFingerprint
    )
  }
}

private func normalizedUnitInterval(_ value: Double) -> Double {
  if value.isNaN || value <= 0 { return 0 }
  if value >= 1 { return 1 }
  return value
}
