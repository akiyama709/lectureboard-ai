import Foundation

public struct ContextualBoardEngine: Sendable {
  private static let automaticKeywordConfirmationThreshold = 0.66
  private static let groundedAssertionConfidenceThreshold = 0.80
  // A single bounded Speech-provider cycle may finalize several independently safe importance
  // sentences. This cap applies only to those embedded public units; ordinary candidates retain
  // `maximumProposalsPerPass`.
  private static let maximumEmbeddedImportanceProposalsPerPass = 8
  private struct ExplicitBoardContent {
    var kind: BoardIntentKind
    var title: String?
    var items: [String]
    var isImportanceStatement = false
  }

  private struct RankedCandidate {
    var sourceIndex: Int
    var unitIndex: Int
    var intent: BoardIntent
    var isGroundedAssertionApproximation: Bool
    var isEmbeddedExplicitImportance = false
  }

  private struct IntentCandidate {
    var intent: BoardIntent
    var isGroundedAssertionApproximation: Bool
  }

  private enum ImportanceCuePlacement {
    case prefix
    case suffix
  }

  private struct ImportanceCueMatch {
    var range: Range<String.Index>
    var placement: ImportanceCuePlacement
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

  /// Returns whether provisional work derived from `previousText` may survive a cumulative speech
  /// hypothesis update to `currentText`.
  ///
  /// Replacement text always invalidates provisional work. An append-only update is retained only
  /// when the complete cumulative frame still passes the global semantic vetoes and the appended
  /// continuation is neither reported speech nor an unsafe quotation. Benign presentation
  /// logistics may follow an importance statement without invalidating it.
  public func canRetainProvisionalBoardWork(
    previousText: String,
    currentText: String
  ) -> Bool {
    guard canonicalVisibleText(currentText) != canonicalVisibleText(previousText) else {
      return isSafeEmbeddedImportanceFrame(currentText)
    }
    guard currentText.hasPrefix(previousText), isSafeEmbeddedImportanceFrame(currentText) else {
      return false
    }
    let continuation = String(currentText.dropFirst(previousText.count))
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !continuation.isEmpty else { return true }
    return isSafeLogisticsUnit(continuation)
      || (!isReportedSpeech(continuation) && !isFramedAsQuotationOrReading(continuation))
  }

  /// Identifies transcript hypotheses that should receive priority in the small queue retained
  /// while current slide analysis is unavailable. This is only a retention hint: ordinary board
  /// admission still runs later with the complete visual context and all fail-closed checks.
  public func shouldPrioritizePendingAnalysis(_ segment: TranscriptSegment) -> Bool {
    guard segment.isFinal else { return false }
    if ExplicitBoardRequestParser.requestedContent(
      in: segment.text,
      language: segment.language
    ) != nil {
      return isValidExplicitEvidence(segment)
    }
    guard isValidImportanceEvidence(segment),
      isSafeEmbeddedImportanceFrame(segment.text),
      !isReportedSpeech(segment.text),
      !isFramedAsQuotationOrReading(segment.text)
    else { return false }

    let units = importanceUnits(in: segment.text)
    guard let firstImportanceIndex = units.firstIndex(where: containsRecognizedImportanceCue) else {
      return false
    }
    for (unitIndex, unit) in units.enumerated() {
      if containsRecognizedImportanceCue(unit) {
        guard explicitImportanceBody(in: unit) != nil else { return false }
        continue
      }
      if isSafeLogisticsUnit(unit) { continue }
      if unitIndex < firstImportanceIndex, isSafeLeadingContextQuestion(unit) { continue }
      guard isSafeEmbeddedContextUnit(unit) else { return false }
    }
    return true
  }

  /// Returns whether this observation explicitly corrects or retracts immediately preceding
  /// speech. Callers may use it only across an adjacent provider-cycle boundary; it is not board
  /// admission evidence by itself.
  public func invalidatesImmediatelyPrecedingBoardWork(_ segment: TranscriptSegment) -> Bool {
    isCorrectionOrRetraction(segment.text)
  }

  /// Bounds cross-cycle retraction to an immediately preceding utterance that consisted of one
  /// safe importance statement. Multi-unit cycles are intentionally left stable because a later
  /// correction may refer only to an unboarded trailing clause.
  public func canRetractAcrossProviderCycle(
    previousText: String,
    correction: TranscriptSegment
  ) -> Bool {
    guard correction.isFinal,
      isValidExplicitEvidence(correction),
      isSafeCrossCycleCorrectionFrame(correction.text)
    else { return false }
    return sentenceUnits(in: previousText).count == 1
  }

  /// Returns only the independent importance statement that follows a cross-cycle correction.
  /// Ordinary proposal evaluation keeps rejecting the original whole correction frame. The caller
  /// may use this replacement only after ``canRetractAcrossProviderCycle(previousText:correction:)``
  /// succeeds and the immediately preceding board work has actually been removed.
  public func replacementSegmentAfterCrossCycleRetraction(
    _ correction: TranscriptSegment
  ) -> TranscriptSegment? {
    guard correction.isFinal,
      isValidExplicitEvidence(correction),
      isSafeCrossCycleCorrectionFrame(correction.text)
    else { return nil }
    let units = sentenceUnits(in: correction.text)
    guard
      let correctionIndex = units.firstIndex(where: isCorrectionOrRetraction),
      correctionIndex < units.index(before: units.endIndex)
    else { return nil }
    let replacementText = units[units.index(after: correctionIndex)...]
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard containsRecognizedImportanceCue(replacementText),
      isSafeEmbeddedImportanceFrame(replacementText),
      !isReportedSpeech(replacementText),
      !isLogisticsOrMetalinguistic(replacementText)
    else { return nil }

    return TranscriptSegment(
      id: correction.id,
      text: replacementText,
      startTime: correction.startTime,
      endTime: correction.endTime,
      language: correction.language,
      confidence: correction.confidence,
      isFinal: true,
      emphasis: correction.emphasis
    )
  }

  /// A provider rollover is not a semantic boundary. Destructive cross-cycle reconciliation is
  /// therefore permitted only when the correction itself is the first independent unit and the
  /// complete cumulative frame contains no quoted, reported, uncertain, interrogative, or
  /// presentation-logistics context. This prevents a correction token inside material being read
  /// or discussed from retracting the lecturer's own preceding board work.
  private func isSafeCrossCycleCorrectionFrame(_ text: String) -> Bool {
    let units = sentenceUnits(in: text)
    guard let correctionUnit = units.first,
      isAffirmativeStandaloneCrossCycleCorrectionUnit(correctionUnit),
      !isNegatedImportanceBody(crossCycleCorrectionPropositionText(text)),
      !containsUnsafeQuotationMark(in: text),
      !hasUnsafeMetalinguisticStructure(text),
      !isReportedSpeech(text),
      !isFramedAsQuotationOrReading(text),
      !isUncertainImportanceBody(text),
      !isExplicitQuestion(text),
      !isTagQuestion(text),
      !units.contains(where: isLogisticsOrMetalinguistic)
    else { return false }

    return units.allSatisfy { unit in
      !isNegatedImportanceBody(crossCycleCorrectionPropositionText(unit))
        && !containsUnsafeQuotationMark(in: unit)
        && !hasUnsafeMetalinguisticStructure(unit)
        && !isReportedSpeech(unit)
        && !isFramedAsQuotationOrReading(unit)
        && !isUncertainImportanceBody(unit)
        && !isExplicitQuestion(unit)
        && !isTagQuestion(unit)
    }
  }

  /// Destructive reconciliation across provider cycles deliberately uses a narrow allowlist.
  /// The broader correction detector remains useful inside one cumulative hypothesis, but a
  /// token such as "wrong" may otherwise occur in a quotation, negation, or discussion of words.
  private func isAffirmativeStandaloneCrossCycleCorrectionUnit(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    if !regexRanges(
      #"^(?:(?:ええと|あの|まあ)[、，,\s]*)?(?:いや|いえ)[、，,\s]*(?:違います|(?:(?:今のは|それは|これは)?(?:間違い|誤り)です)|そうではありません)\s*[。．.!！]?$|^(?:(?:今のは|それは|これは)?(?:間違い|誤り)です|(?:撤回|訂正)(?:します|しました))\s*[。．.!！]?$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"^\s*no\s*[,;:]\s*(?:that|this|it)(?:\s+(?:question|statement|answer|point|claim|explanation))?(?:\s+(?:is|was)|['’]s)\s+(?:wrong|false|mistaken)\s*[.!]?\s*$|^\s*(?:i|we)\s+(?:retract|withdraw)\s+(?:that|this|it|the\s+(?:previous|last)\s+statement)\s*[.!]?\s*$"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  /// Removes only a leading hesitation and correction discourse marker. Negation is then checked
  /// on the proposition itself, so affirmative English "No" remains usable while "wasn't wrong"
  /// and Japanese "違わない" are rejected.
  private func crossCycleCorrectionPropositionText(_ text: String) -> String {
    text.replacingOccurrences(
      of: #"^\s*(?:(?:ええと|あの|まあ)[、，,\s]*)?(?:(?:いや|いえ)[、，,\s]*|no\s*[,;:]\s*)"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
  }

  public func propose(
    slide: SlideContext,
    recentSegments: [TranscriptSegment],
    existingIntents: [BoardIntent] = [],
    candidateSourceSegmentIDs: Set<UUID>? = nil
  ) -> [BoardIntent] {
    guard maximumProposalsPerPass > 0 else { return [] }
    let latestIndexBySource = recentSegments.enumerated().reduce(into: [UUID: Int]()) {
      latestIndices, indexedSegment in
      latestIndices[indexedSegment.element.id] = indexedSegment.offset
    }
    let finalizedSegments: [TranscriptSegment] = recentSegments.enumerated().compactMap {
      index, segment in
      guard segment.isFinal, latestIndexBySource[segment.id] == index else { return nil }
      return segment
    }
    let candidateSegments = finalizedSegments.enumerated().filter { _, segment in
      candidateSourceSegmentIDs?.contains(segment.id) ?? true
    }
    let candidates =
      candidateSegments
      .flatMap { sourceIndex, segment -> [RankedCandidate] in
        let otherFinalizedSegments = finalizedSegments.filter { $0.id != segment.id }
        let wholeCandidate = candidateIntent(
          for: segment,
          on: slide,
          among: otherFinalizedSegments,
          allowsExplicitBoardRequest: true,
          allowsGroundedAssertionApproximation: true
        )
        let hasMultipleImportanceUnits =
          importanceUnits(in: segment.text).filter(containsRecognizedImportanceCue).count > 1
        if !hasMultipleImportanceUnits,
          let wholeCandidate,
          isPublic(wholeCandidate.intent.state)
        {
          if shouldAdmit(wholeCandidate.intent, among: existingIntents) {
            return [
              RankedCandidate(
                sourceIndex: sourceIndex,
                unitIndex: 0,
                intent: wholeCandidate.intent,
                isGroundedAssertionApproximation:
                  wholeCandidate.isGroundedAssertionApproximation
              )
            ]
          }
        }

        let embeddedImportance = embeddedImportanceIntents(
          for: segment,
          on: slide,
          among: otherFinalizedSegments
        )
        if !embeddedImportance.isEmpty {
          let allowsSameSourcePublicExtension = isAppendOnlySameSourceExtension(
            currentIntents: embeddedImportance.map(\.intent),
            currentSegment: segment,
            existingIntents: existingIntents
          )
          return embeddedImportance.compactMap { embedded in
            guard
              shouldAdmit(
                embedded.intent,
                among: existingIntents,
                allowsSameSourcePublicExtension: allowsSameSourcePublicExtension
              )
            else { return nil }
            return RankedCandidate(
              sourceIndex: sourceIndex,
              unitIndex: embedded.unitIndex,
              intent: embedded.intent,
              isGroundedAssertionApproximation: false,
              isEmbeddedExplicitImportance: true
            )
          }
        }

        if let embeddedGroundedAssertion = embeddedGroundedAssertionIntent(
          for: segment,
          on: slide,
          among: otherFinalizedSegments
        ),
          shouldAdmit(embeddedGroundedAssertion.intent, among: existingIntents)
        {
          return [
            RankedCandidate(
              sourceIndex: sourceIndex,
              unitIndex: embeddedGroundedAssertion.unitIndex,
              intent: embeddedGroundedAssertion.intent,
              isGroundedAssertionApproximation: true
            )
          ]
        }

        guard let wholeCandidate,
          shouldAdmit(wholeCandidate.intent, among: existingIntents)
        else {
          return []
        }
        return [
          RankedCandidate(
            sourceIndex: sourceIndex,
            unitIndex: 0,
            intent: wholeCandidate.intent,
            isGroundedAssertionApproximation:
              wholeCandidate.isGroundedAssertionApproximation
          )
        ]
      }
      .sorted {
        let lhsIsPublic = isPublic($0.intent.state)
        let rhsIsPublic = isPublic($1.intent.state)
        if lhsIsPublic != rhsIsPublic {
          return lhsIsPublic
        }
        if $0.isGroundedAssertionApproximation != $1.isGroundedAssertionApproximation {
          return !$0.isGroundedAssertionApproximation
        }
        if $0.sourceIndex == $1.sourceIndex, $0.unitIndex != $1.unitIndex {
          return $0.unitIndex < $1.unitIndex
        }
        if $0.intent.importance != $1.intent.importance {
          return $0.intent.importance > $1.intent.importance
        }
        if $0.intent.confidence != $1.intent.confidence {
          return $0.intent.confidence > $1.intent.confidence
        }
        if $0.sourceIndex != $1.sourceIndex {
          return $0.sourceIndex < $1.sourceIndex
        }
        return $0.unitIndex < $1.unitIndex
      }

    var accepted: [BoardIntent] = []
    var acceptedGroundedAssertionApproximation = false
    var acceptedEmbeddedImportanceCount = 0
    for candidate in candidates {
      let proposalLimit =
        candidate.isEmbeddedExplicitImportance
        ? max(maximumProposalsPerPass, Self.maximumEmbeddedImportanceProposalsPerPass)
        : maximumProposalsPerPass
      guard accepted.count < proposalLimit else { continue }
      if candidate.isEmbeddedExplicitImportance {
        guard
          acceptedEmbeddedImportanceCount < Self.maximumEmbeddedImportanceProposalsPerPass
        else { continue }
      }
      if candidate.isGroundedAssertionApproximation {
        guard !acceptedGroundedAssertionApproximation else { continue }
      }
      if isPublic(candidate.intent.state),
        accepted.contains(where: {
          isPublic($0.state) && hasSameVisibleContent($0, candidate.intent)
        })
      {
        continue
      }
      accepted.append(candidate.intent)
      if candidate.isEmbeddedExplicitImportance {
        acceptedEmbeddedImportanceCount += 1
      }
      if candidate.isGroundedAssertionApproximation {
        acceptedGroundedAssertionApproximation = true
      }
    }
    return accepted
  }

  private func candidateIntent(
    for segment: TranscriptSegment,
    on slide: SlideContext,
    among otherFinalizedSegments: [TranscriptSegment],
    allowsExplicitBoardRequest: Bool,
    allowsGroundedAssertionApproximation: Bool
  ) -> IntentCandidate? {
    let explicitBoardRequest =
      allowsExplicitBoardRequest
      ? ExplicitBoardRequestParser.requestedContent(
        in: segment.text,
        language: segment.language
      ) : nil
    let explicitContent = explicitlyStructuredContent(segment.text, on: slide)
    let matchingRepeatedEvidence = repeatedEvidence(
      for: segment,
      among: otherFinalizedSegments
    )
    let score = scorer.score(
      segment: segment,
      slide: slide,
      recentSegments: otherFinalizedSegments
    )
    let hasValidExplicitEvidence =
      (explicitBoardRequest != nil && isValidExplicitEvidence(segment))
      || (explicitContent?.isImportanceStatement == true
        && isValidImportanceEvidence(segment))
    let hasSafeSlideGroundedAssertion =
      allowsGroundedAssertionApproximation && isSafeSlideGroundedAssertion(segment, on: slide)
    guard hasValidExplicitEvidence || hasSafeSlideGroundedAssertion || scorer.shouldPropose(score)
    else {
      return nil
    }
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
      repeatedEvidence: matchingRepeatedEvidence,
      explicitBoardRequest: explicitBoardRequest,
      explicitContent: explicitContent,
      hasSafeSlideGroundedAssertion: hasSafeSlideGroundedAssertion
    )
    return IntentCandidate(
      intent: intent,
      isGroundedAssertionApproximation: hasSafeSlideGroundedAssertion
    )
  }

  private func embeddedImportanceIntents(
    for segment: TranscriptSegment,
    on slide: SlideContext,
    among otherFinalizedSegments: [TranscriptSegment]
  ) -> [(unitIndex: Int, intent: BoardIntent)] {
    guard isValidImportanceEvidence(segment),
      isSafeEmbeddedImportanceFrame(segment.text)
    else {
      return []
    }

    let units = importanceUnits(in: segment.text)
    guard units.count > 1 else { return [] }
    guard let firstImportanceIndex = units.firstIndex(where: containsRecognizedImportanceCue) else {
      return []
    }
    var importanceUnits: [(unitIndex: Int, intent: BoardIntent)] = []
    for (unitIndex, text) in units.enumerated() {
      guard containsRecognizedImportanceCue(text) else {
        if isSafeLogisticsUnit(text) {
          continue
        }
        if unitIndex < firstImportanceIndex,
          isSafeLeadingContextQuestion(text)
        {
          continue
        }
        guard isSafeEmbeddedContextUnit(text) else { return [] }
        continue
      }

      let unit = TranscriptSegment(
        id: segment.id,
        text: text,
        startTime: segment.startTime,
        endTime: segment.endTime,
        language: segment.language,
        confidence: segment.confidence,
        isFinal: true,
        emphasis: segment.emphasis
      )
      guard
        explicitlyStructuredContent(text, on: slide)?.isImportanceStatement == true,
        let candidate = candidateIntent(
          for: unit,
          on: slide,
          among: otherFinalizedSegments,
          allowsExplicitBoardRequest: false,
          allowsGroundedAssertionApproximation: false
        ),
        isPublic(candidate.intent.state)
      else {
        return []
      }
      importanceUnits.append((unitIndex: unitIndex, intent: candidate.intent))
    }
    return importanceUnits
  }

  private func embeddedGroundedAssertionIntent(
    for segment: TranscriptSegment,
    on slide: SlideContext,
    among otherFinalizedSegments: [TranscriptSegment]
  ) -> (unitIndex: Int, intent: BoardIntent)? {
    guard segment.isFinal, isValidExplicitEvidence(segment),
      segment.confidence >= Self.groundedAssertionConfidenceThreshold,
      !containsRecognizedImportanceCue(segment.text),
      isSafePublicSemanticFrame(segment.text)
    else {
      return nil
    }

    let units = sentenceUnits(in: segment.text)
    guard units.count > 1, units.allSatisfy({ isSafePublicSemanticFrame($0) }) else { return nil }

    for (unitIndex, text) in units.enumerated() {
      let unit = TranscriptSegment(
        id: segment.id,
        text: text,
        startTime: segment.startTime,
        endTime: segment.endTime,
        language: segment.language,
        confidence: segment.confidence,
        isFinal: true,
        emphasis: segment.emphasis
      )
      guard isSafeSlideGroundedAssertion(unit, on: slide),
        let candidate = candidateIntent(
          for: unit,
          on: slide,
          among: otherFinalizedSegments,
          allowsExplicitBoardRequest: false,
          allowsGroundedAssertionApproximation: true
        ),
        candidate.isGroundedAssertionApproximation,
        isPublic(candidate.intent.state)
      else {
        continue
      }
      return (unitIndex: unitIndex, intent: candidate.intent)
    }
    return nil
  }

  private func classify(
    segment: TranscriptSegment,
    slide: SlideContext,
    score: ImportanceScore,
    reliableRepeatedScore: ImportanceScore,
    repeatedEvidence: [TranscriptSegment],
    explicitBoardRequest: String?,
    explicitContent: ExplicitBoardContent?,
    hasSafeSlideGroundedAssertion: Bool
  ) -> BoardIntent {
    let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
    let inferredKind = classifyKind(text)
    let inferredContent = groundedContent(for: inferredKind, text: text)
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

    if let explicitBoardRequest {
      kind = .keyword
      content = (nil, [explicitBoardRequest])
      state = isValidExplicitEvidence(segment) ? .confirmed : .proposed
      usesRepeatedEvidence = false
    } else if let explicitContent {
      kind = explicitContent.kind
      content = (explicitContent.title, explicitContent.items)
      let isSemanticallySafe =
        explicitContent.isImportanceStatement
        || isSafePublicSemanticFrame(text)
      state =
        isSemanticallySafe
          && (hasReliableEvidence
            || (explicitContent.isImportanceStatement && isValidImportanceEvidence(segment)))
        ? .confirmed : .proposed
      usesRepeatedEvidence = false
    } else if hasSafeSlideGroundedAssertion {
      // This narrow path is a conservative relevance proxy. Slide grounding and recognition
      // confidence do not prove pedagogical importance; they only admit a safe, relevant claim
      // when no explicit importance cue was spoken.
      kind = .keyword
      content = (nil, [bounded(trimBoardItem(text))])
      state = .confirmed
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

    if containsRecognizedImportanceCue(text) {
      guard let importanceBody = explicitImportanceBody(in: text) else { return nil }
      let structuredCandidates = [
        explicitDefinition(in: importanceBody, on: slide),
        explicitCausalChain(in: importanceBody),
        explicitComparison(in: importanceBody),
        explicitList(in: importanceBody),
      ].compactMap { $0 }
      if structuredCandidates.count == 1 {
        var content = structuredCandidates[0]
        guard content.items.allSatisfy(isSafeImportanceItem) else { return nil }
        content.isImportanceStatement = true
        return content
      }
      guard structuredCandidates.isEmpty, classifyKind(importanceBody) == .keyword,
        isSingleSubstantiveClause(importanceBody),
        isCompleteSafeImportanceBody(importanceBody)
      else {
        return nil
      }
      return ExplicitBoardContent(
        kind: .keyword,
        title: nil,
        items: [bounded(importanceBody)],
        isImportanceStatement: true
      )
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
    let prefixMatches =
      ImportanceScorer.importancePrefixCuePatterns.flatMap { pattern in
        regexRanges(pattern, in: text, caseInsensitive: true).map {
          ImportanceCueMatch(range: $0, placement: .prefix)
        }
      }
    let suffixMatches =
      ImportanceScorer.importanceSuffixCuePatterns.flatMap { pattern in
        regexRanges(pattern, in: text, caseInsensitive: true).map {
          ImportanceCueMatch(range: $0, placement: .suffix)
        }
      }

    let rawBody: String
    let usesEnclosingCues: Bool
    if prefixMatches.count == 1, suffixMatches.count == 1,
      let prefix = prefixMatches.first, let suffix = suffixMatches.first,
      prefix.range.upperBound <= suffix.range.lowerBound
    {
      rawBody = String(text[prefix.range.upperBound..<suffix.range.lowerBound])
      usesEnclosingCues = true
    } else {
      let matches = prefixMatches + suffixMatches
      guard matches.count == 1, let cue = matches.first else { return nil }
      switch cue.placement {
      case .prefix:
        rawBody = String(text[cue.range.upperBound...])
      case .suffix:
        rawBody = String(text[..<cue.range.lowerBound])
      }
      usesEnclosingCues = false
    }
    var body = trimBoardItem(rawBody)
    if usesEnclosingCues, body.lowercased().hasPrefix("that ") {
      body.removeFirst("that ".count)
    }
    guard !body.isEmpty,
      isSafePublicSemanticFrame(text, permitsExplicitImportanceSyntax: true),
      isSafePublicSemanticFrame(body)
    else {
      return nil
    }
    return body
  }

  private func containsRecognizedImportanceCue(_ text: String) -> Bool {
    ImportanceScorer.containsExplicitImportanceCue(text)
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
      let interval = evidenceInterval(for: candidate)
      guard candidate.language == segment.language, isReliable(candidate),
        !seen.contains(candidate.id), !seenIntervals.contains(interval),
        canonicalRepeatedText(candidate.text) == target
      else {
        return false
      }
      seen.insert(candidate.id)
      seenIntervals.insert(interval)
      return true
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

  private func isValidExplicitEvidence(_ segment: TranscriptSegment) -> Bool {
    segment.confidence.isFinite && (0...1).contains(segment.confidence)
      && segment.emphasis.isFinite && (0...1).contains(segment.emphasis)
      && segment.startTime.isFinite && segment.endTime.isFinite
      && segment.startTime >= 0 && segment.endTime >= segment.startTime
  }

  private func isValidImportanceEvidence(_ segment: TranscriptSegment) -> Bool {
    // Apple Speech can return an exact zero for an otherwise correctly transcribed final result.
    // An explicit importance cue is lecturer-supplied semantic evidence, so accept the provider's
    // full documented range here only after the question, negation, uncertainty, quotation,
    // reported-speech, and instruction checks above have all passed. Ordinary automatic content
    // still uses `isReliable(_:)` and therefore retains its 0.5 confidence floor.
    isValidExplicitEvidence(segment)
  }

  private func isSafeSlideGroundedAssertion(
    _ segment: TranscriptSegment,
    on slide: SlideContext
  ) -> Bool {
    let assertion = trimBoardItem(segment.text)
    guard segment.isFinal, isValidExplicitEvidence(segment),
      segment.confidence >= Self.groundedAssertionConfidenceThreshold,
      !containsRecognizedImportanceCue(segment.text),
      !isExplicitQuestion(segment.text), !isBareInterrogative(segment.text),
      classifyKind(assertion) == .keyword,
      sentenceUnits(in: segment.text).count == 1,
      isSingleSubstantiveClause(assertion),
      isDeclarativeAssertion(assertion, language: segment.language),
      isSafePublicSemanticFrame(segment.text),
      hasDistinctiveSlideGrounding(assertion, on: slide),
      !isNearVerbatimSlideReading(assertion, on: slide)
    else {
      return false
    }
    return true
  }

  private func isDeclarativeAssertion(_ text: String, language: LanguageTag) -> Bool {
    let normalized = TextFeatures.normalize(trimBoardItem(text))
    let languageCode = language.rawValue.lowercased()
    if languageCode.hasPrefix("ja") {
      let semanticStem = normalized.replacingOccurrences(
        of: #"(?:です|でした|だ|だった|である)$"#,
        with: "",
        options: .regularExpression
      )
      guard groundingContentTokens(semanticStem).count >= 2 else { return false }
      return !regexRanges(
        #"(?:です|でした|ます|ました|ません|ませんでした|である|ではない|じゃない|だった|ではなかった|じゃなかった|する|した|している|していた|なる|なった|れる|れた|られる|られた|[うくぐすつぬぶむる])$"#,
        in: normalized
      ).isEmpty
    }
    guard languageCode.hasPrefix("en") else { return false }
    guard groundingContentTokens(normalized).count >= 2 else { return false }
    return !regexRanges(
      #"\b(?:am|is|are|was|were|do|does|did|has|have|had|can|could|will|would|shall|should|must)\b|\b(?:affect|become|change|connect|constrain|cause|decrease|depend|determine|develop|differ|emerge|enable|evolve|explain|imply|increase|influence|interact|matter|mean|produce|relate|remain|represent|require|reflect|shape|support|vary)(?:s|ed)?\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func hasDistinctiveSlideGrounding(_ assertion: String, on slide: SlideContext) -> Bool {
    let assertionTokens = groundingContentTokens(assertion)
    guard !assertionTokens.isEmpty else { return false }

    if !isGenericSlideTitle(slide.title) {
      let titleTokens = groundingContentTokens(slide.title)
      if !assertionTokens.intersection(titleTokens).isEmpty {
        return true
      }
    }

    return slide.textBlocks.contains { block in
      assertionTokens.intersection(groundingContentTokens(block.text)).count >= 2
    }
  }

  private func isNearVerbatimSlideReading(_ assertion: String, on slide: SlideContext) -> Bool {
    let assertionTokens = groundingContentTokens(assertion)
    guard !assertionTokens.isEmpty else { return true }

    return ([slide.title] + slide.textBlocks.map(\.text)).contains { source in
      let sourceTokens = groundingContentTokens(source)
      guard !sourceTokens.isEmpty else { return false }
      let intersection = assertionTokens.intersection(sourceTokens).count
      let assertionCoverage = Double(intersection) / Double(assertionTokens.count)
      let similarity = TextFeatures.jaccard(assertionTokens, sourceTokens)
      return assertionCoverage >= 0.85 || similarity >= 0.78
    }
  }

  private func groundingContentTokens(_ text: String) -> Set<String> {
    let englishFunctionWords: Set<String> = [
      "a", "an", "and", "are", "as", "at", "be", "been", "being", "but", "by", "can",
      "could", "did", "do", "does", "for", "from", "had", "has", "have", "he", "her",
      "here", "him", "his", "i", "in", "is", "it", "its", "may", "might", "must", "no",
      "not", "of", "on", "or", "our", "she", "should", "that", "the", "their", "them",
      "there", "these", "they", "this", "those", "to", "was", "we", "were", "will",
      "with", "would", "you", "your",
    ]
    return TextFeatures.tokens(text).subtracting(englishFunctionWords)
  }

  private func isGenericSlideTitle(_ title: String) -> Bool {
    let normalized = canonicalVisibleText(title)
    let genericTitles: Set<String> = [
      "agenda", "background", "conclusion", "contents", "discussion", "introduction",
      "method", "methods", "overview", "results", "slide", "summary", "title", "untitled",
      "はじめに", "まとめ", "スライド", "タイトル", "概要", "結論", "結果", "背景", "方法", "目次",
    ]
    return normalized.isEmpty || genericTitles.contains(normalized)
  }

  private func sentenceUnits(in text: String) -> [String] {
    var units: [String] = []
    text.enumerateSubstrings(
      in: text.startIndex..<text.endIndex,
      options: [.bySentences, .substringNotRequired]
    ) { _, range, _, _ in
      let unit = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
      if !unit.isEmpty {
        units.append(unit)
      }
    }
    return units
  }

  private func importanceUnits(in text: String) -> [String] {
    sentenceUnits(in: text).flatMap { sentence in
      let internalCueRanges = regexRanges(
        #"(?:重要なのは|重要な(?:点|こと)は|(?:大切|大事)な(?:点|こと)は|大切なのは|(?:要点|ポイント)は|一番伝えたい(?:の|こと)は|(?:the|a|an|our|my)\s+(?:(?:most\s+)?important|key|main|central)\s+(?:point|idea|thing|takeaway)(?:\s+here)?\s+is)"#,
        in: sentence,
        caseInsensitive: true
      )
      let splitIndices = internalCueRanges.map(\.lowerBound).filter { $0 != sentence.startIndex }
      guard !splitIndices.isEmpty else { return [sentence] }

      var units: [String] = []
      var start = sentence.startIndex
      for end in splitIndices + [sentence.endIndex] {
        let unit = String(sentence[start..<end])
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !unit.isEmpty {
          units.append(unit)
        }
        start = end
      }
      return units
    }
  }

  private func shouldAdmit(
    _ intent: BoardIntent,
    among existingIntents: [BoardIntent],
    allowsSameSourcePublicExtension: Bool = false
  ) -> Bool {
    if existingIntents.contains(where: { existing in
      isPublic(existing.state) && hasSameVisibleContent(existing, intent)
    }) {
      return false
    }

    let sourceIDs = Set(intent.sourceSegmentIDs)
    let sameSourceIntents = existingIntents.filter { existing in
      !sourceIDs.isDisjoint(with: existing.sourceSegmentIDs)
    }
    guard !sameSourceIntents.isEmpty else { return true }
    guard isPublic(intent.state) else { return false }
    if allowsSameSourcePublicExtension { return true }
    return !sameSourceIntents.contains { isPublic($0.state) }
  }

  private func isAppendOnlySameSourceExtension(
    currentIntents: [BoardIntent],
    currentSegment: TranscriptSegment,
    existingIntents: [BoardIntent]
  ) -> Bool {
    let existingPublicIntents = existingIntents.filter { intent in
      isPublic(intent.state) && intent.sourceSegmentIDs.contains(currentSegment.id)
    }
    guard !existingPublicIntents.isEmpty else { return false }

    let units = importanceUnits(in: currentSegment.text)
    guard let firstImportanceIndex = units.firstIndex(where: containsRecognizedImportanceCue) else {
      return false
    }
    let retainedLeadingAssertions = units.prefix(firstImportanceIndex).filter { unit in
      let item = trimBoardItem(unit)
      return !containsRecognizedImportanceCue(unit)
        && isSingleSubstantiveClause(item)
        && isDeclarativeAssertion(item, language: currentSegment.language)
        && isSafePublicSemanticFrame(unit)
    }

    return existingPublicIntents.allSatisfy { existing in
      currentIntents.contains { current in hasSameVisibleContent(existing, current) }
        || (existing.kind == .keyword && existing.items.count == 1
          && retainedLeadingAssertions.contains { unit in
            canonicalVisibleText(bounded(trimBoardItem(unit)))
              == canonicalVisibleText(existing.items[0])
          })
    }
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
    if ["ですか", "ますか", "でしょうか", "なのですか", "なのか", "かな", "でいい"].contains(where: {
      normalized.hasSuffix($0)
    }) {
      return true
    }
    if normalized.hasSuffix("なの") || normalized.hasSuffix("でしょ") { return true }
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

  private func isBareInterrogative(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    if normalized.contains("かどうか") { return true }
    let japanese = ["何", "なに", "誰", "だれ", "どこ", "いつ", "なぜ", "どう", "どのように"]
    if japanese.contains(normalized) { return true }
    if !regexRanges(
      #"^(?:何|なに|誰|だれ|どこ|いつ|なぜ|どう|どのように)(?:です|なの|だ)?$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"^(?:whether\b|(?:what|why|how|when|where|which|who)(?:\s+(?:exactly|specifically))?$)"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isNegatedImportanceBody(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    if !regexRanges(
      #"(?:では|じゃ)(?:ありません|ない|なかった|なく)|ではなく|違わない(?:です)?|(?:間違い|誤り)では(?:ありません|ない)|間違っていません"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"^(?:not|no)\b|^(?:(?:absolutely|definitely|certainly|clearly|simply|really|actually)\s+)+not\b|\b(?:is|are|was|were)\s+not\b|\b(?:isn|aren|wasn|weren)['’]?t\b|\b(?:that|this|it|he|she|there)['’]s\s+not\b|\b(?:they|we|you)['’]re\s+not\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isUncertainImportanceBody(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    let japaneseCues = [
      "不明", "不確か", "未確定", "誤認識", "分かりません", "わかりません", "かもしれません",
      "かもしれない", "と思います", "と思う", "と考えます", "と考える", "可能性があります",
      "可能性がある", "おそらく", "恐らく", "たぶん", "多分", "推測", "仮説", "と言われています",
      "と言われている", "と仮定します", "と仮定する", "ではなさそう", "じゃなさそう", "かは疑問",
      "怪しい", "断言できません", "断言できない", "仮に", "もし", "とします", "としましょう",
      "冗談です", "冗談ですが", "たとえ話です",
    ]
    if japaneseCues.contains(where: normalized.contains) { return true }
    if !regexRanges(
      #"(?:らしい|だそう|のよう)(?:です|だ|である)?\s*[。．.!！]?\s*$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"\b(?:uncertain|unclear|unknown|unsettled|unsure|maybe|perhaps|possibly|probably|likely|unlikely|allegedly|apparently|arguably|presumably|supposedly|reportedly|hardly|doubtful|hypothetically)\b|\banything\s+but\b|\bnot\s+(?:clear|certain|settled|known|convinced)\b|\b(?:i|we)\s+(?:think|believe|suppose|guess|doubt)\b|\bi\s+(?:am\s+)?not\s+convinced\b|\bi\s+question\s+whether\b|\b(?:may|might|could|would)\b|^\s*(?:if|suppose|assuming|assume)\b|\bfor\s+the\s+sake\s+of\s+argument\b|\b(?:just\s+kidding|i\s+am\s+joking|i['’]?m\s+joking)\b|\b(?:seems?|appears?|supposed)\s+(?:to\s+be\s+)?"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isImportanceInstruction(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    if hasUnsafeMetalinguisticStructure(text) {
      return true
    }
    if !regexRanges(
      #"(?:板書|書いて|描いて|表示して)[^。．.!！?？]{0,24}(?:ください|指示|命令|発話)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:と|という内容を)(?:繰り返す|復唱する|発話する|言う|述べる)こと(?:です|だ|である)?\s*[。．.!！]?\s*$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"^(?:please\s+)?(?:do\s+not\s+)?(?:write|put|draw|show|display|note|ignore|breathe)\b|^to\s+(?:write|put|draw|show|display|note|say|repeat|ignore|breathe)\b|\b(?:should|must|need\s+to|have\s+to)\s+(?:write|put|draw|show|display|note|say|repeat|ignore|breathe)\b|\b(?:word|phrase|sentence|command|instruction)\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isSafeImportanceItem(_ text: String) -> Bool {
    isCompleteSafeImportanceBody(text)
  }

  private func isReportedSpeech(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    if normalized.contains("によれば") || normalized.contains("によると")
      || normalized.contains("いわく") || normalized.contains("の見解では")
      || normalized.contains("ある説では") || normalized.contains("文献の主張")
      || normalized.contains("論文の主張")
    {
      return true
    }
    if !regexRanges(
      #"一般には[^。．.!！?？]{0,40}と(?:言われます|言われています|されています)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:と|って)[^。．.!！?？]{0,32}(?:言います|言いました|言っています|言われています|言われている|述べます|述べました|述べています|話します|話しました|発言します|発言しました|発話します|発話しました|説明します|説明しました|主張します|主張しました|指摘します|指摘しました|書きます|書きました|書かれています|されています|されている)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:先生|講師|著者|発表者|話者)[^。．.!！?？]{0,24}(?:による|の)(?:説明|発言|主張|指摘|報告)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:先生|講師|著者|発表者|話者|文献|論文|報告書|研究)(?:の(?:話|言葉|説明|報告|主張|見解)|という(?:話|説明))では"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"\S{1,24}(?:は|が)[^。．.!！?？]{1,48}(?:だ|です)?と(?:考えています|考えます|主張しています|主張します|述べています|述べます)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:先生|講師|著者|発表者|話者)が[^。．.!！?？]{0,16}(?:言います|言いました|述べます|述べました|説明します|説明しました|主張します|主張しました|指摘します|指摘しました)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:先生|講師|著者|発表者|話者)(?:は|が)[^。．.!！?？]{0,32}(?:(?:だ)?と(?:考えています|考えます|しています|おっしゃいました|おっしゃいます)|(?:言います|言いました|述べます|述べました|説明します|説明しました|主張します|主張しました|指摘します|指摘しました))"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"\baccording\s+to\b|\bin\s+(?:the\s+)?view\s+of\b|\bin\s+(?:the\s+)?(?:words?|account)\s+of\b|\bin\s+[a-z][a-z-]*['’]s\s+(?:view|words?)\b|\b[a-z][a-z-]*['’]s\s+(?:view|conclusion|claim|argument|account|words?)\b|\b[a-z][a-z-]*(?:\s+[a-z][a-z-]*){0,2}\s+(?:believe|believes|think|thinks|conclude|concludes|suggest|suggests|maintain|maintains|hold|holds|argue|argues|claim|claims)\b|\b[a-z][a-z-]*['’]s\s+(?:key|main|central|important)\s+(?:point|claim|conclusion|argument)\b|\bor\s+so\s+(?:i|we)\s+(?:was|were)\s+told\b|\b(?:is|are|was|were)\s+(?:said|stated|claimed|reported)\b|\b(?:say|says|said|state|states|stated|claim|claims|claimed|report|reports|reported|write|writes|wrote|quote|quotes|quoted|explain|explains|explained|argue|argues|argued|note|notes|noted)\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isFramedAsQuotationOrReading(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    let japaneseCues = [
      "引用します", "引用です", "引用して", "引用終わり", "読み上げます", "読み上げて", "復唱します",
      "復唱して", "スライドを読み", "スライドには書", "スライドに書", "スライドに記載",
    ]
    if japaneseCues.contains(where: normalized.contains) { return true }
    if !regexRanges(
      #"スライド[^。．.!！?？]{0,32}と(?:あります|ある|示されています|示されている)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"\b(?:quote|quoting|quoted|read(?:ing)?\s+(?:from\s+)?the\s+slide|(?:the\s+slide\s+(?:says|states|reads|shows|lists|notes)|as\s+the\s+slide\s+says)|repeat(?:ing)?\s+after)\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isTagQuestion(_ text: String) -> Bool {
    let normalized = canonicalVisibleText(text)
    if !regexRanges(
      #"(?:ですよね|ますよね|だよね|よね|でしょうね?|じゃないですか|ではないですか)$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"(?:,\s*|\s+)(?:right|correct|do\s+you\s+agree|isn['’]?t\s+it|aren['’]?t\s+(?:they|we|you)|doesn['’]?t\s+it|don['’]?t\s+(?:they|we|you)|won['’]?t\s+it|wouldn['’]?t\s+it)$"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isCorrectionOrRetraction(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    if normalized.contains("もとい") { return true }
    if !regexRanges(
      #"(?:^|[。．.!！?？])\s*(?:ただし[、，,\s]*)?(?:(?:今のは|それは|これは)?(?:間違い|誤り)です|違います|そうではありません|そうではない)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"[、，,;；:：—–]\s*(?:いや|いえ|正確には)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:^|[。．.!！?？])\s*(?:(?:いや|いえ)(?:[、，,;；:：\s]|$)|(?:やっぱり|正しくは)\s*\S+|(?:訂正|修正)(?:すると|します)?(?:[、，,;；:：\s]|$))"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:重要なのは|重要な(?:点|こと)は|要点は|ポイントは|肝は|核心は)[^。．.!！?？]{1,48}?\s*(?:いや|いえ|正確には)\s*\S+"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"(?:いや|いえ)[、，,\s]*(?:違|誤|間違|別|状況|むしろ|正確|そうでは)|(?:撤回|訂正)(?:します|しました|する)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"\bor\s+rather\b|(?:[—–]\s*|\b)no\s*[,;:]|[,;:—–]\s*actually\b|(?:^|[.?!])\s*(?:rather\b|correction\s*:)|\b(?:but\s+)?(?:actually|no)\b[^.?!]{0,24}\b(?:wrong|false|mistaken|retract|correct)\b|\b(?:i|we)\s+(?:retract|withdraw|correct)\b|(?:^|[.?!])\s*(?:that|this)\s+is\s+(?:false|wrong|mistaken)\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty {
      return true
    }
    guard
      regexRanges(
        #"^\s*(?:the\s+)?(?:key\s+point|important\s+point|what\s+matters)\s+is\s+actually\b"#,
        in: normalized,
        caseInsensitive: true
      ).isEmpty
    else {
      return false
    }
    return !regexRanges(
      #"\b(?:key\s+point|important\s+point|what\s+matters)\s+(?:is\s+)?\S+(?:\s+\S+){0,6}\s+(?:actually|i\s+mean)\s+\S+"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isImperativeAssertion(_ text: String) -> Bool {
    let normalized = canonicalVisibleText(text)
    if !regexRanges(
      #"(?:ください|下さい|なさい|ましょう|(?:し)?ないで)$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    if !regexRanges(
      #"^(?:you|we)\s+(?:should|must|need\s+to|have\s+to)\s+[a-z]"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"^(?:(?:please\s+)?|(?:do\s+not|don['’]?t|never)\s+)(?:write|put|draw|show|display|note|consider|look|observe|compare|explain|define|repeat|say|open|close|click|select|start|stop|move|go|ignore|breathe|summarize|pay\s+attention)\b|\b(?:should|must|need\s+to|have\s+to)\s+(?:write|put|draw|show|display|note|consider|explain|define|repeat|say|ignore|breathe|summarize)\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isLogisticsOrMetalinguistic(_ text: String) -> Bool {
    let normalized = canonicalVisibleText(text)
    let japaneseCues = [
      "次のスライド", "前のスライド", "次に進", "休憩します", "時間です", "マイク", "画面共有",
      "メニューを開", "ウインドウを開", "ウィンドウを開", "について考えます", "について説明します",
      "について話します", "を説明します", "を紹介します", "と発音します", "と発音されます",
      "と読みます", "と読まれます", "二つの漢字", "2つの漢字",
    ]
    if japaneseCues.contains(where: normalized.contains) { return true }
    if !regexRanges(
      #"(?:今日は|本日は)[^。．.!！?？]{0,36}を(?:扱います|話します|説明します)|(?:名詞|動詞|形容詞|副詞)(?:です|だ|である)|(?:一|二|三|四|五|六|七|八|九|十|\d+)(?:文字|音節)(?:です|だ|である)"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"\b(?:next|previous)\s+slide\b|\b(?:is|are|was|were)\s+next\b|^(?:okay|ok|all\s+right)\b[^.?!]*(?:next|move\s+on|continue|slide)\b|^(?:today|now)\s+(?:i|we)\s+(?:discuss|explain|consider|cover|review|introduce)\b|^(?:today\s+)?(?:i|we)\s+(?:will|are\s+going\s+to)\s+(?:cover|discuss|talk\s+about|explain|review|consider|introduce)\b|\b(?:context\s+)?(?:menu|window|file|application|app|powerpoint)\s+(?:is|was)\s+(?:open|closed|visible|selected)\b|\b(?:is|are)\s+(?:an?\s+)?(?:noun|verb|adjective|adverb)\b|\b(?:is|are)\s+(?:pronounced|spelled)\b|\b(?:has|have|contains?|consists?\s+of)\s+(?:[a-z-]+|\d+)\s+(?:letters?|syllables?|characters?)\b"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isDeicticOrGrammarOnly(_ text: String) -> Bool {
    let normalized = canonicalVisibleText(text)
    if isBareInterrogative(normalized) { return true }
    if !regexRanges(
      #"^(?:これ|それ|あれ|ここ|そこ|あそこ)(?:です|だ|である)?$|^(?:この|その|あの)(?:スライド|点|こと|内容|文章|図|画像)(?:です|だ|である)?$"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"^(?:this|that|it|these|those|here|there)$|^(?:this|that|these|those)\s+(?:slide|point|thing|content|text|figure|image)$"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isSafeEmbeddedContextUnit(_ text: String) -> Bool {
    if isPlacementOnlyInstruction(text) { return true }
    return isSafePublicSemanticFrame(text)
  }

  private func isSafeEmbeddedImportanceFrame(_ text: String) -> Bool {
    guard !isExplicitQuestion(text), !isBareInterrogative(text),
      !isNegatedImportanceBody(text), !isUncertainImportanceBody(text),
      !isFramedAsQuotationOrReading(text), !isTagQuestion(text),
      !isCorrectionOrRetraction(text), isSafeStructuredUtterance(text)
    else {
      return false
    }
    return true
  }

  private func isSafeLogisticsUnit(_ text: String) -> Bool {
    guard !containsRecognizedImportanceCue(text), isLogisticsOrMetalinguistic(text),
      !isExplicitQuestion(text), !isBareInterrogative(text),
      !isNegatedImportanceBody(text), !isUncertainImportanceBody(text),
      !isFramedAsQuotationOrReading(text), !isTagQuestion(text),
      !isCorrectionOrRetraction(text), !isImportanceInstruction(text),
      !isImperativeAssertion(text), isSafeStructuredUtterance(text)
    else {
      return false
    }
    guard isReportedSpeech(text) else { return true }

    let normalized = canonicalVisibleText(text)
    let stripped = normalized.replacingOccurrences(
      of:
        #"^(?:today\s+)?(?:i|we)\s+(?:(?:will|are\s+going\s+to)\s+)?(?:discuss|explain|consider|cover|review|introduce)\s+"#,
      with: "",
      options: [.regularExpression, .caseInsensitive]
    )
    return stripped != normalized && !isReportedSpeech(stripped)
  }

  private func isSafeLeadingContextQuestion(_ text: String) -> Bool {
    isExplicitQuestion(text) && !containsRecognizedImportanceCue(text)
      && !isTagQuestion(text) && !isUncertainImportanceBody(text)
      && !isReportedSpeech(text) && !isFramedAsQuotationOrReading(text)
      && !isCorrectionOrRetraction(text) && !isImportanceInstruction(text)
      && !isImperativeAssertion(text) && isSafeStructuredUtterance(text)
  }

  private func isPlacementOnlyInstruction(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    guard !containsRecognizedImportanceCue(normalized) else { return false }
    if !regexRanges(
      #"\A(?:その|これ|それ)?(?:内容を)?(?:スライド(?:画面)?の)?(?:(?:右上|左上|右下|左下|上部|下部|中央|真ん中)(?:の(?:部分|空白部分|空いている部分))?|白い(?:部分|スペース)|空白(?:部分|領域|スペース)?|空いている(?:部分|領域|スペース))?(?:に|へ)?\s*(?:板書|表示|配置|記入|書いて|描いて)(?:を)?(?:して)?(?:ください|下さい|ほしい|欲しい)\s*[。．.!！]?\z"#,
      in: normalized
    ).isEmpty {
      return true
    }
    return !regexRanges(
      #"\A(?:please\s+)?(?:write|put|place|show|display|draw)\s+(?:it|that|this|the\s+(?:point|content))\s+(?:in|on|at)\s+(?:the\s+)?(?:blank|empty|white|upper|lower|top|bottom|left|right)[^.?!]*\s*[.!]?\z"#,
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
    guard !containsUnsafeQuotationMark(in: text), !isCorrectionOrRetraction(text),
      !hasUnsafeMetalinguisticStructure(text)
    else { return false }

    return true
  }

  private func hasUnsafeMetalinguisticStructure(_ text: String) -> Bool {
    let normalized = TextFeatures.normalize(text)
    let japaneseMetalinguisticCues = [
      "接続詞", "という語", "という表現", "という言葉", "という文", "という指示", "という命令", "と発話",
    ]
    if japaneseMetalinguisticCues.contains(where: normalized.contains) { return true }
    return !regexRanges(
      #"\b(?:word|phrase|sentence|command|instruction|term|connector|conjunction)\b|\b(?:use|say|write|pronounce|define|explain)\s+(?:the\s+)?(?:word\s+)?['\"]?(?:because|therefore|whereas)['\"]?\b|['\"]\s*(?:because|therefore|whereas)\s*['\"]"#,
      in: normalized,
      caseInsensitive: true
    ).isEmpty
  }

  private func isSafeAutomaticKeywordAssertion(_ text: String) -> Bool {
    let assertion = trimBoardItem(text)
    guard isSingleSubstantiveClause(assertion), isSafePublicSemanticFrame(text)
    else {
      return false
    }
    return !containsRecognizedImportanceCue(text)
  }

  private func isSafePublicSemanticFrame(
    _ text: String,
    permitsExplicitImportanceSyntax: Bool = false
  ) -> Bool {
    guard !isExplicitQuestion(text), !isBareInterrogative(text),
      !isNegatedImportanceBody(text), !isUncertainImportanceBody(text),
      !isReportedSpeech(text), !isFramedAsQuotationOrReading(text),
      !isTagQuestion(text), !isCorrectionOrRetraction(text),
      !isLogisticsOrMetalinguistic(text), !isDeicticOrGrammarOnly(text),
      isSafeStructuredUtterance(text)
    else {
      return false
    }
    if !permitsExplicitImportanceSyntax {
      guard !isImportanceInstruction(text), !isImperativeAssertion(text) else { return false }
    }
    return true
  }

  private func isCompleteSafeImportanceBody(_ text: String) -> Bool {
    let body = trimBoardItem(text)
    guard !body.isEmpty, isSingleSubstantiveClause(body),
      isSafePublicSemanticFrame(body)
    else {
      return false
    }

    let containsJapanese = body.unicodeScalars.contains { scalar in
      (0x3040...0x30FF).contains(scalar.value) || (0x3400...0x9FFF).contains(scalar.value)
    }
    if containsJapanese {
      if isDeclarativeAssertion(body, language: .japanese) { return true }
      guard regexRanges(#"(?:なの|でしょ|かな|かね|かしら)$"#, in: body).isEmpty else {
        return false
      }
      if !regexRanges(
        #"(?:です|でした|だ|だった|である|ます|ました|する|した|なる|なった|こと|もの)$"#,
        in: body
      ).isEmpty {
        return true
      }
      return !regexRanges(
        #"^[\p{L}\p{N}ー・]{1,42}$"#,
        in: body
      ).isEmpty
    }

    if isDeclarativeAssertion(body, language: .englishUS) { return true }
    return !regexRanges(
      #"^(?:(?:a|an|the)\s+)?[a-z0-9][a-z0-9'’-]*(?:\s+(?:(?:and|of|for|in|on|with|without|between|among)\s+)?[a-z0-9][a-z0-9'’-]*){0,7}$"#,
      in: body,
      caseInsensitive: true
    ).isEmpty
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
