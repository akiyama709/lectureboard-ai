import Foundation

/// Promotes one stable, complete declarative unit from a stream of partial speech hypotheses.
///
/// The newest hypothesis is never published by itself. A sentence boundary must survive in two
/// consecutive revisions of one provider-owned segment. Ordinarily both revisions must meet the
/// recognition-confidence floor; two exact-zero revisions may forward a completed prefix only when
/// it contains an explicit importance statement for semantic review. A caller may separately invoke
/// ``commitAfterPause(_:)`` after a bounded no-update interval; that path is likewise limited to a
/// completed prefix containing an importance statement, an unpunctuated Japanese or English
/// importance statement with a conservative declarative ending, or a safe whole-utterance request
/// accepted by ``ExplicitBoardRequestParser``. The whole stable review candidate, including an
/// unfinished trailing fragment, is preserved so that a later semantic safety gate can see
/// corrections, qualifications, questions, and surrounding context instead of receiving a
/// misleading extracted fragment. Only its completed prefix is consumed. Every finite provider
/// confidence in the bounded zero-through-one range is retained rather than inflated on the pause
/// path, and every incremental commit retains both the provider identity and the cumulative stable
/// prefix. This lets the contextual engine distinguish an append-only continuation from a later
/// correction in the same provider cycle.
/// The contextual board engine remains responsible for grounding, semantic safety, importance, and
/// the final public-state decision.
public struct StablePartialTranscriptCommitter: Sendable {
  private var previousPartial: TranscriptSegment?
  private var progressSegmentID: UUID?
  private var consumedPrefix = ""
  private var quarantinedSegmentID: UUID?

  public init() {}

  public mutating func observe(_ segment: TranscriptSegment) -> TranscriptSegment? {
    guard !segment.isFinal else {
      reset()
      return nil
    }

    guard let previousPartial else {
      beginProgress(for: segment.id)
      self.previousPartial = segment
      return nil
    }
    defer { self.previousPartial = segment }
    if previousPartial.id != segment.id || previousPartial.language != segment.language {
      beginProgress(for: segment.id)
      return nil
    }
    guard quarantinedSegmentID != segment.id else { return nil }

    let stablePrefix = commonPrefix(previousPartial.text, segment.text)
    guard stablePrefix.hasPrefix(consumedPrefix), segment.text.hasPrefix(consumedPrefix) else {
      quarantinedSegmentID = segment.id
      return nil
    }
    let hasOrdinaryReliability = isReliable(previousPartial) && isReliable(segment)
    let hasStableExactZeroEvidence =
      previousPartial.confidence == 0 && segment.confidence == 0
      && hasValidPauseMetadata(previousPartial) && hasValidPauseMetadata(segment)
    guard hasOrdinaryReliability || hasStableExactZeroEvidence,
      segment.endTime >= previousPartial.endTime
    else {
      return nil
    }

    let unconsumed = String(stablePrefix.dropFirst(consumedPrefix.count))
    let completedUnits = completeUnits(in: unconsumed)
    guard !completedUnits.isEmpty else {
      return nil
    }
    let completedPrefix = completedUnits.map(\.sourceText).joined()
    let declarativeUnits = completedUnits.filter(\.isDeclarative)
    let shouldEmit: Bool
    if hasOrdinaryReliability {
      shouldEmit = declarativeUnits.contains {
        isSubstantive($0.trimmedText)
          || ImportanceScorer.containsExplicitImportanceCue($0.trimmedText)
      }
      // The contextual engine decides which declarative units are public. Retain all completed
      // surrounding units so a question, correction, or qualification cannot be hidden from it.
    } else {
      shouldEmit = declarativeUnits.contains(where: {
        ImportanceScorer.containsExplicitImportanceCue($0.trimmedText)
      })
    }

    // Stable questions and short framing units cannot become board candidates, but consuming them
    // lets a later complete declarative unit advance independently. Any subsequent revision of
    // this consumed prefix is quarantined below instead of being silently reinterpreted.
    guard shouldEmit else {
      consumedPrefix += completedPrefix
      return nil
    }

    let semanticReviewText = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    consumedPrefix += completedPrefix

    return syntheticFinal(
      from: segment,
      text: semanticReviewText,
      confidence: min(previousPartial.confidence, segment.confidence),
      emphasis: min(previousPartial.emphasis, segment.emphasis)
    )
  }

  /// Promotes the most recently observed partial after the caller has measured a bounded pause.
  ///
  /// The argument must exactly equal the last value passed to ``observe(_:)``. This makes a stale
  /// timer fail closed when any provider field changes before it fires. Unlike the ordinary
  /// two-revision path, this narrow fallback accepts a completed prefix containing at least one
  /// explicit importance statement, a punctuation-free Japanese or English importance statement,
  /// or a safe whole-utterance board request. It requires valid bounded metadata and retains the
  /// provider confidence without inflating it. The contextual board engine remains responsible for
  /// semantic safety and the final public-state decision.
  public mutating func commitAfterPause(_ segment: TranscriptSegment) -> TranscriptSegment? {
    guard !segment.isFinal,
      quarantinedSegmentID != segment.id,
      progressSegmentID == segment.id,
      consumedPrefix != segment.text,
      let previousPartial,
      previousPartial == segment,
      hasValidPauseMetadata(previousPartial),
      hasValidPauseMetadata(segment)
    else {
      return nil
    }

    guard segment.text.hasPrefix(consumedPrefix) else {
      quarantinedSegmentID = segment.id
      return nil
    }

    let unconsumed = String(segment.text.dropFirst(consumedPrefix.count))
    let completedUnits = completeUnits(in: unconsumed)
    let completedPrefix = completedUnits.map(\.sourceText).joined()
    let hasCompletedImportanceUnit = completedUnits.contains {
      $0.isDeclarative && ImportanceScorer.containsExplicitImportanceCue($0.trimmedText)
    }
    if hasCompletedImportanceUnit {
      consumedPrefix += completedPrefix
      return syntheticFinal(
        from: segment,
        text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    }

    let wholeUtterance = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    if ExplicitBoardRequestParser.requestedContent(
      in: wholeUtterance,
      language: segment.language
    ) != nil {
      consumedPrefix = segment.text
      return syntheticFinal(from: segment, text: wholeUtterance)
    }

    let trailingText = String(unconsumed.dropFirst(completedPrefix.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trailingText.contains("?"),
      !trailingText.contains("？"),
      isSubstantiveImportanceUtterance(trailingText),
      ImportanceScorer.containsExplicitImportanceCue(trailingText),
      hasConservativeUnpunctuatedDeclarativeEnding(
        trailingText,
        language: segment.language
      )
    else {
      return nil
    }

    consumedPrefix = segment.text
    return syntheticFinal(
      from: segment,
      text: segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  public mutating func reset() {
    previousPartial = nil
    progressSegmentID = nil
    consumedPrefix = ""
    quarantinedSegmentID = nil
  }

  private struct CompleteUnit {
    var sourceText: String
    var trimmedText: String
    var isDeclarative: Bool
  }

  private mutating func beginProgress(for segmentID: UUID) {
    progressSegmentID = segmentID
    consumedPrefix = ""
    quarantinedSegmentID = nil
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

  private mutating func syntheticFinal(
    from segment: TranscriptSegment,
    text: String,
    confidence: Double? = nil,
    emphasis: Double? = nil
  ) -> TranscriptSegment {
    return TranscriptSegment(
      id: segment.id,
      text: text,
      startTime: segment.startTime,
      endTime: segment.endTime,
      language: segment.language,
      confidence: confidence ?? segment.confidence,
      isFinal: true,
      emphasis: emphasis ?? segment.emphasis
    )
  }

  private func commonPrefix(_ lhs: String, _ rhs: String) -> String {
    String(lhs.prefix(while: rhs, satisfies: ==))
  }

  private func completeUnits(in text: String) -> [CompleteUnit] {
    var units: [CompleteUnit] = []
    var unitStart = text.startIndex
    var index = text.startIndex
    while index < text.endIndex {
      let next = text.index(after: index)
      if isCompleteBoundary(text[index], before: index, after: next, in: text) {
        let sourceText = String(text[unitStart..<next])
        let trimmedText = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedText.isEmpty {
          units.append(
            CompleteUnit(
              sourceText: sourceText,
              trimmedText: trimmedText,
              isDeclarative: isDeclarativeBoundary(
                text[index],
                before: index,
                after: next,
                in: text
              )
            )
          )
        }
        unitStart = next
      }
      index = next
    }
    return units
  }

  private func isCompleteBoundary(
    _ character: Character,
    before index: String.Index,
    after next: String.Index,
    in text: String
  ) -> Bool {
    if ["。", "．", "!", "！", "?", "？"].contains(character) { return true }
    guard character == "." else { return false }

    let previousIsDigit =
      index > text.startIndex && text[text.index(before: index)].isWholeNumber
    let nextIsDigit = next < text.endIndex && text[next].isWholeNumber
    guard !(previousIsDigit && nextIsDigit) else { return false }
    return next == text.endIndex || text[next].isWhitespace
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
    return nonWhitespaceCount >= 11 && nonWhitespaceCount <= 240
  }

  private func isSubstantiveImportanceUtterance(_ text: String) -> Bool {
    let nonWhitespaceCount = text.reduce(into: 0) { count, character in
      if !character.isWhitespace { count += 1 }
    }
    // Short natural cues such as `肝は文脈です` still carry a complete proposition. The contextual
    // engine independently validates the extracted body and semantic safety before publication.
    return nonWhitespaceCount >= 6 && nonWhitespaceCount <= 240
  }

  private func hasConservativeUnpunctuatedDeclarativeEnding(
    _ text: String,
    language: LanguageTag
  ) -> Bool {
    let languageCode = language.rawValue.lowercased()
    if languageCode.hasPrefix("ja") {
      return [
        "ではありませんでした", "ではありません", "ではなかった", "ませんでした", "であります", "ではない",
        "でした", "ました", "ません", "である", "だった", "です", "ます",
        "ください", "下さい",
      ].contains { text.hasSuffix($0) }
    }

    guard languageCode.hasPrefix("en") else { return false }
    let words = text.split { !$0.isLetter && !$0.isNumber }
    guard let finalWord = words.last?.lowercased() else { return false }
    let incompleteFinalWords: Set<String> = [
      "a", "an", "and", "are", "as", "at", "be", "because", "been", "being", "but",
      "by", "can", "could", "did", "do", "does", "for", "from", "had", "has", "have",
      "if", "in", "is", "must", "of", "on", "or", "should", "that", "the", "to", "was",
      "were", "which", "who", "will", "with", "without", "would",
    ]
    return !incompleteFinalWords.contains(finalWord)
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
