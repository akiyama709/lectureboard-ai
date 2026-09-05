import Foundation
import Testing

@testable import LectureBoardCore

struct LectureSessionExporterTests {
  @Test func jsonIsDeterministicAndContainsOnlyPublicSceneFields() throws {
    let sourceIntentID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
    let sourceSegmentID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
    let scene = BoardScene(
      slideNumber: 2,
      elements: [
        BoardElement(
          id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
          kind: .text,
          region: NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
          text: "公開板書",
          role: .emphasis,
          sourceIntentID: sourceIntentID
        ),
        BoardElement(
          kind: .arrow,
          region: NormalizedRect(x: 0.2, y: 0.4, width: 0.2, height: 0.1),
          points: [
            NormalizedPoint(x: 0.2, y: 0.45),
            NormalizedPoint(x: 0.4, y: 0.45),
          ],
          sourceIntentID: sourceIntentID
        ),
      ]
    )
    let session = LectureSessionExporter(scenes: [scene])
    let first = try session.jsonData()
    let second = try session.jsonData()

    #expect(first == second)
    let json = String(decoding: first, as: UTF8.self)
    #expect(json.contains("lectureboard-session"))
    #expect(json.contains("公開板書"))
    #expect(!json.contains(sourceIntentID.uuidString))
    #expect(!json.contains(sourceSegmentID.uuidString))
    #expect(!json.contains("sourceIntentID"))
    #expect(!json.contains("sourceSegmentIDs"))
    #expect(!json.contains("transcript"))
    #expect(!json.contains("ocr"))
  }

  @Test func multiSlideJSONPreservesOrderAndSVGIsOneDeterministicDocument() throws {
    let first = BoardScene(
      slideNumber: 1,
      elements: [
        BoardElement(
          kind: .roundedRectangle,
          region: NormalizedRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
          role: .secondary
        )
      ]
    )
    let second = BoardScene(
      slideNumber: 7,
      elements: [
        BoardElement(
          kind: .ellipse,
          region: NormalizedRect(x: 0.6, y: 0.6, width: 0.2, height: 0.2),
          role: .caution
        )
      ]
    )
    let exporter = LectureSessionExporter(scenes: [first, second])
    let data = try exporter.jsonData()
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let slides = try #require(object["slides"] as? [[String: Any]])
    #expect(slides.count == 2)
    #expect(slides[0]["slideNumber"] as? Int == 1)
    #expect(slides[1]["slideNumber"] as? Int == 7)

    let svg = exporter.svgString()
    #expect(svg == String(decoding: exporter.svgData(), as: UTF8.self))
    #expect(svg.contains("viewBox=\"0 0 1000 2000\""))
    #expect(svg.contains("data-slide-number=\"1\""))
    #expect(svg.contains("data-slide-number=\"7\""))
    #expect(svg.contains("translate(0 1000)"))
    #expect(svg.contains("<ellipse"))
  }

  @Test func svgEscapesTextAndDoesNotExposeElementIdentifiers() {
    let elementID = UUID(uuidString: "DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD")!
    let scene = BoardScene(
      slideNumber: 3,
      elements: [
        BoardElement(
          id: elementID,
          kind: .text,
          region: NormalizedRect(x: 0, y: 0, width: 1, height: 0.1),
          text: "<script>& \"quoted\"",
          role: .primary
        )
      ]
    )

    let svg = LectureSessionExporter(scenes: [scene]).svgString()
    #expect(svg.contains("&lt;script&gt;&amp; &quot;quoted&quot;"))
    #expect(!svg.contains(elementID.uuidString))
    #expect(!svg.contains("sourceIntentID"))
  }

  @Test func writeCreatesSVGSiblingForExplicitJSONPath() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("lectureboard-export-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let jsonURL = directory.appendingPathComponent("session.json")
    let urls = try LectureSessionExporter(scenes: [BoardScene(slideNumber: 1)]).write(to: jsonURL)
    #expect(urls.json == jsonURL)
    #expect(urls.svg == directory.appendingPathComponent("session.svg"))
    #expect(FileManager.default.fileExists(atPath: urls.json.path))
    #expect(FileManager.default.fileExists(atPath: urls.svg.path))
    #expect(try Data(contentsOf: urls.json).starts(with: Data("{\n".utf8)))
    #expect(try Data(contentsOf: urls.svg).starts(with: Data("<?xml".utf8)))
  }
}
