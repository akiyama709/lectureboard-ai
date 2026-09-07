import Foundation

/// Promotes one stable, complete declarative unit from a stream of partial speech hypotheses.
///
/// The ordinary path never publishes the newest hypothesis by itself. The same text must survive
/// in two consecutive revisions of one provider-owned segment, and a sentence boundary must
/// already be present. A caller may separately invoke ``commitAfterPause(_:)`` after a bounded
/// no-update interval; that path is limited to an unchanged, metadata-valid Japanese partial with
/// an explicit importance cue and a conservative declarative ending. Because Apple partial
/// confidence can be unavailable, the pause path derives only the minimum public confidence from
/// the measured stability; the contextual board engine remains responsible for grounding,
/// importance, and the final public-state decision.
public struct StablePartialTranscriptCommitter: Sendable {
  private var previousPartial: TranscriptSegment?
  private var committedSegmentID: UUID?

  public init() {}

  public mutating func observe(_ segment: TranscriptSegment) -> TranscriptSegment? {
    guard !segment.isFinal else {
      reset()
      return nil
    }

    defer { previousPartial = segment }
    guard committedSegmentID != segment.id else { return nil }
    guard let previousPartial else { return nil }
    guard previousPartial.id == segment.id,
      previousPartial.language == segment.language,
      isReliable(previousPartial),
      isReliable(segment),
      segment.endTime >= previousPartial.endTime
    else {
      return nil
    }

    let stablePrefix = commonPrefix(previousPartial.text, segment.text)
    guard let unit = firstCompleteDeclarativeUnit(in: stablePrefix), isSubstantive(unit) else {
      return nil
    }

    committedSegmentID = segment.id
    return TranscriptSegment(
      id: segment.id,
      text: unit,
      startTime: segment.startTime,
      endTime: segment.endTime,
      language: segment.language,
      confidence: min(previousPartial.confidence, segment.confidence),
      isFinal: true,
      emphasis: min(previousPartial.emphasis, segment.emphasis)
    )
  }

  /// Promotes the most recently observed partial after the caller has measured a bounded pause.
  ///
  /// The argument must exactly equal the last value passed to ``observe(_:)``. This makes a stale
  /// timer fail closed when any provider field changes before it fires. Unlike the ordinary
  /// two-revision path, this narrow fallback accepts a punctuation-free Japanese statement, but
  /// only when it is substantive, explicitly marks importance, has valid bounded metadata, and has
  /// a conservative complete declarative ending. A low provider confidence is not represented as
  /// higher recognition certainty; the returned minimum instead records that this narrow pause
  /// contract supplied enough independent stability for the contextual engine to evaluate it.
  public mutating func commitAfterPause(_ segment: TranscriptSegment) -> TranscriptSegment? {
    guard !segment.isFinal,
      committedSegmentID != segment.id,
      let previousPartial,
      previousPartial == segment,
      hasValidPauseMetadata(previousPartial),
      hasValidPauseMetadata(segment),
      segment.language == .japanese
    else {
      return nil
    }

    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard firstCompleteDeclarativeUnit(in: text) == nil,
      !text.contains("?"),
      !text.contains("？"),
      isSubstantive(text),
      ImportanceScorer.containsExplicitImportanceCue(text),
      hasConservativeJapaneseDeclarativeEnding(text)
    else {
      return nil
    }

    committedSegmentID = segment.id
    return TranscriptSegment(
      id: segment.id,
      text: text,
      startTime: segment.startTime,
      endTime: segment.endTime,
      language: segment.language,
      confidence: max(segment.confidence, 0.5),
      isFinal: true,
      emphasis: segment.emphasis
    )
  }

  public mutating func reset() {
    previousPartial = nil
    committedSegmentID = nil
  }

  private func isReliable(_ segment: TranscriptSegment) -> Bool {
    segment.confidence.isFinite && (0.5...1).contains(segment.confidence)
      && segment.emphasis.isFinite && (0...1).contains(segment.emphasis)
      && segment.startTime.isFinite && segment.endTime.isFinite
      && segment.startTime >= 0 && segment.endTime >= segment.startTime
  }

  private func hasValidPauseMetadata(_ segment: TranscriptSegment) -> Bool {
    segment.confidence.isFinite && (0...1).contains(segment.confidence)
      && segment.emphasis.isFinite && (0...1).contains(segment.emphasis)
      && segment.startTime.isFinite && segment.endTime.isFinite
      && segment.startTime >= 0 && segment.endTime >= segment.startTime
  }

  private func commonPrefix(_ lhs: String, _ rhs: String) -> String {
    String(lhs.prefix(while: rhs, satisfies: ==))
  }

  private func firstCompleteDeclarativeUnit(in text: String) -> String? {
    var index = text.startIndex
    while index < text.endIndex {
      let next = text.index(after: index)
      if isDeclarativeBoundary(text[index], before: index, after: next, in: text) {
        return String(text[..<next]).trimmingCharacters(in: .whitespacesAndNewlines)
      }
      index = next
    }
    return nil
  }

  private func isDeclarativeBoundary(
    _ character: Character,
    before index: String.Index,
    after next: String.Index,
    in text: String
  ) -> Bool {
    if ["。", "．", "!", "！"].contains(character) { return true }
    guard character == "." else { return false }

    let previousIsDigit =
      index > text.startIndex && text[text.index(before: index)].isWholeNumber
    let nextIsDigit = next < text.endIndex && text[next].isWholeNumber
    guard !(previousIsDigit && nextIsDigit) else { return false }
    return next == text.endIndex || text[next].isWhitespace
  }

  private func isSubstantive(_ text: String) -> Bool {
    let nonWhitespaceCount = text.reduce(into: 0) { count, character in
      if !character.isWhitespace { count += 1 }
    }
    return nonWhitespaceCount >= 12 && nonWhitespaceCount <= 240
  }

  private func hasConservativeJapaneseDeclarativeEnding(_ text: String) -> Bool {
    [
      "ではありませんでした", "ではありません", "ではなかった", "ませんでした", "であります", "ではない",
      "でした", "ました", "ません", "である", "だった", "です", "ます",
    ].contains { text.hasSuffix($0) }
  }
}

extension String {
  fileprivate func prefix(
    while other: String,
    satisfies predicate: (Character, Character) -> Bool
  ) -> Substring {
    var lhsIndex = startIndex
    var rhsIndex = other.startIndex
    while lhsIndex < endIndex, rhsIndex < other.endIndex,
      predicate(self[lhsIndex], other[rhsIndex])
    {
      formIndex(after: &lhsIndex)
      other.formIndex(after: &rhsIndex)
    }
    return self[..<lhsIndex]
  }
}
