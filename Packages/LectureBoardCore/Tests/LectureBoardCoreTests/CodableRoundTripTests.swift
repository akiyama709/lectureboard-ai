import Foundation
import Testing

@testable import LectureBoardCore

struct CodableRoundTripTests {
  @Test func boardSceneRoundTripsThroughJSON() throws {
    let scene = BoardScene(
      slideNumber: 4,
      elements: [
        BoardElement(
          kind: .text,
          region: NormalizedRect(x: 0.7, y: 0.1, width: 0.25, height: 0.1),
          text: "統合知",
          role: .emphasis
        )
      ]
    )

    let data = try JSONEncoder().encode(scene)
    let decoded = try JSONDecoder().decode(BoardScene.self, from: data)
    #expect(decoded == scene)
  }
}
