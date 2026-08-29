import LectureBoardCore

@MainActor
enum DemoBoardSceneFactory {
  static func make(language: LanguageTag) -> BoardScene {
    let japanese = language.rawValue.hasPrefix("ja")
    return BoardScene(
      slideNumber: 1,
      elements: [
        BoardElement(
          kind: .roundedRectangle,
          region: NormalizedRect(x: 0.68, y: 0.08, width: 0.29, height: 0.25),
          role: .emphasis
        ),
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.71, y: 0.11, width: 0.23, height: 0.07),
          text: japanese ? "持続可能性" : "Sustainability",
          role: .emphasis
        ),
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.71, y: 0.19, width: 0.23, height: 0.11),
          text: japanese
            ? "現在の必要\n＋将来世代の可能性"
            : "present needs\n+ future possibilities",
          role: .primary
        ),
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.69, y: 0.48, width: 0.27, height: 0.12),
          text: japanese
            ? "人間活動 → 環境負荷 → 社会的影響"
            : "human activity → environmental pressure → social effects",
          role: .primary
        ),
      ]
    )
  }
}
