import Foundation

/// Extracts the requested board content from a narrowly defined, whole-utterance command.
///
/// This parser intentionally does not try to understand general instructions. It accepts only a
/// small set of end-anchored Japanese and English forms so quoted speech, multiple statements, and
/// metalinguistic mentions have a lower risk of accidentally becoming public board content.
enum ExplicitBoardRequestParser {
  private static let maximumContentLength = 64

  static func requestedContent(in text: String, language: LanguageTag) -> String? {
    let languageCode = language.rawValue.lowercased()
    let captured: String?

    if languageCode.hasPrefix("ja") {
      captured = capture(
        #"\A\s*(.+?)\s*(?:(?:を|と)\s*板書\s*してください|と\s*書いて\s*ください)\s*[。．.!！]?\s*\z"#,
        in: text
      ).map(stripJapanesePlacementPrefix)
    } else if languageCode.hasPrefix("en") {
      captured = capture(
        #"\A\s*(?:please\s+)?(?:write|put)\s+(.+?)\s+on\s+the\s+board(?:\s+please)?\s*[.!]?\s*\z"#,
        in: text,
        caseInsensitive: true
      )
    } else {
      return nil
    }

    guard let captured else { return nil }
    let content = captured.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isSafeContent(content), !containsQuotationMark(in: text) else { return nil }
    return content
  }

  private static func capture(
    _ pattern: String,
    in text: String,
    caseInsensitive: Bool = false
  ) -> String? {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return nil
    }
    let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = expression.firstMatch(in: text, range: searchRange),
      match.range == searchRange,
      let range = Range(match.range(at: 1), in: text)
    else {
      return nil
    }
    return String(text[range])
  }

  private static func stripJapanesePlacementPrefix(_ text: String) -> String {
    // The public board layout remains responsible for placement. This prefix is removed only so
    // the spoken instruction itself never becomes visible board content.
    capture(
      #"\A(?:スライド(?:画面)?の)?(?:(?:右上|左上|右下|左下)(?:の(?:部分|空白部分|空いている部分))?|上部|下部|中央|真ん中|空白部分|空いている部分)に\s*(.+)\z"#,
      in: text
    ) ?? text
  }

  private static func isSafeContent(_ text: String) -> Bool {
    guard (1...maximumContentLength).contains(text.count),
      text.rangeOfCharacter(from: .newlines) == nil
    else {
      return false
    }

    let clauseAndListPunctuation = CharacterSet(charactersIn: "、，,;；:：。．.!！?？")
    guard text.rangeOfCharacter(from: clauseAndListPunctuation) == nil else { return false }

    let normalized = TextFeatures.normalize(text)
    let deicticOnlyContent = Set([
      "これ", "それ", "あれ", "ここ", "そこ", "あそこ",
      "this", "that", "it", "these", "those", "here", "there",
    ])
    guard !deicticOnlyContent.contains(normalized) else { return false }
    guard
      !hasRegexMatch(#"\A(?:この|その|あの|これ|それ|あれ)"#, in: normalized),
      !hasRegexMatch(
        #"\A(?:this|that|these|those)\b"#,
        in: normalized,
        caseInsensitive: true
      )
    else {
      return false
    }

    let japaneseMetalinguisticCues = [
      "という語", "という言葉", "という表現", "という文", "という指示", "という命令",
      "と発話", "書いて", "板書して",
    ]
    guard !japaneseMetalinguisticCues.contains(where: normalized.contains) else { return false }

    return !hasRegexMatch(
      #"(?:\A(?:the\s+)?(?:word|phrase|term|sentence|command|instruction)\b|\b(?:write|put)\b)"#,
      in: normalized,
      caseInsensitive: true
    )
  }

  private static func containsQuotationMark(in text: String) -> Bool {
    text.rangeOfCharacter(from: CharacterSet(charactersIn: "\"'“”‘’「」『』")) != nil
  }

  private static func hasRegexMatch(
    _ pattern: String,
    in text: String,
    caseInsensitive: Bool = false
  ) -> Bool {
    let options: NSRegularExpression.Options = caseInsensitive ? [.caseInsensitive] : []
    guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else {
      return false
    }
    let searchRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return expression.firstMatch(in: text, range: searchRange) != nil
  }
}
