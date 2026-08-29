import Foundation
import Testing

@testable import LectureBoardCore

struct SlideAnalysisAssemblerTests {
  @Test func filtersAndNormalizesTextObservations() {
    let acceptedID = UUID()
    let analysis = SlideAnalysisAssembler().assemble(
      textObservations: [
        SlideTextObservation(
          id: acceptedID,
          text: "  Grounded title\n",
          region: NormalizedRect(x: -0.02, y: 0.04, width: 0.52, height: 0.10),
          confidence: 0.91
        ),
        SlideTextObservation(
          text: "Low confidence",
          region: NormalizedRect(x: 0.1, y: 0.3, width: 0.4, height: 0.08),
          confidence: 0.2
        ),
        SlideTextObservation(
          text: " \n",
          region: NormalizedRect(x: 0.1, y: 0.4, width: 0.4, height: 0.08),
          confidence: 0.9
        ),
      ],
      geometryObservations: []
    )

    #expect(analysis.textBlocks.count == 1)
    #expect(analysis.textBlocks[0].id == acceptedID)
    #expect(analysis.textBlocks[0].text == "Grounded title")
    #expect(analysis.textBlocks[0].region.x == 0)
    #expect(analysis.title == "Grounded title")
  }

  @Test func explicitTitleTakesPriorityOverSpatialFallback() {
    let analysis = SlideAnalysisAssembler().assemble(
      textObservations: [
        SlideTextObservation(
          text: "Header",
          region: NormalizedRect(x: 0.1, y: 0.05, width: 0.4, height: 0.08),
          confidence: 0.9
        ),
        SlideTextObservation(
          text: "Vision title",
          region: NormalizedRect(x: 0.1, y: 0.22, width: 0.5, height: 0.09),
          confidence: 0.95,
          isTitleCandidate: true
        ),
      ],
      geometryObservations: []
    )

    #expect(analysis.title == "Vision title")
  }

  @Test func rejectsTinyLowConfidenceAndFullSlideGeometry() {
    let analysis = SlideAnalysisAssembler().assemble(
      textObservations: [],
      geometryObservations: [
        SlideGeometryObservation(
          region: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.2),
          confidence: 0.8
        ),
        SlideGeometryObservation(
          region: NormalizedRect(x: 0, y: 0, width: 1, height: 1),
          confidence: 0.99
        ),
        SlideGeometryObservation(
          region: NormalizedRect(x: 0.2, y: 0.2, width: 0.01, height: 0.01),
          confidence: 0.99
        ),
        SlideGeometryObservation(
          region: NormalizedRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2),
          confidence: 0.1
        ),
      ]
    )

    #expect(analysis.graphicRegions.count == 1)
    let region = analysis.graphicRegions[0]
    #expect(abs(region.x - 0.1) < 0.000_001)
    #expect(abs(region.y - 0.2) < 0.000_001)
    #expect(abs(region.width - 0.3) < 0.000_001)
    #expect(abs(region.height - 0.2) < 0.000_001)
  }

  @Test func padsAndTransitivelyMergesTouchingOccupancy() {
    let configuration = SlideAnalysisConfiguration(
      occupancyPadding: 0.01,
      mergeTolerance: 0
    )
    let analysis = SlideAnalysisAssembler(configuration: configuration).assemble(
      textObservations: [
        SlideTextObservation(
          text: "A",
          region: NormalizedRect(x: 0.10, y: 0.10, width: 0.10, height: 0.10),
          confidence: 1
        ),
        SlideTextObservation(
          text: "B",
          region: NormalizedRect(x: 0.21, y: 0.10, width: 0.10, height: 0.10),
          confidence: 1
        ),
      ],
      geometryObservations: [
        SlideGeometryObservation(
          region: NormalizedRect(x: 0.32, y: 0.10, width: 0.10, height: 0.10),
          confidence: 1
        )
      ]
    )

    #expect(analysis.occupiedRegions.count == 1)
    let occupied = analysis.occupiedRegions[0]
    #expect(abs(occupied.x - 0.09) < 0.000_001)
    #expect(abs(occupied.y - 0.09) < 0.000_001)
    #expect(abs(occupied.maxX - 0.43) < 0.000_001)
    #expect(abs(occupied.maxY - 0.21) < 0.000_001)
  }

  @Test func preservesSeparatedOccupiedRegionsInSpatialOrder() {
    let configuration = SlideAnalysisConfiguration(
      occupancyPadding: 0,
      mergeTolerance: 0
    )
    let analysis = SlideAnalysisAssembler(configuration: configuration).assemble(
      textObservations: [
        SlideTextObservation(
          text: "Lower",
          region: NormalizedRect(x: 0.6, y: 0.7, width: 0.2, height: 0.08),
          confidence: 1
        ),
        SlideTextObservation(
          text: "Upper",
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.08),
          confidence: 1
        ),
      ],
      geometryObservations: []
    )

    #expect(analysis.textBlocks.map(\.text) == ["Upper", "Lower"])
    #expect(analysis.occupiedRegions.count == 2)
    #expect(analysis.occupiedRegions[0].y < analysis.occupiedRegions[1].y)
  }

  @Test func normalizesInvalidConfigurationBounds() {
    let configuration = SlideAnalysisConfiguration(
      minimumTextConfidence: -1,
      minimumGeometryConfidence: 2,
      minimumTextArea: -0.5,
      minimumGeometryArea: 0.7,
      maximumGeometryArea: 0.2,
      occupancyPadding: 2,
      mergeTolerance: -1,
      titleBandMaximumY: 4
    )

    #expect(configuration.minimumTextConfidence == 0)
    #expect(configuration.minimumGeometryConfidence == 1)
    #expect(configuration.minimumTextArea == 0)
    #expect(configuration.minimumGeometryArea == 0.7)
    #expect(configuration.maximumGeometryArea == 0.7)
    #expect(configuration.occupancyPadding == 0.25)
    #expect(configuration.mergeTolerance == 0)
    #expect(configuration.titleBandMaximumY == 1)
  }

  @Test func visualAnalysisRoundTripsThroughJSON() throws {
    let analysis = SlideVisualAnalysis(
      title: "Feedback loop",
      textBlocks: [
        SlideTextBlock(
          text: "Feedback loop",
          region: NormalizedRect(x: 0.08, y: 0.06, width: 0.42, height: 0.08)
        )
      ],
      graphicRegions: [
        NormalizedRect(x: 0.12, y: 0.30, width: 0.28, height: 0.24)
      ],
      occupiedRegions: [
        NormalizedRect(x: 0.07, y: 0.05, width: 0.44, height: 0.10),
        NormalizedRect(x: 0.11, y: 0.29, width: 0.30, height: 0.26),
      ]
    )

    let data = try JSONEncoder().encode(analysis)
    let decoded = try JSONDecoder().decode(SlideVisualAnalysis.self, from: data)
    #expect(decoded == analysis)
  }
}
