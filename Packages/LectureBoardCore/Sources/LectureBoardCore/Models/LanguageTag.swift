import Foundation

public struct LanguageTag: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral
{
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: StringLiteralType) {
    self.rawValue = value
  }

  public static let japanese: LanguageTag = "ja-JP"
  public static let englishUS: LanguageTag = "en-US"
  public static let englishGB: LanguageTag = "en-GB"
}
