import Testing

@testable import LectureBoardCore

struct StableContentChangeDetectorTests {
  private let configuration = StableContentChangeDetectorConfiguration(
    cellDifferenceThreshold: 0.05,
    minimumChangedCellRate: 0.005,
    maximumCandidateChangedCellRate: 0,
    requiredConsecutiveFrames: 2
  )

  @Test func computesMaximumChannelDifferencesAndChangedCellRate() throws {
    let first = ContentFingerprint(
      sampleColumns: 2,
      sampleRows: 1,
      cells: [
        RGBContentCell(red: 10, green: 100, blue: 200),
        RGBContentCell(red: 50, green: 50, blue: 50),
      ]
    )
    let second = ContentFingerprint(
      sampleColumns: 2,
      sampleRows: 1,
      cells: [
        RGBContentCell(red: 15, green: 80, blue: 255),
        RGBContentCell(red: 55, green: 50, blue: 45),
      ]
    )

    let comparison = try #require(
      second.comparison(from: first, cellDifferenceThreshold: 0.05)
    )

    #expect(comparison.maximumChannelDifferences == [55, 5])
    #expect(comparison.changedCellCount == 1)
    #expect(comparison.changedCellRate == 0.5)
  }

  @Test func establishesInitialBaselineOnlyAfterConsecutiveMatches() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)

    #expect(detector.ingest(baseline).state == .collectingBaseline(consecutiveFrames: 1))
    let established = detector.ingest(baseline)

    #expect(established.state == .baselineEstablished)
    #expect(established.baselineFingerprint == baseline)
    #expect(detector.ingest(baseline).state == .unchanged)
  }

  @Test func confirmsSparsePersistentContentChangeOnlyOnce() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)
    let changed = changingCells(in: baseline, indices: [42])
    establish(baseline, in: &detector)

    #expect(detector.ingest(changed).state == .contentChangePending(consecutiveFrames: 1))
    let confirmed = detector.ingest(changed)

    #expect(confirmed.state == .contentChanged)
    #expect(confirmed.comparisonFromBaseline?.changedCellCount == 1)
    #expect(confirmed.comparisonFromBaseline?.changedCellRate == 0.01)
    #expect(confirmed.baselineFingerprint == changed)
    #expect(detector.ingest(changed).state == .unchanged)
  }

  @Test func defaultConfigurationKeepsSmallVisualStatePendingForFirstTwoDeliveries() {
    let productionConfiguration = StableContentChangeDetectorConfiguration()
    #expect(productionConfiguration.cellDifferenceThreshold == 0.08)
    #expect(productionConfiguration.minimumChangedCellRate == 0.001)
    #expect(productionConfiguration.maximumCandidateChangedCellRate == 0)
    #expect(productionConfiguration.requiredConsecutiveFrames == 3)

    var detector = StableContentChangeDetector()
    let baseline = fingerprint(columns: 160, rows: 90)
    let changed = changingCells(in: baseline, indices: Array(0..<15))
    let acceptedBaseline = detector.rebase(to: baseline)
    #expect(acceptedBaseline)

    let firstDelivery = detector.ingest(changed)
    let secondDelivery = detector.ingest(changed)

    #expect(firstDelivery.state == .contentChangePending(consecutiveFrames: 1))
    #expect(secondDelivery.state == .contentChangePending(consecutiveFrames: 2))
    #expect(firstDelivery.comparisonFromBaseline?.changedCellCount == 15)
    #expect(
      firstDelivery.comparisonFromBaseline?.changedCellRate
        == Double(15) / Double(160 * 90)
    )
    #expect(firstDelivery.baselineFingerprint == baseline)
    #expect(secondDelivery.baselineFingerprint == baseline)
  }

  @Test func defaultConfigurationResetsCandidateAndConfirmsOnlyLaterPersistentState() {
    var detector = StableContentChangeDetector()
    let baseline = fingerprint(columns: 160, rows: 90)
    let firstVisualState = changingCells(in: baseline, indices: Array(0..<15))
    let laterVisualState = changingCells(in: baseline, indices: Array(15..<30))
    let acceptedBaseline = detector.rebase(to: baseline)
    #expect(acceptedBaseline)

    let observations = [
      detector.ingest(firstVisualState),
      detector.ingest(firstVisualState),
      detector.ingest(laterVisualState),
      detector.ingest(laterVisualState),
      detector.ingest(laterVisualState),
      detector.ingest(laterVisualState),
    ]

    #expect(observations[0].state == .contentChangePending(consecutiveFrames: 1))
    #expect(observations[1].state == .contentChangePending(consecutiveFrames: 2))
    #expect(observations[2].state == .contentChangePending(consecutiveFrames: 1))
    #expect(observations[3].state == .contentChangePending(consecutiveFrames: 2))
    #expect(observations[4].state == .contentChanged)
    #expect(observations[4].baselineFingerprint == laterVisualState)
    #expect(observations[5].state == .unchanged)
    #expect(observations.filter { $0.state == .contentChanged }.count == 1)
  }

  @Test func defaultConfigurationConfirmsEraseBackToBaselineOnThirdDelivery() {
    var detector = StableContentChangeDetector()
    let baseline = fingerprint(columns: 160, rows: 90)
    let inked = changingCells(in: baseline, indices: Array(30..<45))
    let acceptedBaseline = detector.rebase(to: baseline)
    #expect(acceptedBaseline)
    #expect(detector.ingest(inked).state == .contentChangePending(consecutiveFrames: 1))
    #expect(detector.ingest(inked).state == .contentChangePending(consecutiveFrames: 2))
    #expect(detector.ingest(inked).state == .contentChanged)

    let firstEraseDelivery = detector.ingest(baseline)
    let secondEraseDelivery = detector.ingest(baseline)
    let thirdEraseDelivery = detector.ingest(baseline)

    #expect(firstEraseDelivery.state == .contentChangePending(consecutiveFrames: 1))
    #expect(secondEraseDelivery.state == .contentChangePending(consecutiveFrames: 2))
    #expect(firstEraseDelivery.baselineFingerprint == inked)
    #expect(secondEraseDelivery.baselineFingerprint == inked)
    #expect(thirdEraseDelivery.state == .contentChanged)
    #expect(thirdEraseDelivery.comparisonFromBaseline?.changedCellCount == 15)
    #expect(thirdEraseDelivery.baselineFingerprint == baseline)
    #expect(detector.ingest(baseline).state == .unchanged)
  }

  @Test func confirmsPersistentErasureBackToOriginalBaseline() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)
    let inked = changingCells(in: baseline, indices: [10, 11])
    establish(baseline, in: &detector)
    _ = detector.ingest(inked)
    #expect(detector.ingest(inked).state == .contentChanged)

    #expect(detector.ingest(baseline).state == .contentChangePending(consecutiveFrames: 1))
    let erased = detector.ingest(baseline)

    #expect(erased.state == .contentChanged)
    #expect(erased.comparisonFromBaseline?.changedCellCount == 2)
    #expect(erased.baselineFingerprint == baseline)
    #expect(detector.ingest(baseline).state == .unchanged)
  }

  @Test func doesNotConfirmSingleFrameNoise() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)
    let noise = changingCells(in: baseline, indices: [5])
    establish(baseline, in: &detector)

    #expect(detector.ingest(noise).state == .contentChangePending(consecutiveFrames: 1))
    #expect(detector.ingest(baseline).state == .unchanged)
    #expect(detector.ingest(noise).state == .contentChangePending(consecutiveFrames: 1))
    #expect(detector.ingest(baseline).state == .unchanged)
  }

  @Test func doesNotConfirmAnimationWhoseChangedCellMoves() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)
    establish(baseline, in: &detector)

    for index in [1, 2, 3, 4] {
      let animationFrame = changingCells(in: baseline, indices: [index])
      #expect(
        detector.ingest(animationFrame).state
          == .contentChangePending(consecutiveFrames: 1)
      )
    }

    #expect(detector.ingest(baseline).state == .unchanged)
  }

  @Test func rejectsInvalidAndMismatchedFingerprintsWithoutChangingState() {
    let malformed = ContentFingerprint(sampleColumns: 2, sampleRows: 2, cells: [])
    let overflowing = ContentFingerprint(sampleColumns: Int.max, sampleRows: 2, cells: [])
    let baseline = fingerprint(columns: 2, rows: 2)
    let mismatched = fingerprint(columns: 1, rows: 4)
    var detector = StableContentChangeDetector(configuration: configuration)

    #expect(malformed.isValid == false)
    #expect(overflowing.isValid == false)
    #expect(malformed.comparison(from: baseline, cellDifferenceThreshold: 0.1) == nil)
    #expect(baseline.comparison(from: mismatched, cellDifferenceThreshold: 0.1) == nil)
    #expect(detector.ingest(malformed).state == .invalid)
    establish(baseline, in: &detector)

    let invalidObservation = detector.ingest(mismatched)
    #expect(invalidObservation.state == .invalid)
    #expect(invalidObservation.baselineFingerprint == baseline)
    #expect(detector.ingest(baseline).state == .unchanged)
  }

  @Test func normalizesConfigurationBounds() {
    let bounded = StableContentChangeDetectorConfiguration(
      cellDifferenceThreshold: -1,
      minimumChangedCellRate: 2,
      maximumCandidateChangedCellRate: .nan,
      requiredConsecutiveFrames: 0
    )
    let infinities = StableContentChangeDetectorConfiguration(
      cellDifferenceThreshold: .infinity,
      minimumChangedCellRate: -.infinity,
      maximumCandidateChangedCellRate: .infinity
    )

    #expect(bounded.cellDifferenceThreshold == 0)
    #expect(bounded.minimumChangedCellRate == 1)
    #expect(bounded.maximumCandidateChangedCellRate == 0)
    #expect(bounded.requiredConsecutiveFrames == 1)
    #expect(infinities.cellDifferenceThreshold == 1)
    #expect(infinities.minimumChangedCellRate == 0)
    #expect(infinities.maximumCandidateChangedCellRate == 1)
  }

  @Test func resetRequiresANewBaselineSequence() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)
    establish(baseline, in: &detector)

    detector.reset()
    let observation = detector.ingest(baseline)

    #expect(observation.state == .collectingBaseline(consecutiveFrames: 1))
    #expect(observation.baselineFingerprint == nil)
  }

  @Test func rebaseEstablishesAValidBaselineImmediatelyAndRejectsInvalidInput() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)
    let invalid = ContentFingerprint(sampleColumns: 2, sampleRows: 2, cells: [])

    let acceptedBaseline = detector.rebase(to: baseline)
    #expect(acceptedBaseline)
    #expect(detector.ingest(baseline).state == .unchanged)
    let acceptedInvalid = detector.rebase(to: invalid)
    #expect(acceptedInvalid == false)
    #expect(detector.ingest(baseline).state == .unchanged)
  }

  @Test func discardingPendingChangeRequiresANewConsecutiveSequence() {
    var detector = StableContentChangeDetector(configuration: configuration)
    let baseline = fingerprint(columns: 10, rows: 10)
    let changed = changingCells(in: baseline, indices: [42])
    let acceptedBaseline = detector.rebase(to: baseline)
    #expect(acceptedBaseline)

    #expect(detector.ingest(changed).state == .contentChangePending(consecutiveFrames: 1))
    detector.discardPendingChange()
    #expect(detector.ingest(changed).state == .contentChangePending(consecutiveFrames: 1))
    #expect(detector.ingest(changed).state == .contentChanged)
  }

  @Test func denseRGBFingerprintDetectsChangeMissedByCoarseCenterSamples() {
    let columns = 64
    let rows = 36
    let baseline = fingerprint(columns: columns, rows: rows)
    let changedIndices = (0..<12).map { row in (row * 2) * columns + row * 2 }
    let changed = changingCells(in: baseline, indices: changedIndices)

    let coarseBaseline = coarseCenterFingerprint(from: baseline)
    let coarseChanged = coarseCenterFingerprint(from: changed)
    #expect(coarseBaseline.sampleColumns == 32)
    #expect(coarseBaseline.sampleRows == 18)
    #expect(coarseChanged.normalizedDifference(from: coarseBaseline) == 0)

    let denseConfiguration = StableContentChangeDetectorConfiguration(
      cellDifferenceThreshold: 0.05,
      minimumChangedCellRate: 0.004,
      maximumCandidateChangedCellRate: 0,
      requiredConsecutiveFrames: 2
    )
    var detector = StableContentChangeDetector(configuration: denseConfiguration)
    establish(baseline, in: &detector)

    #expect(detector.ingest(changed).state == .contentChangePending(consecutiveFrames: 1))
    let observation = detector.ingest(changed)

    #expect(observation.state == .contentChanged)
    #expect(observation.comparisonFromBaseline?.changedCellCount == changedIndices.count)
  }

  private func fingerprint(columns: Int, rows: Int) -> ContentFingerprint {
    ContentFingerprint(
      sampleColumns: columns,
      sampleRows: rows,
      cells: Array(
        repeating: RGBContentCell(red: 255, green: 255, blue: 255),
        count: columns * rows
      )
    )
  }

  private func changingCells(
    in fingerprint: ContentFingerprint,
    indices: [Int]
  ) -> ContentFingerprint {
    var cells = fingerprint.cells
    for index in indices {
      cells[index] = RGBContentCell(red: 180, green: 20, blue: 20)
    }
    return ContentFingerprint(
      sampleColumns: fingerprint.sampleColumns,
      sampleRows: fingerprint.sampleRows,
      cells: cells
    )
  }

  private func establish(
    _ fingerprint: ContentFingerprint,
    in detector: inout StableContentChangeDetector
  ) {
    #expect(detector.ingest(fingerprint).state == .collectingBaseline(consecutiveFrames: 1))
    #expect(detector.ingest(fingerprint).state == .baselineEstablished)
  }

  private func coarseCenterFingerprint(
    from fingerprint: ContentFingerprint
  ) -> FrameFingerprint {
    var luminance: [UInt8] = []
    luminance.reserveCapacity(32 * 18)
    for row in 0..<18 {
      for column in 0..<32 {
        let denseIndex = (row * 2 + 1) * fingerprint.sampleColumns + column * 2 + 1
        let cell = fingerprint.cells[denseIndex]
        luminance.append(cell.red)
      }
    }
    return FrameFingerprint(sampleColumns: 32, sampleRows: 18, luminance: luminance)
  }
}
