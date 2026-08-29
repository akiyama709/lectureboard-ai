import Foundation

public struct ContextualBoardEngine: Sendable {
  public var scorer: ImportanceScorer
  public var maximumProposalsPerPass: Int

  public init(
    scorer: ImportanceScorer = ImportanceScorer(),
    maximumProposalsPerPass: Int = 3
  ) {
    self.scorer = scorer
    self.maximumProposalsPerPass = maximumProposalsPerPass
  }

  public func propose(
    slide: SlideContext,
    recentSegments: [TranscriptSegment],
    existingIntents: [BoardIntent] = []
  ) -> [BoardIntent] {
    let existingSources = Set(existingIntents.flatMap(\.sourceSegmentIDs))

    return
      recentSegments
      .filter(\.isFinal)
      .filter { !existingSources.contains($0.id) }
      .compactMap { segment -> BoardIntent? in
        let score = scorer.score(
          segment: segment,
          slide: slide,
          recentSegments: recentSegments.filter { $0.id != segment.id }
        )
        guard scorer.shouldPropose(score) else { return nil }
        return classify(segment: segment, slide: slide, score: score)
      }
      .sorted {
        if $0.importance == $1.importance {
          return $0.confidence > $1.confidence
        }
        return $0.importance > $1.importance
      }
      .prefix(maximumProposalsPerPass)
      .map { $0 }
  }

  private func classify(
    segment: TranscriptSegment,
    slide: SlideContext,
    score: ImportanceScore
  ) -> BoardIntent {
    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let kind = classifyKind(text)
    let content = groundedContent(for: kind, text: text)
    let defaultTitle =
      slide.title.isEmpty ? localizedTitle(for: kind, language: segment.language) : slide.title

    return BoardIntent(
      kind: kind,
      title: content.title ?? defaultTitle,
      items: content.items,
      sourceSegmentIDs: [segment.id],
      importance: score.total,
      confidence: min(segment.confidence, 1),
      language: segment.language,
      state: score.total >= 0.78 ? .confirmed : .proposed
    )
  }

  private func classifyKind(_ text: String) -> BoardIntentKind {
    if TextFeatures.containsAny(text, phrases: ImportanceScorer.definitionCues) {
      return .definition
    }
    if TextFeatures.containsAny(text, phrases: ImportanceScorer.causalCues) { return .causalChain }
    if TextFeatures.containsAny(text, phrases: ImportanceScorer.comparisonCues) {
      return .comparison
    }
    if TextFeatures.containsAny(text, phrases: ImportanceScorer.enumerationCues) { return .list }
    if text.hasSuffix("?") || text.hasSuffix("？")
      || TextFeatures.containsAny(text, phrases: ImportanceScorer.questionCues)
    {
      return .question
    }
    return .keyword
  }

  private func groundedContent(for kind: BoardIntentKind, text: String) -> (
    title: String?, items: [String]
  ) {
    switch kind {
    case .definition:
      return splitDefinition(text)
    case .causalChain:
      return (nil, split(text, cues: ImportanceScorer.causalCues))
    case .comparison:
      return (nil, split(text, cues: ImportanceScorer.comparisonCues))
    case .list:
      return (nil, splitList(text))
    case .question:
      return (nil, [bounded(text)])
    default:
      return (nil, [bounded(text)])
    }
  }

  private func splitDefinition(_ text: String) -> (title: String?, items: [String]) {
    let cues = ["とは", "means", "is defined as", "refers to", "すなわち", "in other words"]
    for cue in cues {
      if let range = text.range(of: cue, options: [.caseInsensitive, .diacriticInsensitive]) {
        let lhs = text[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        let rhs = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        if !lhs.isEmpty, !rhs.isEmpty {
          return (bounded(String(lhs), limit: 42), [bounded(String(rhs))])
        }
      }
    }
    return (nil, [bounded(text)])
  }

  private func split(_ text: String, cues: [String]) -> [String] {
    var components = [text]
    for cue in cues {
      components = components.flatMap { component in
        component.components(separatedBy: cue)
      }
    }
    let cleaned =
      components
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)) }
      .filter { !$0.isEmpty }
      .map { bounded($0, limit: 72) }
    return cleaned.count >= 2 ? Array(cleaned.prefix(4)) : [bounded(text)]
  }

  private func splitList(_ text: String) -> [String] {
    let separators = CharacterSet(charactersIn: "、，,;；。．")
    let items =
      text
      .components(separatedBy: separators)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .map { bounded($0, limit: 64) }
    return items.count >= 2 ? Array(items.prefix(5)) : [bounded(text)]
  }

  private func bounded(_ text: String, limit: Int = 96) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit - 1)) + "…"
  }

  private func localizedTitle(for kind: BoardIntentKind, language: LanguageTag) -> String {
    let japanese = language.rawValue.lowercased().hasPrefix("ja")
    switch kind {
    case .definition: return japanese ? "定義" : "Definition"
    case .causalChain: return japanese ? "因果関係" : "Causal relationship"
    case .comparison: return japanese ? "比較" : "Comparison"
    case .list: return japanese ? "要点" : "Key points"
    case .question: return japanese ? "問い" : "Question"
    case .warning: return japanese ? "注意" : "Caution"
    case .example: return japanese ? "例" : "Example"
    case .conceptMap: return japanese ? "概念関係" : "Concept map"
    case .keyword: return japanese ? "要点" : "Key point"
    }
  }
}
