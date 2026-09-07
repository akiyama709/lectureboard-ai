import Foundation

public struct ContextualBoardEngine: Sendable {
  private static let automaticKeywordConfirmationThreshold = 0.66

  private struct ExplicitBoardContent {
    var kind: BoardIntentKind
    var title: String?
    var items: [String]
  }

  private enum CausalDirection {
    case forward
    case reverse
  }

  private struct DirectionalMatch {
    var range: Range<String.Index>
    var direction: CausalDirection
  }

  private struct OrdinalMatch {
    var ordinal: Int
    var range: Range<String.Index>
  }

  private struct RepeatedEvidenceKey: Equatable {
    var text: String
    var isQuestion: Bool
  }

  private struct EvidenceInterval: Hashable {
    var startTime: TimeInterval
    var endTime: TimeInterval
  }

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
    guard maximumProposalsPerPass > 0 else { return [] }
    let existingSources = Set(existingIntents.flatMap(\.sourceSegmentIDs))
    let finalizedSegments = recentSegments.filter(\.isFinal)

    let candidates =
      finalizedSegments
      .enumerated()
      .filter { !existingSources.contains($0.element.id) }
      .compactMap { sourceIndex, segment -> (sourceIndex: Int, intent: BoardIntent)? in
        let otherFinalizedSegments = finalizedSegments.filter { $0.id != segment.id }
        let matchingRepeatedEvidence = repeatedEvidence(
          for: segment,
          among: otherFinalizedSegments
        )
        let score = scorer.score(
          segment: segment,
          slide: slide,
          recentSegments: otherFinalizedSegments
        )
        guard scorer.shouldPropose(score) else { return nil }
        let reliableRepeatedScore = scorer.score(
          segment: segment,
          slide: slide,
          recentSegments: matchingRepeatedEvidence
        )
        let intent = classify(
          segment: segment,
          slide: slide,
          score: score,
          reliableRepeatedScore: reliableRepeatedScore,
          repeatedEvidence: matchingRepeatedEvidence
        )
        guard
          !existingIntents.contains(where: { existing in
            isPublic(existing.state) && hasSameVisibleContent(existing, intent)
          })
        else {
          return nil
        }
        return (sourceIndex, intent)
      }
      .sorted {
        let lhsIsPublic = isPublic($0.intent.state)
        let rhsIsPublic = isPublic($1.intent.state)
        if lhsIsPublic != rhsIsPublic {
          return lhsIsPublic
        }
        if $0.intent.importance != $1.intent.importance {
          return $0.intent.importance > $1.intent.importance
        }
        if $0.intent.confidence != $1.intent.confidence {
          return $0.intent.confidence > $1.intent.confidence
        }
        return $0.sourceIndex < $1.sourceIndex
      }
      .map(\.intent)

    var accepted: [BoardIntent] = []
    for candidate in candidates {
      if isPublic(candidate.state),
        accepted.contains(where: { isPublic($0.state) && hasSameVisibleContent($0, candidate) })
      {
        continue
      }
      accepted.append(candidate)
      if accepted.count == maximumProposalsPerPass { break }
    }
    return accepted
  }

  private func classify(
    segment: TranscriptSegment,
    slide: SlideContext,
    score: ImportanceScore,
    reliableRepeatedScore: ImportanceScore,
    repeatedEvidence: [TranscriptSegment]
  ) -> BoardIntent {
    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let inferredKind = classifyKind(text)
    let inferredContent = groundedContent(for: inferredKind, text: text)
    let explicitContent = explicitlyStructuredContent(text, on: slide)
    let hasReliableEvidence = isReliable(segment)
    let hasRepeatedExplicitQuestion =
      hasReliableEvidence && isExplicitQuestion(text) && repeatedEvidence.count >= 3
    let hasHighImportanceRepeatedKeywordAssertion =
      hasReliableEvidence
      && inferredKind == .keyword
      && repeatedEvidence.count >= 1
      && reliableRepeatedScore.total >= Self.automaticKeywordConfirmationThreshold
      && isSafeAutomaticKeywordAssertion(text)
    let kind: BoardIntentKind
    let content: (title: String?, items: [String])
    let state: BoardIntentState
    let usesRepeatedEvidence: Bool

    if let explicitContent {
      kind = explicitContent.kind
      content = (explicitContent.title, explicitContent.items)
      state = hasReliableEvidence ? .confirmed : .proposed
      usesRepeatedEvidence = false
    } else if hasRepeatedExplicitQuestion {
      kind = .question
      content = (nil, [bounded(text)])
      state = .confirmed
      usesRepeatedEvidence = true
    } else if hasHighImportanceRepeatedKeywordAssertion {
      kind = .keyword
      content = (nil, [bounded(text)])
      state = .confirmed
      usesRepeatedEvidence = true
    } else {
      kind = inferredKind
      content = inferredContent
      state = .proposed
      usesRepeatedEvidence = false
    }
    let defaultTitle =
      slide.title.isEmpty ? localizedTitle(for: kind, language: segment.language) : slide.title

    let sourceSegmentIDs =
      usesRepeatedEvidence
      ? [segment.id] + repeatedEvidence.prefix(3).map(\.id)
      : [segment.id]

    return BoardIntent(
      kind: kind,
      title: content.title ?? defaultTitle,
      items: content.items,
      sourceSegmentIDs: sourceSegmentIDs,
      importance: score.total,
      confidence: min(segment.confidence, 1),
      language: segment.language,
      state: state
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

  private func explicitlyStructuredContent(
    _ text: String,
    on slide: SlideContext
  ) -> ExplicitBoardContent? {
    guard !isExplicitQuestion(text) else { return nil }

    if let importanceBody = explicitImportanceBody(in: text) {
      let structuredCandidates = [
        explicitDefinition(in: importanceBody, on: slide),
        explicitCausalChain(in: importanceBody),
        explicitComparison(in: importanceBody),
        explicitList(in: importanceBody),
      ].compactMap { $0 }
      if structuredCandidates.count == 1 {
        return structuredCandidates[0]
      }
      guard structuredCandidates.isEmpty, classifyKind(importanceBody) == .keyword,
        isSingleSubstantiveClause(importanceBody)
      else {
        return nil
      }
      return ExplicitBoardContent(kind: .keyword, title: nil, items: [bounded(importanceBody)])
    }

    let candidates = [
      explicitDefinition(in: text, on: slide),
      explicitCausalChain(in: text),
      explicitComparison(in: text),
      explicitList(in: text),
    ].compactMap { $0 }

    return candidates.count == 1 ? candidates[0] : nil
  }

  private func explicitImportanceBody(in text: String) -> String? {
    let matches = ImportanceScorer.importanceCuePatterns.flatMap {
      regexRanges($0, in: text, caseInsensitive: true)
    }
    guard matches.count == 1, let cue = matches.first else { return nil }

    let body = trimBoardItem(String(text[cue.upperBound...]))
    guard !body.isEmpty, !isExplicitQuestion(body), isSafeStructuredUtterance(text)
    else {
      return nil
    }
    return body
  }

  private func explicitDefinition(
    in text: String,
    on slide: SlideContext
  ) -> ExplicitBoardContent? {
    var cueRanges: [Range<String.Index>] = []

    for range in regexRanges(#"とは"#, in: text) {
      let suffix = text[range.upperBound...]
      if !suffix.hasPrefix("異な"), !suffix.hasPrefix("違") {
        cueRanges.append(range)
      }
    }
    for pattern in [
      #"\bis\s+defined\s+as\b"#,
      #"\bmeans\b"#,
      #"\brefers\s+to\b"#,
    ] {
      cueRanges.append(contentsOf: regexRanges(pattern, in: text, caseInsensitive: true))
    }

    cueRanges.sort { $0.lowerBound < $1.lowerBound }
    guard cueRanges.count == 1, let cue = cueRanges.first else { return nil }

    let rawTitle = trimDefinitionTitle(String(text[..<cue.lowerBound]))
    let rawBody = trimBoardItem(String(text[cue.upperBound...]))
    guard isDefinitionTerm(rawTitle), !rawBody.isEmpty,
      !isExplicitQuestion(rawBody), isDefinitionAnswer(rawBody),
      isSingleSubstantiveClause(rawBody),
      isGrounded(term: rawTitle, on: slide)
    else {
      return nil
    }

    return ExplicitBoardContent(
      kind: .definition,
      title: bounded(rawTitle, limit: 42),
      items: [bounded(rawBody)]
    )
  }

  private func explicitCausalChain(in text: String) -> ExplicitBoardContent? {
    let descriptors: [(String, CausalDirection, Bool)] = [
      (#"(?<=[。．.!！?？、，,;；:：])\s*そのため"#, .forward, false),
      (#"したがって"#, .forward, false),
      (#"結果として"#, .forward, false),
      (#"\btherefore\b"#, .forward, true),
      (#"\bas\s+a\s+result\b(?!\s+of\b)"#, .forward, true),
      (#"なぜなら"#, .reverse, false),
      (#"\bbecause\b"#, .reverse, true),
      (#"\bas\s+a\s+result\s+of\b"#, .reverse, true),
    ]
    var matches: [DirectionalMatch] = []
    for (pattern, direction, caseInsensitive) in descriptors {
      matches.append(
        contentsOf: regexRanges(pattern, in: text, caseInsensitive: caseInsensitive).map {
          DirectionalMatch(range: $0, direction: direction)
        }
      )
    }
    matches.sort { $0.range.lowerBound < $1.range.lowerBound }
    guard !matches.isEmpty, nonoverlapping(matches.map(\.range)) else { return nil }
    guard isSafeStructuredUtterance(text) else { return nil }

    let directions = Set(matches.map { $0.direction == .forward ? 0 : 1 })
    guard directions.count == 1 else { return nil }
    let components = split(text, at: matches.map(\.range)).map { trimBoardItem($0) }.filter {
      !$0.isEmpty
    }
    guard components.allSatisfy(isSingleSubstantiveClause) else { return nil }

    if matches[0].direction == .reverse {
      guard matches.count == 1, components.count == 2 else { return nil }
      return ExplicitBoardContent(
        kind: .causalChain,
        title: nil,
        items: [bounded(components[1], limit: 72), bounded(components[0], limit: 72)]
      )
    }

    guard components.count == matches.count + 1, components.count >= 2 else { return nil }
    return ExplicitBoardContent(
      kind: .causalChain,
      title: nil,
      items: Array(components.prefix(4)).map { bounded($0, limit: 72) }
    )
  }

  private func explicitComparison(in text: String) -> ExplicitBoardContent? {
    let patterns = [
      #"一方で(?:は)?"#,
      #"とは異なり"#,
      #"\bwhereas\b"#,
      #"\bon\s+the\s+other\s+hand\b"#,
    ]
    let matches = patterns.flatMap {
      regexRanges($0, in: text, caseInsensitive: true)
    }.sorted { $0.lowerBound < $1.lowerBound }
    guard matches.count == 1, let cue = matches.first else { return nil }
    guard isSafeStructuredUtterance(text) else { return nil }

    let components = split(text, at: [cue]).map { trimBoardItem($0) }.filter { !$0.isEmpty }
    guard components.count == 2, components.allSatisfy(isSingleSubstantiveClause) else {
      return nil
    }
    return ExplicitBoardContent(
      kind: .comparison,
      title: nil,
      items: components.map { bounded($0, limit: 72) }
    )
  }

  private func explicitList(in text: String) -> ExplicitBoardContent? {
    let descriptors: [(Int, String, Bool)] = [
      (1, #"第一(?:に|は|として|[:：、，])"#, false),
      (2, #"第二(?:に|は|として|[:：、，])"#, false),
      (3, #"第三(?:に|は|として|[:：、，])"#, false),
      (4, #"第四(?:に|は|として|[:：、，])"#, false),
      (1, #"(?:一|1)(?:つ|個|番)目(?:に|は|として|の|[:：、，])"#, false),
      (2, #"(?:二|2)(?:つ|個|番)目(?:に|は|として|の|[:：、，])"#, false),
      (3, #"(?:三|3)(?:つ|個|番)目(?:に|は|として|の|[:：、，])"#, false),
      (4, #"(?:四|4)(?:つ|個|番)目(?:に|は|として|の|[:：、，])"#, false),
      (1, #"\bfirst(?:ly)?\b(?:\s+point\b)?(?:\s+is\b)?\s*[,;:]?"#, true),
      (2, #"\bsecond(?:ly)?\b(?:\s+point\b)?(?:\s+is\b)?\s*[,;:]?"#, true),
      (3, #"\bthird(?:ly)?\b(?:\s+point\b)?(?:\s+is\b)?\s*[,;:]?"#, true),
      (4, #"\bfourth(?:ly)?\b(?:\s+point\b)?(?:\s+is\b)?\s*[,;:]?"#, true),
    ]
    var matches: [OrdinalMatch] = []
    for (ordinal, pattern, caseInsensitive) in descriptors {
      matches.append(
        contentsOf: regexRanges(pattern, in: text, caseInsensitive: caseInsensitive)
          .filter { startsAtEnumerationBoundary($0, in: text) }
          .map { OrdinalMatch(ordinal: ordinal, range: $0) }
      )
    }
    matches.sort { $0.range.lowerBound < $1.range.lowerBound }
    guard matches.count >= 2, nonoverlapping(matches.map(\.range)) else { return nil }
    guard isSafeStructuredUtterance(text) else { return nil }

    let ordinals = matches.map(\.ordinal)
    guard ordinals.first == 1,
      zip(ordinals, ordinals.dropFirst()).allSatisfy({ pair in
        pair.1 == pair.0 + 1
      })
    else {
      return nil
    }

    var items: [String] = []
    for index in matches.indices {
      let lowerBound = matches[index].range.upperBound
      let upperBound =
        index + 1 < matches.count ? matches[index + 1].range.lowerBound : text.endIndex
      let item = trimBoardItem(String(text[lowerBound..<upperBound]))
      guard !item.isEmpty else { return nil }
      items.append(bounded(item, limit: 64))
    }
    guard items.allSatisfy(isSingleSubstantiveClause) else { return nil }

    return ExplicitBoardContent(kind: .list, title: nil, items: Array(items.prefix(5)))
  }

  private func repeatedEvidence(
    for segment: TranscriptSegment,
    among candidates: [TranscriptSegment]
  ) -> [TranscriptSegment] {
    guard isReliable(segment) else { return [] }
    let target = canonicalRepeatedText(segment.text)
    guard !target.text.isEmpty else { return [] }

    var seen = Set([segment.id])
    var seenIntervals = Set([evidenceInterval(for: segment)])
    return candidates.filter { candidate in
      guard candidate.language == segment.language, isReliable(candidate),
        seen.insert(candidate.id).inserted,
        seenIntervals.insert(evidenceInterval(for: candidate)).inserted
      else {
        return false
      }
      return canonicalRepeatedText(candidate.text) == target
    }
  }

  private func canonicalRepeatedText(_ text: String) -> RepeatedEvidenceKey {
    RepeatedEvidenceKey(
      text: canonicalVisibleText(text),
      isQuestion: isExplicitQuestion(text)
    )
  }

  private func isReliable(_ segment: TranscriptSegment) -> Bool {
    segment.confidence.isFinite && (0.5...1).contains(segment.confidence)
      && segment.startTime.isFinite && segment.endTime.isFinite
      && segment.startTime >= 0 && segment.endTime >= segment.startTime
  }

  private func evidenceInterval(for segment: TranscriptSegment) -> EvidenceInterval {
    EvidenceInterval(startTime: segment.startTime, endTime: segment.endTime)
  }

  private func isExplicitQuestion(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if trimmed.hasSuffix("?") || trimmed.hasSuffix("？") { return true }

    let withoutTerminal = trimmed.trimmingCharacters(
      in: CharacterSet(charactersIn: "。．.!！")
    )
    let normalized = TextFeatures.normalize(withoutTerminal)
    if ["ですか", "ますか", "でしょうか", "なのですか", "なのか"].contains(where: {
      normalized.hasSuffix($0)
    }) {
      return true
    }
    if normalized.hasSuffix("か") || normalized.hasSuffix("かね")
      || normalized.hasSuffix("かしら") || normalized.hasSuffix("だろう")
      || normalized.hasSuffix("でしょう")
    {
      return true
    }
    if !regexRanges(
      #"(?:何|なに|誰|どこ|いつ|なぜ|どのように)(?:です|なの)?か$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"^(?:(?:what|why|how|when|where|which)\s+(?:do|does|did|is|are|was|were|can|could|should|would|will)\b|who\s+(?:is|are|was|were|does|did|can|could|should|would|will)\b|(?:do|does|did|is|are|was|were|can|could|should|would|will)\b)"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isDefinitionTerm(_ text: String) -> Bool {
    guard (2...42).contains(text.count), !text.contains("\n"), !text.contains("\r") else {
      return false
    }
    let forbidden = CharacterSet(charactersIn: "、，,;；:：。．!?！？")
    guard text.rangeOfCharacter(from: forbidden) == nil else { return false }

    let normalized = TextFeatures.normalize(text)
    let rejectedPrefixes = [
      "私は", "わたしは", "私が", "僕は", "わたくしは", "我々は", "われわれは",
      "i ", "we ", "he ", "she ", "they ", "this ", "that ", "it ",
    ]
    let rejectedWholeTerms = [
      "私", "わたし", "僕", "彼", "彼女", "これ", "それ", "あれ", "ここ", "そこ", "あそこ",
      "i", "we", "he", "she", "they", "this", "that", "it",
    ]
    return !rejectedPrefixes.contains(where: { normalized.hasPrefix($0) })
      && !rejectedWholeTerms.contains(normalized)
  }

  private func isDefinitionAnswer(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    let rejectedJapanesePrefixes = [
      "何", "なに", "どの", "どれ", "どう", "誰", "だれ", "いつ", "なぜ",
      "限り", "言え", "いえ", "違", "異な",
    ]
    guard !rejectedJapanesePrefixes.contains(where: { normalized.hasPrefix($0) }) else {
      return false
    }
    return regexRanges(
      #"^(?:what|which|who|where|when|why|how)\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isGrounded(term: String, on slide: SlideContext) -> Bool {
    let normalizedTerm = normalizedGroundingText(term)
    guard !normalizedTerm.isEmpty else { return false }
    let sources = [slide.title] + slide.textBlocks.map(\.text) + [slide.speakerNotes]
    return sources.contains { source in
      containsGroundedTerm(normalizedTerm, in: normalizedGroundingText(source))
    }
  }

  private func normalizedGroundingText(_ text: String) -> String {
    text
      .precomposedStringWithCanonicalMapping
      .folding(
        options: [.caseInsensitive, .widthInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func containsGroundedTerm(_ term: String, in source: String) -> Bool {
    var searchStart = source.startIndex
    while searchStart < source.endIndex,
      let range = source.range(of: term, range: searchStart..<source.endIndex)
    {
      if hasValidASCIIBoundary(before: range.lowerBound, in: source)
        && hasValidASCIIBoundary(after: range.upperBound, in: source)
      {
        return true
      }
      searchStart = range.upperBound
    }
    return false
  }

  private func hasValidASCIIBoundary(before index: String.Index, in text: String) -> Bool {
    guard index > text.startIndex else { return true }
    return !isASCIIWordCharacter(text[text.index(before: index)])
  }

  private func hasValidASCIIBoundary(after index: String.Index, in text: String) -> Bool {
    guard index < text.endIndex else { return true }
    return !isASCIIWordCharacter(text[index])
  }

  private func isASCIIWordCharacter(_ character: Character) -> Bool {
    character.unicodeScalars.allSatisfy { scalar in
      (0x30...0x39).contains(scalar.value)
        || (0x41...0x5A).contains(scalar.value)
        || (0x61...0x7A).contains(scalar.value)
        || scalar.value == 0x5F
    }
  }

  private func isSafeStructuredUtterance(_ text: String) -> Bool {
    guard !containsUnsafeQuotationMark(in: text) else { return false }

    let normalized = TextFeatures.normalize(text)
    let japaneseMetalinguisticCues = ["接続詞", "という語", "という表現"]
    guard !japaneseMetalinguisticCues.contains(where: normalized.contains) else { return false }
    return regexRanges(
      #"\b(?:word|phrase|term|connector|conjunction)\b|\b(?:use|say|write|pronounce|define|explain)\s+(?:the\s+)?(?:word\s+)?['\"]?(?:because|therefore|whereas)['\"]?\b|['\"]\s*(?:because|therefore|whereas)\s*['\"]"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isSafeAutomaticKeywordAssertion(_ text: String) -> Bool {
    let assertion = trimBoardItem(text)
    guard !isExplicitQuestion(text), isSingleSubstantiveClause(assertion),
      isSafeStructuredUtterance(text)
    else {
      return false
    }
    return !ImportanceScorer.containsExplicitImportanceCue(text)
  }

  private func containsUnsafeQuotationMark(in text: String) -> Bool {
    let unconditionalQuotationMarks = CharacterSet(charactersIn: "\"“”‘「」『』")
    guard text.rangeOfCharacter(from: unconditionalQuotationMarks) == nil else { return true }

    let characters = Array(text)
    for index in characters.indices where "'’".contains(characters[index]) {
      guard index > characters.startIndex else { return true }
      let nextIndex = characters.index(after: index)
      guard nextIndex < characters.endIndex else { return true }
      let previousIndex = characters.index(before: index)
      guard characters[previousIndex].isLetter else { return true }
      if characters[nextIndex].isLetter {
        continue
      }
      if characters[nextIndex] == "," || characters[nextIndex] == "，" {
        continue
      }
      guard characters[nextIndex].isWhitespace,
        characters[nextIndex...].first(where: { !$0.isWhitespace })?.isLetter == true
      else {
        return true
      }
    }
    return false
  }

  private func isSingleSubstantiveClause(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count >= 2 else { return false }
    let internalBoundaries = CharacterSet(charactersIn: "。．.!！?？;；")
    return trimmed.rangeOfCharacter(from: internalBoundaries) == nil
  }

  private func startsAtEnumerationBoundary(
    _ range: Range<String.Index>,
    in text: String
  ) -> Bool {
    let prefix = text[..<range.lowerBound]
    guard let previous = prefix.last(where: { !$0.isWhitespace }) else { return true }
    let boundaries = CharacterSet(charactersIn: "。．.!！?？、，,;；:：")
    return previous.unicodeScalars.allSatisfy(boundaries.contains)
  }

  private func regexRanges(
    _ pattern: String,
    in text: String,
    caseInsensitive: Bool = false
  ) -> [Range<String.Index>] {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return []
    }
    let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.matches(in: text, range: searchRange).compactMap {
      Range($0.range, in: text)
    }
  }

  private func nonoverlapping(_ ranges: [Range<String.Index>]) -> Bool {
    guard ranges.count > 1 else { return true }
    let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
    return zip(sorted, sorted.dropFirst()).allSatisfy { pair in
      pair.0.upperBound <= pair.1.lowerBound
    }
  }

  private func split(
    _ text: String,
    at ranges: [Range<String.Index>]
  ) -> [String] {
    let sorted = ranges.sorted { $0.lowerBound < $1.lowerBound }
    guard nonoverlapping(sorted) else { return [text] }

    var components: [String] = []
    var start = text.startIndex
    for range in sorted {
      components.append(String(text[start..<range.lowerBound]))
      start = range.upperBound
    }
    components.append(String(text[start...]))
    return components
  }

  private func trimDefinitionTitle(_ text: String) -> String {
    trim(
      text,
      leading: [],
      trailing: CharacterSet(charactersIn: "、，,;；:：")
    )
  }

  private func trimBoardItem(_ text: String) -> String {
    trim(
      text,
      leading: CharacterSet(charactersIn: "、，,;；:："),
      trailing: CharacterSet(charactersIn: "、，,;；:：。．.!！?？")
    )
  }

  private func trim(
    _ text: String,
    leading: CharacterSet,
    trailing: CharacterSet
  ) -> String {
    var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
    while let first = value.unicodeScalars.first, leading.contains(first) {
      value.removeFirst()
      value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    while let last = value.unicodeScalars.last, trailing.contains(last) {
      value.removeLast()
      value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return value
  }

  private func isPublic(_ state: BoardIntentState) -> Bool {
    state == .confirmed || state == .pinned
  }

  private func hasSameVisibleContent(_ lhs: BoardIntent, _ rhs: BoardIntent) -> Bool {
    lhs.kind == rhs.kind
      && canonicalVisibleText(lhs.title) == canonicalVisibleText(rhs.title)
      && lhs.items.map(canonicalVisibleText) == rhs.items.map(canonicalVisibleText)
  }

  private func canonicalVisibleText(_ text: String) -> String {
    let folded = text.folding(
      options: [.caseInsensitive, .widthInsensitive],
      locale: Locale(identifier: "en_US_POSIX")
    )
    let collapsed =
      folded
      .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return trim(
      collapsed,
      leading: [],
      trailing: CharacterSet(charactersIn: "。．.!！?？")
    )
  }

  private func splitDefinition(_ text: String) -> (title: String?, items: [String]) {
    let cues = ["とは", "means", "is defined as", "refers to", "すなわち", "in other words"]
    let boundaryCharacters = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
    for cue in cues {
      if let range = text.range(of: cue, options: [.caseInsensitive, .diacriticInsensitive]) {
        let lhs = text[..<range.lowerBound].trimmingCharacters(in: boundaryCharacters)
        let rhs = text[range.upperBound...].trimmingCharacters(in: boundaryCharacters)
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
