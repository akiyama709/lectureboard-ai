import Foundation

struct TextFeatures: Sendable {
  static func normalize(_ text: String) -> String {
    text
      .folding(
        options: [.caseInsensitive, .diacriticInsensitive],
        locale: Locale(identifier: "en_US_POSIX")
      )
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func tokens(_ text: String) -> Set<String> {
    let normalized = normalize(text)
    var result = Set<String>()

    let latinWords =
      normalized
      .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
      .split(separator: " ")
      .map(String.init)
      .filter { $0.count >= 2 }
    result.formUnion(latinWords)

    let cjk = normalized.unicodeScalars.filter { scalar in
      switch scalar.value {
      case 0x3040...0x30FF, 0x3400...0x9FFF, 0xF900...0xFAFF:
        return true
      default:
        return false
      }
    }.map(String.init).joined()

    if cjk.count == 1 {
      result.insert(cjk)
    } else if cjk.count > 1 {
      let characters = Array(cjk)
      for index in 0..<(characters.count - 1) {
        result.insert(String(characters[index...index + 1]))
      }
    }

    return result
  }

  static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
    guard !lhs.isEmpty || !rhs.isEmpty else { return 1 }
    let intersection = lhs.intersection(rhs).count
    let union = lhs.union(rhs).count
    return union == 0 ? 0 : Double(intersection) / Double(union)
  }

  static func containsAny(_ text: String, phrases: [String]) -> Bool {
    let normalized = normalize(text)
    return phrases.contains { normalized.contains(normalize($0)) }
  }
}
