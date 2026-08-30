import Foundation

/// A validated, in-memory PowerPoint slide identity sample.
///
/// This type intentionally does not conform to `Codable`: presentation tokens and slide
/// identifiers are runtime-only correlation material and must not enter verification reports.
public struct SlideIdentitySample: Equatable, Sendable {
  public let presentationSessionToken: String
  public let slideID: Int
  public let slideIndex: Int

  public init?(
    presentationSessionToken: String,
    slideID: Int,
    slideIndex: Int
  ) {
    guard !presentationSessionToken.isEmpty, slideID > 0, slideIndex > 0 else {
      return nil
    }

    self.presentationSessionToken = presentationSessionToken
    self.slideID = slideID
    self.slideIndex = slideIndex
  }
}

public enum SlideIdentitySignal: Equatable, Sendable {
  case unavailable
  case available(SlideIdentitySample)
}

public enum SlideIdentityEvent: Equatable, Sendable {
  case none
  case baselineEstablished
  case metadataUpdated
  case slideChanged
  case continuityBroken
}

public enum SlideIdentityState: String, Codable, Equatable, Sendable {
  case unavailable
  case establishing
  case identified
  case interrupted
}

/// Confirms independent PowerPoint slide identity only after two consecutive matching samples.
///
/// A presentation-session change or an unavailable signal invalidates continuity. The first
/// subsequently confirmed slide becomes a new baseline and is never counted as a slide change.
public struct SlideIdentityTracker: Equatable, Sendable {
  public private(set) var state: SlideIdentityState = .unavailable
  public private(set) var sampleCount = 0
  public private(set) var continuityBreakCount = 0
  public private(set) var slideChangeCount = 0

  private var confirmedSample: SlideIdentitySample?
  private var candidateSample: SlideIdentitySample?

  public init() {}

  @discardableResult
  public mutating func ingest(_ signal: SlideIdentitySignal) -> SlideIdentityEvent {
    sampleCount = Self.incrementingWithoutOverflow(sampleCount)

    switch signal {
    case .unavailable:
      return interruptContinuity()
    case .available(let sample):
      return ingestAvailable(sample)
    }
  }

  public mutating func reset() {
    self = Self()
  }

  private mutating func ingestAvailable(_ sample: SlideIdentitySample) -> SlideIdentityEvent {
    if let confirmedSample {
      guard sample.presentationSessionToken == confirmedSample.presentationSessionToken else {
        breakContinuityAndBeginBaseline(with: sample)
        return .continuityBroken
      }

      if sample.slideID == confirmedSample.slideID {
        let slideIndexChanged = sample.slideIndex != confirmedSample.slideIndex
        self.confirmedSample = sample
        candidateSample = nil
        state = .identified
        return slideIndexChanged ? .metadataUpdated : .none
      }

      if candidateSample?.matchesIdentity(of: sample) == true {
        self.confirmedSample = sample
        candidateSample = nil
        state = .identified
        slideChangeCount = Self.incrementingWithoutOverflow(slideChangeCount)
        return .slideChanged
      }

      candidateSample = sample
      state = .establishing
      return .none
    }

    if let candidateSample {
      if candidateSample.matchesIdentity(of: sample) {
        confirmedSample = sample
        self.candidateSample = nil
        state = .identified
        return .baselineEstablished
      }

      if candidateSample.presentationSessionToken != sample.presentationSessionToken {
        continuityBreakCount = Self.incrementingWithoutOverflow(continuityBreakCount)
        self.candidateSample = sample
        state = .establishing
        return .continuityBroken
      }
    }

    candidateSample = sample
    state = .establishing
    return .none
  }

  private mutating func interruptContinuity() -> SlideIdentityEvent {
    let hadContinuity = state == .establishing || state == .identified
    confirmedSample = nil
    candidateSample = nil

    if hadContinuity {
      continuityBreakCount = Self.incrementingWithoutOverflow(continuityBreakCount)
      state = .interrupted
      return .continuityBroken
    }

    if state != .interrupted {
      state = .unavailable
    }
    return .none
  }

  private mutating func breakContinuityAndBeginBaseline(with sample: SlideIdentitySample) {
    continuityBreakCount = Self.incrementingWithoutOverflow(continuityBreakCount)
    confirmedSample = nil
    candidateSample = sample
    state = .establishing
  }

  private static func incrementingWithoutOverflow(_ value: Int) -> Int {
    value == .max ? .max : value + 1
  }
}

extension SlideIdentitySample {
  fileprivate func matchesIdentity(of other: Self) -> Bool {
    presentationSessionToken == other.presentationSessionToken && slideID == other.slideID
  }
}
