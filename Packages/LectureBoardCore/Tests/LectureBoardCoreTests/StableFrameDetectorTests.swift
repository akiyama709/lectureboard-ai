import Testing

@testable import LectureBoardCore

struct StableFrameDetectorTests {
  private let configuration = StableFrameDetectorConfiguration(
    stableDifferenceThreshold: 0.01,
    slideChangeThreshold: 0.20,
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

  @Test func waitsForANewStableFrameBeforeReportingSlideChange() {
    var detector = StableFrameDetector(configuration: configuration)
    let firstSlide = fingerprint(10)
    let secondSlide = fingerprint(240)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)
    _ = detector.ingest(firstSlide)

    #expect(detector.ingest(secondSlide).stability == .transitioning)
    #expect(detector.ingest(secondSlide).stability == .transitioning)
    #expect(detector.ingest(secondSlide).stability == .slideChanged)
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
    #expect(detector.ingest(fingerprint(200)).stability == .slideChanged)
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

  @Test func normalizesInvalidConfigurationValues() {
    let bounded = StableFrameDetectorConfiguration(
      stableDifferenceThreshold: -1,
      slideChangeThreshold: 2,
      requiredConsecutiveFrames: 0
    )
    let ordered = StableFrameDetectorConfiguration(
      stableDifferenceThreshold: 0.4,
      slideChangeThreshold: 0.2
    )

    #expect(bounded.stableDifferenceThreshold == 0)
    #expect(bounded.slideChangeThreshold == 1)
    #expect(bounded.requiredConsecutiveFrames == 1)
    #expect(ordered.slideChangeThreshold == ordered.stableDifferenceThreshold)
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
    FrameFingerprint(
      sampleColumns: 2,
      sampleRows: 2,
      luminance: Array(repeating: luminance, count: 4)
    )
  }
}
