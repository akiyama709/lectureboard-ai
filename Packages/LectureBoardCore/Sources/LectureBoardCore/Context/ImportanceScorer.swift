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
    let lexicalImportanceBonus = Self.containsExplicitImportanceCue(segment.text) ? 0.30 : 0

    let total = clamp(
      0.28 * novelty
        + 0.29 * structure
        + 0.18 * repetition
        + 0.17 * emphasis
        + 0.08 * dwell
        + lexicalImportanceBonus
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
    if Self.containsExplicitImportanceCue(text) { return 1.0 }
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

  static let importancePrefixCuePatterns = [
    #"^\s*(?:ここで\s*)?(?:特に\s*)?重要なのは\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:特に\s*)?重要な(?:点|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:特に\s*)?(?:大切|大事)な(?:点|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:一番|最も)\s*(?:重要|大切)なのは\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:特に\s*)?大切なのは\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:特に\s*)?(?:大事|肝心)なのは\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:(?:この|その|今日の|今回の)\s*)?(?:要点|ポイント)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:ぜひ\s*)?(?:押さえて|理解して|覚えて)(?:おいて|いて)?ほしい(?:の|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:ぜひ\s*)?(?:注目して|意識して)(?:おいて|いて)?ほしい(?:の|点|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:特に\s*)?(?:強調|重視)したい(?:の|点|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:ぜひ\s*)?(?:押さえるべき|覚えておくべき|見逃してはいけない)(?:点|こと|の)?は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:(?:この|その|ここでの)\s*)?(?:鍵|核心)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:鍵|核心)になるのは\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:要するに|まとめると|まとめれば|一言で言えば|ひとことで言えば|端的に言えば|結論を言うと)\s*[、，,;；:：]?\s*"#,
    #"^\s*結論(?:として(?:は)?|は)\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:the|a|an|our|my)\s+(?:(?:most\s+)?important|key|main|central)\s+(?:point|idea|thing|takeaway)(?:\s+here)?\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*the\s+(?:point|bottom\s+line|take(?:[-‐‑–—]|\s+)home\s+message|thing\s+to\s+remember|core\s+(?:point|message|issue))\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*the\s+(?:conclusion|takeaway)(?:\s+here)?\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*what\s+matters\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*what\s+is\s+important\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*what\s+(?:i\s+want\s+you\s+to|you\s+(?:should|need\s+to))\s+remember(?:\s+here)?\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*(?:please\s+)?remember\s+that(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*keep\s+in\s+mind\s+that(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*(?:please\s+)?pay\s+attention\s+to(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*(?:(?:i|we)\s+(?:want|need)\s+to|let\s+me)\s+(?:emphasize|stress|highlight)(?:\s+that)?(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*(?:in\s+conclusion|to\s+conclude|in\s+summary|to\s+summarize|to\s+sum\s+up|in\s+short|most\s+importantly|put\s+simply|simply\s+put)\s*[,;:]?\s*"#,
    #"^\s*(?:もう一つ|もうひとつ|別の)\s*(?:重要|大切)な(?:点|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?(?:肝|要旨)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?忘れないでほしい(?:の|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*(?:ここで\s*)?一番伝えたい(?:の|こと)は\s*[、，,;；:：]?\s*"#,
    #"^\s*another\s+(?:important|key|main)\s+(?:point|idea|thing)\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*(?:the\s+)?crux(?:\s+here)?\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*(?:the\s+)?one\s+thing\s+to\s+remember(?:\s+here)?\s+is(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*you\s+should\s+remember\s+that(?=\s|[,;:])\s*[,;:]?\s*"#,
    #"^\s*above\s+all\s*[,;:]?\s*"#,
  ]

  static let importanceSuffixCuePatterns = [
    #"(?:が|こそ)\s*(?:(?:いちばん|一番|最も|特に)\s*)?(?:重要|大切|大事)(?:です|だ|である)\s*[。．.!！]?\s*$"#,
    #"(?:が|こそ|は)\s*(?:(?:いちばん|一番|最も|特に)\s*)?(?:重要な\s*)?(?:鍵|核心|要点|ポイント|決め手|本質)(?:です|だ|である|になります|となります)\s*[。．.!！]?\s*$"#,
    #"\s+(?:is|are)\s+(?:(?:the\s+)?(?:most|particularly)\s+)?(?:important|essential|crucial)(?:\s+(?:point|thing|idea|takeaway))?\s*[.!]?\s*$"#,
    #"\s+(?:is|are)\s+(?:the\s+)?(?:key|central|core|fundamental)(?:\s+(?:point|idea|issue|message|factor))?\s*[.!]?\s*$"#,
    #"\s+(?:is|are)\s+the\s+(?:point|bottom\s+line|take(?:[-‐‑–—]|\s+)home\s+message)\s*[.!]?\s*$"#,
    #"\s+(?:is|are)\s+(?:what\s+matters|worth\s+remembering)\s*[.!]?\s*$"#,
    #"\s+matters?\s+most\s*[.!]?\s*$"#,
    #"(?:は)\s*(?:(?:いちばん|一番|最も|特に)\s*)?(?:重要|大切|大事)(?:です|だ|である)\s*[。．.!！]?\s*$"#,
    #"を\s*覚えておいてください\s*[。．.!！]?\s*$"#,
  ]

  static let importanceCuePatterns =
    importancePrefixCuePatterns + importanceSuffixCuePatterns

  static func containsExplicitImportanceCue(_ text: String) -> Bool {
    let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return importanceCuePatterns.contains { pattern in
      guard
        let expression = try? NSRegularExpression(
          pattern: pattern,
          options: [.caseInsensitive]
        )
      else {
        return false
      }
      return expression.firstMatch(in: text, range: searchRange) != nil
    }
  }

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
