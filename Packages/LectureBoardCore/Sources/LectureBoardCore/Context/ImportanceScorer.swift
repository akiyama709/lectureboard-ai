import Foundation

public struct ImportanceScore: Codable, Hashable, Sendable {
  public var total: Double
  public var novelty: Double
  public var discourseStructure: Double
  public var repetition: Double
  public var emphasis: Double
  public var dwell: Double

  public init(
    total: Double,
    novelty: Double,
    discourseStructure: Double,
    repetition: Double,
    emphasis: Double,
    dwell: Double
  ) {
    self.total = total
    self.novelty = novelty
    self.discourseStructure = discourseStructure
    self.repetition = repetition
    self.emphasis = emphasis
    self.dwell = dwell
  }
}

public struct ImportanceScorer: Sendable {
  public var threshold: Double

  public init(threshold: Double = 0.58) {
    self.threshold = threshold
  }

  public func score(
    segment: TranscriptSegment,
    slide: SlideContext,
    recentSegments: [TranscriptSegment]
  ) -> ImportanceScore {
    let segmentTokens = TextFeatures.tokens(segment.text)
    let slideTokens = TextFeatures.tokens(slide.searchableText)
    let novelty = 1 - TextFeatures.jaccard(segmentTokens, slideTokens)
    let structure = discourseStructureScore(segment.text)
    let repetition = repetitionScore(segmentTokens, in: recentSegments)
    let emphasis = min(max(segment.emphasis, 0), 1)
    let dwell = min(max(slide.dwellTime / 120, 0), 1)

    let total = clamp(
      0.28 * novelty
        + 0.29 * structure
        + 0.18 * repetition
        + 0.17 * emphasis
        + 0.08 * dwell
    )

    return ImportanceScore(
      total: total,
      novelty: novelty,
      discourseStructure: structure,
      repetition: repetition,
      emphasis: emphasis,
      dwell: dwell
    )
  }

  public func shouldPropose(_ score: ImportanceScore) -> Bool {
    score.total >= threshold
  }

  private func discourseStructureScore(_ text: String) -> Double {
    if TextFeatures.containsAny(text, phrases: Self.definitionCues) { return 1.0 }
    if TextFeatures.containsAny(text, phrases: Self.causalCues) { return 0.95 }
    if TextFeatures.containsAny(text, phrases: Self.comparisonCues) { return 0.9 }
    if TextFeatures.containsAny(text, phrases: Self.enumerationCues) { return 0.8 }
    if text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
      || text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("？")
      || TextFeatures.containsAny(text, phrases: Self.questionCues)
    {
      return 0.75
    }
    return 0.35
  }

  private func repetitionScore(_ tokens: Set<String>, in recentSegments: [TranscriptSegment])
    -> Double
  {
    guard !tokens.isEmpty, !recentSegments.isEmpty else { return 0 }
    let occurrences = recentSegments.reduce(into: 0) { count, segment in
      let overlap = TextFeatures.jaccard(tokens, TextFeatures.tokens(segment.text))
      if overlap >= 0.25 { count += 1 }
    }
    return min(Double(occurrences) / 3, 1)
  }

  private func clamp(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }

  static let definitionCues = [
    "とは", "を意味します", "を意味する", "定義", "すなわち", "言い換えると",
    "means", "is defined as", "refers to", "in other words",
  ]

  static let causalCues = [
    "なぜなら", "そのため", "したがって", "結果として", "につながる", "をもたらす",
    "because", "therefore", "as a result", "leads to", "results in", "causes",
  ]

  static let comparisonCues = [
    "一方", "対して", "異なり", "比較", "これに対し",
    "whereas", "in contrast", "compared with", "on the other hand", "unlike",
  ]

  static let enumerationCues = [
    "第一", "第二", "三つ", "四つ", "ポイントは", "要点は",
    "first", "second", "three points", "four points", "the key points",
  ]

  static let questionCues = [
    "なぜ", "どのように", "何が", "問うべき", "why", "how", "what should",
  ]
}
