import Testing

@testable import LectureBoardCore

struct StableFrameDetectorTests {
  private let configuration = StableFrameDetectorConfiguration(
    stableDifferenceThreshold: 0.01,
    significantChangeThreshold: 0.20,
    requiredConsecutiveFrames: 3
  )

  @Test func confirmsInitialFrameOnlyAfterConsecutiveMatches() {
    var detector = StableFrameDetector(configuration: configuration)
    let frame = fingerprint(20)

    #expect(detector.ingest(frame).stability == .collecting(consecutiveFrames: 1))
    #expect(detector.ingest(frame).stability == .collecting(consecutiveFrames: 2))
    #expect(detector.ingest(frame).stability == .stable)
    #expect(detector.ingest(frame).stability == .unchanged)
  }

  @Test func keepsOneOpaqueTokenFromFirstCandidateObservationThroughConfirmation() throws {
    var detector = StableFrameDetector(configuration: configuration)
    let frame = fingerprint(20)

    let first = detector.ingest(frame)
    let firstToken = try #require(first.candidateToken)
    let second = detector.ingest(frame)
    let confirmed = detector.ingest(frame)

    #expect(first.stability == .collecting(consecutiveFrames: 1))
    #expect(second.stability == .collecting(consecutiveFrames: 2))
    #expect(second.candidateToken == firstToken)
    #expect(confirmed.stability == .stable)
    #expect(confirmed.candidateToken == firstToken)
    #expect(detector.ingest(frame).candidateToken == nil)
  }

  @Test func independentlyCapturedEvidenceConfirmsOnlyTheExactPendingCandidate() throws {
    var detector = StableFrameDetector(configuration: configuration)
    let frame = fingerprint(20)

    let first = detector.ingest(frame)
    let token = try #require(first.candidateToken)
    let secondResult = detector.confirmPendingFrame(frame, token: token)
    let second = try #require(secondResult)
    let confirmedResult = detector.confirmPendingFrame(frame, token: token)
    let confirmed = try #require(confirmedResult)
    let afterConfirmation = detector.confirmPendingFrame(frame, token: token)

    #expect(second.stability == .collecting(consecutiveFrames: 2))
    #expect(second.candidateToken == token)
    #expect(confirmed.stability == .stable)
    #expect(confirmed.candidateToken == token)
    #expect(afterConfirmation == nil)
  }

  @Test func staleConfirmationTokensCannotAdvanceAReplacementOrSurviveReset() throws {
    var detector = StableFrameDetector(configuration: configuration)
    let firstCandidate = fingerprint(20)
    let replacementCandidate = fingerprint(180)

    let staleToken = try #require(detector.ingest(firstCandidate).candidateToken)
    let replacement = detector.ingest(replacementCandidate)
    let replacementToken = try #require(replacement.candidateToken)

    #expect(staleToken != replacementToken)
    let staleResult = detector.confirmPendingFrame(firstCandidate, token: staleToken)
    #expect(staleResult == nil)
    let mismatchedFingerprintResult = detector.confirmPendingFrame(
      firstCandidate,
      token: replacementToken
    )
    #expect(mismatchedFingerprintResult == nil)
    let replacementSecondResult = detector.confirmPendingFrame(
      replacementCandidate,
      token: replacementToken
    )
    let replacementSecond = try #require(replacementSecondResult)
    #expect(replacementSecond.stability == .collecting(consecutiveFrames: 2))

    detector.reset()

    let afterReset = detector.confirmPendingFrame(
      replacementCandidate,
      token: replacementToken
    )
    #expect(afterReset == nil)
    let restarted = detector.ingest(replacementCandidate)
    #expect(restarted.stability == .collecting(consecutiveFrames: 1))
    #expect(restarted.candidateToken != replacementToken)
  }

  @Test func replacementCandidateReceivesANewToken() throws {
    var detector = StableFrameDetector(configuration: configuration)
    let baseline = fingerprint(10)
    let firstCandidate = fingerprint(80)
    let replacement = fingerprint(180)
    _ = detector.ingest(baseline)
    _ = detector.ingest(baseline)
    _ = detector.ingest(baseline)

    let firstToken = try #require(detector.ingest(firstCandidate).candidateToken)
    let replacementFirst = detector.ingest(replacement)
    let replacementToken = try #require(replacementFirst.candidateToken)
    let replacementSecond = detector.ingest(replacement)
    let confirmed = detector.ingest(replacement)

    #expect(firstToken != replacementToken)
    #expect(replacementFirst.stability == .transitioning)
    #expect(replacementSecond.candidateToken == replacementToken)
    #expect(confirmed.stability == .significantVisualChange)
    #expect(confirmed.candidateToken == replacementToken)
  }

  @Test func unchangedAndInvalidFramesClearCandidateTokens() throws {
    var unchangedDetector = StableFrameDetector(configuration: configuration)
    let baseline = fingerprint(10)
    let candidate = fingerprint(80)
    _ = unchangedDetector.ingest(baseline)
    _ = unchangedDetector.ingest(baseline)
    _ = unchangedDetector.ingest(baseline)

    let beforeUnchanged = try #require(unchangedDetector.ingest(candidate).candidateToken)
    #expect(unchangedDetector.ingest(baseline).candidateToken == nil)
    let afterUnchanged = try #require(unchangedDetector.ingest(candidate).candidateToken)
    #expect(afterUnchanged != beforeUnchanged)

    let malformed = FrameFingerprint(sampleColumns: 2, sampleRows: 2, luminance: [1, 2])
    let invalidObservation = unchangedDetector.ingest(malformed)
    #expect(invalidObservation.stability == .invalid)
    #expect(invalidObservation.candidateToken == nil)
    let afterInvalid = try #require(unchangedDetector.ingest(candidate).candidateToken)
    #expect(afterInvalid != afterUnchanged)
  }

  @Test func resetClearsTheCandidateTokenAndStartsANewCandidate() throws {
    var detector = StableFrameDetector(configuration: configuration)
    let frame = fingerprint(30)
    let beforeReset = try #require(detector.ingest(frame).candidateToken)

    detector.reset()

    let afterReset = detector.ingest(frame)
    #expect(afterReset.stability == .collecting(consecutiveFrames: 1))
    #expect(afterReset.candidateToken != nil)
    #expect(afterReset.candidateToken != beforeReset)
  }

  @Test func treatsSmallLuminanceNoiseAsTheSameStableFrame() {
    var detector = StableFrameDetector(configuration: configuration)
    let frame = fingerprint(100)
    _ = detector.ingest(frame)
    _ = detector.ingest(frame)
    _ = detector.ingest(frame)

    let observation = detector.ingest(
      FrameFingerprint(
        sampleColumns: 2,
        sampleRows: 2,
        luminance: [101, 99, 100, 101]
      )
    )

    #expect(observation.stability == .unchanged)
  }

  @Test func defaultConfigurationReportsMeasuredDifferenceAsASignificantVisualChange() {
    var detector = StableFrameDetector()
    let firstSlide = fingerprint(100)
    let secondSlide = fingerprint(107)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)

    #expect(detector.ingest(secondSlide).stability == .transitioning)
    #expect(detector.ingest(secondSlide).stability == .transitioning)
    let observation = detector.ingest(secondSlide)

    #expect(observation.differenceFromStableFrame! > 0.027)
    #expect(observation.stability == .significantVisualChange)
  }

  @Test func defaultConfigurationKeepsMeasuredIdleNoiseUnchanged() {
    var detector = StableFrameDetector()
    let stableFrame = fingerprint(columns: 32, rows: 18, luminance: 100)
    _ = detector.ingest(stableFrame)
    _ = detector.ingest(stableFrame)
    _ = detector.ingest(stableFrame)

    var noisyLuminance = stableFrame.luminance
    for index in noisyLuminance.indices.prefix(51) {
      noisyLuminance[index] += 1
    }
    let observation = detector.ingest(
      FrameFingerprint(sampleColumns: 32, sampleRows: 18, luminance: noisyLuminance)
    )

    #expect(observation.differenceFromStableFrame! < 0.00035)
    #expect(observation.stability == .unchanged)
  }

  @Test func waitsForANewStableFrameBeforeReportingASignificantVisualChange() {
    var detector = StableFrameDetector(configuration: configuration)
    let firstSlide = fingerprint(10)
    let secondSlide = fingerprint(240)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)

    #expect(detector.ingest(secondSlide).stability == .transitioning)
    #expect(detector.ingest(secondSlide).stability == .transitioning)
    #expect(detector.ingest(secondSlide).stability == .significantVisualChange)
    #expect(detector.ingest(secondSlide).stability == .unchanged)
  }

  @Test func doesNotConfirmChangingAnimationFrames() {
    var detector = StableFrameDetector(configuration: configuration)
    let firstSlide = fingerprint(0)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)

    #expect(detector.ingest(fingerprint(70)).stability == .transitioning)
    #expect(detector.ingest(fingerprint(130)).stability == .transitioning)
    #expect(detector.ingest(fingerprint(200)).stability == .transitioning)
    #expect(detector.ingest(fingerprint(200)).stability == .transitioning)
    #expect(detector.ingest(fingerprint(200)).stability == .significantVisualChange)
  }

  @Test func rejectsMalformedAndMismatchedFingerprints() {
    let malformed = FrameFingerprint(sampleColumns: 2, sampleRows: 2, luminance: [1, 2])
    let valid = fingerprint(0)
    let differentlySized = FrameFingerprint(sampleColumns: 1, sampleRows: 2, luminance: [0, 0])
    var detector = StableFrameDetector(configuration: configuration)

    #expect(malformed.isValid == false)
    #expect(malformed.normalizedDifference(from: valid) == 1)
    #expect(valid.normalizedDifference(from: differentlySized) == 1)
    #expect(detector.ingest(malformed).stability == .invalid)
  }

  @Test func rejectsOverflowingFingerprintDimensionsWithoutTrapping() {
    let overflowing = FrameFingerprint(
      sampleColumns: Int.max,
      sampleRows: 2,
      luminance: []
    )
    let valid = fingerprint(0)
    var detector = StableFrameDetector(configuration: configuration)

    #expect(overflowing.isValid == false)
    #expect(overflowing.normalizedDifference(from: valid) == 1)
    #expect(detector.ingest(overflowing).stability == .invalid)
  }

  @Test func normalizesInvalidConfigurationValues() {
    let bounded = StableFrameDetectorConfiguration(
      stableDifferenceThreshold: -1,
      significantChangeThreshold: 2,
      requiredConsecutiveFrames: 0
    )
    let ordered = StableFrameDetectorConfiguration(
      stableDifferenceThreshold: 0.4,
      significantChangeThreshold: 0.2
    )

    #expect(bounded.stableDifferenceThreshold == 0)
    #expect(bounded.significantChangeThreshold == 1)
    #expect(bounded.requiredConsecutiveFrames == 1)
    #expect(ordered.significantChangeThreshold == ordered.stableDifferenceThreshold)
  }

  @Test func normalizesNonFiniteConfigurationValuesAndStillConfirmsStability() {
    let configuration = StableFrameDetectorConfiguration(
      stableDifferenceThreshold: .nan,
      significantChangeThreshold: .infinity,
      requiredConsecutiveFrames: 2
    )
    var detector = StableFrameDetector(configuration: configuration)
    let frame = fingerprint(20)

    #expect(configuration.stableDifferenceThreshold == 0)
    #expect(configuration.significantChangeThreshold == 1)
    #expect(detector.ingest(frame).stability == .collecting(consecutiveFrames: 1))
    #expect(detector.ingest(frame).stability == .stable)
  }

  @Test func resetRequiresANewStableSequence() {
    var detector = StableFrameDetector(configuration: configuration)
    let frame = fingerprint(30)
    _ = detector.ingest(frame)
    _ = detector.ingest(frame)
    #expect(detector.ingest(frame).stability == .stable)

    detector.reset()

    #expect(detector.ingest(frame).stability == .collecting(consecutiveFrames: 1))
    #expect(detector.ingest(frame).stableFrame == nil)
  }

  private func fingerprint(_ luminance: UInt8) -> FrameFingerprint {
    fingerprint(columns: 2, rows: 2, luminance: luminance)
  }

  private func fingerprint(columns: Int, rows: Int, luminance: UInt8) -> FrameFingerprint {
    FrameFingerprint(
      sampleColumns: columns,
      sampleRows: rows,
      luminance: Array(repeating: luminance, count: columns * rows)
    )
  }
}
