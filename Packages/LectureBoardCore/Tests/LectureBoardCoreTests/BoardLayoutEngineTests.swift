import Testing

@testable import LectureBoardCore

struct BoardLayoutEngineTests {
  @Test func avoidsOccupiedSlideRegion() {
    let occupied = [NormalizedRect(x: 0, y: 0, width: 0.65, height: 1)]
    let intent = BoardIntent(
      kind: .definition,
      title: "Definition",
      items: ["A grounded explanation"],
      sourceSegmentIDs: [],
      importance: 0.8,
      confidence: 0.9,
      language: .englishUS
    )

    let placement = BoardLayoutEngine().placement(
      for: intent,
      slideOccupied: occupied,
      boardOccupied: []
    )

    #expect(placement != nil)
    #expect((placement?.x ?? 0) >= 0.62)
    #expect(placement?.intersectionArea(with: occupied[0]) == 0)
  }

  @Test func returnsNilWhenNoAdequateSpaceExists() {
    let occupied = [NormalizedRect(x: 0, y: 0, width: 1, height: 1)]
    let intent = BoardIntent(
      kind: .comparison,
      title: "Comparison",
      items: ["A", "B"],
      sourceSegmentIDs: [],
      importance: 0.7,
      confidence: 0.8,
      language: .englishUS
    )

    let placement = BoardLayoutEngine().placement(
      for: intent,
      slideOccupied: occupied,
      boardOccupied: []
    )

    #expect(placement == nil)
  }

  @Test func compactKeywordUsesSmallerEmptyRegionWhenDefaultSizeDoesNotFit() throws {
    let occupied = [
      NormalizedRect(x: 0, y: 0, width: 1, height: 0.80),
      NormalizedRect(x: 0, y: 0.80, width: 0.72, height: 0.20),
    ]
    let intent = BoardIntent(
      kind: .keyword,
      title: "Current slide",
      items: ["テストです"],
      sourceSegmentIDs: [],
      importance: 0.9,
      confidence: 0.8,
      language: .japanese
    )

    let placement = try #require(
      BoardLayoutEngine().placement(
        for: intent,
        slideOccupied: occupied,
        boardOccupied: []
      )
    )

    #expect(placement.width == 0.24)
    #expect(placement.height == 0.15)
    #expect(occupied.allSatisfy { placement.intersectionArea(with: $0) == 0 })
  }

  @Test func compactKeywordStillReturnsNilWhenNoEmptyRegionExists() {
    let intent = BoardIntent(
      kind: .keyword,
      title: "Current slide",
      items: ["テストです"],
      sourceSegmentIDs: [],
      importance: 0.9,
      confidence: 0.8,
      language: .japanese
    )

    let placement = BoardLayoutEngine().placement(
      for: intent,
      slideOccupied: [NormalizedRect(x: 0, y: 0, width: 1, height: 1)],
      boardOccupied: []
    )

    #expect(placement == nil)
  }
}
