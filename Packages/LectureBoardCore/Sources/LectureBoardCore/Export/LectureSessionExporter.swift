import Foundation

/// The two files produced for one lecture session.
public struct LectureSessionExportURLs: Equatable, Sendable {
  public let json: URL
  public let svg: URL

  public init(json: URL, svg: URL) {
    self.json = json
    self.svg = svg
  }
}

/// A deterministic, privacy-bounded export of the public board scene.
///
/// The exporter deliberately projects ``BoardScene`` into private DTOs.  Board element UUIDs,
/// source intent UUIDs, transcript segment UUIDs, and all non-public intents therefore cannot
/// accidentally become part of an exported file.  A scene passed to this type is assumed to
/// have already crossed ``BoardSceneComposer``'s confirmed/pinned public-scene boundary.
public struct LectureSessionExporter: Sendable {
  public static let format = "lectureboard-session"
  public static let schemaVersion = 1

  public let scenes: [BoardScene]

  public init(scenes: [BoardScene]) {
    self.scenes = scenes
  }

  /// Encodes the session with sorted keys and stable array ordering.
  public func jsonData() throws -> Data {
    let document = JSONDocument(
      format: Self.format,
      schemaVersion: Self.schemaVersion,
      slides: scenes.map(JSONSlide.init)
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(document)
  }

  /// Renders all slides into one deterministic SVG document.  Slides are stacked vertically,
  /// each in a 1000 by 1000 normalized canvas, so no slide image or capture payload is needed.
  public func svgData() -> Data {
    Data(svgString().utf8)
  }

  public func svgString() -> String {
    let canvasHeight = 1_000 * max(1, scenes.count)
    var output = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
    output +=
      "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1000 \(canvasHeight)\" width=\"1000\" height=\"\(canvasHeight)\">\n"
    output += "  <defs>\n"
    output +=
      "    <marker id=\"arrowhead\" markerWidth=\"8\" markerHeight=\"8\" refX=\"7\" refY=\"4\" orient=\"auto\" markerUnits=\"strokeWidth\">\n"
    output += "      <path d=\"M 0 0 L 8 4 L 0 8 z\" fill=\"#38598a\"/>\n"
    output += "    </marker>\n"
    output += "  </defs>\n"

    if scenes.isEmpty {
      output +=
        "  <g data-slide-number=\"0\"><rect width=\"1000\" height=\"1000\" fill=\"#ffffff\"/></g>\n"
    } else {
      for (index, scene) in scenes.enumerated() {
        let offset = index * 1_000
        output +=
          "  <g data-slide-number=\"\(scene.slideNumber)\" transform=\"translate(0 \(offset))\">\n"
        output += "    <rect width=\"1000\" height=\"1000\" fill=\"#ffffff\"/>\n"
        for element in scene.elements {
          output += svg(element: element)
        }
        output += "  </g>\n"
      }
    }
    output += "</svg>\n"
    return output
  }

  /// Writes JSON at `jsonURL` and SVG beside it with the same basename.
  @discardableResult
  public func write(to jsonURL: URL) throws -> LectureSessionExportURLs {
    let svgURL = jsonURL.deletingPathExtension().appendingPathExtension("svg")
    try jsonData().write(to: jsonURL, options: .atomic)
    try svgData().write(to: svgURL, options: .atomic)
    return LectureSessionExportURLs(json: jsonURL, svg: svgURL)
  }

  public static func jsonData(for scenes: [BoardScene]) throws -> Data {
    try LectureSessionExporter(scenes: scenes).jsonData()
  }

  public static func svgData(for scenes: [BoardScene]) -> Data {
    LectureSessionExporter(scenes: scenes).svgData()
  }

  private func svg(element: BoardElement) -> String {
    let r = element.region.clamped()
    let x = number(r.x * 1_000)
    let y = number(r.y * 1_000)
    let width = number(r.width * 1_000)
    let height = number(r.height * 1_000)
    let color = color(for: element.role)
    let stroke =
      "stroke=\"\(color)\" stroke-width=\"3\" fill=\"none\" stroke-linecap=\"round\" stroke-linejoin=\"round\""

    switch element.kind {
    case .text:
      return svgText(element.text ?? "", x: x, y: y, height: height, color: color)
    case .roundedRectangle:
      return
        "    <rect x=\"\(x)\" y=\"\(y)\" width=\"\(width)\" height=\"\(height)\" rx=\"12\" \(stroke)/>\n"
    case .ellipse:
      return
        "    <ellipse cx=\"\(number(r.x * 1_000 + r.width * 500))\" cy=\"\(number(r.y * 1_000 + r.height * 500))\" rx=\"\(number(r.width * 500))\" ry=\"\(number(r.height * 500))\" \(stroke)/>\n"
    case .line, .arrow:
      let points =
        element.points.count >= 2
        ? element.points.map { "\(number($0.x * 1_000)),\(number($0.y * 1_000))" }.joined(
          separator: " ")
        : "\(x),\(number(r.y * 1_000 + r.height * 500)) \(number(r.x * 1_000 + r.width * 1_000)),\(number(r.y * 1_000 + r.height * 500))"
      let marker = element.kind == .arrow ? " marker-end=\"url(#arrowhead)\"" : ""
      return "    <polyline points=\"\(points)\" \(stroke)\(marker)/>\n"
    }
  }

  private func svgText(_ text: String, x: String, y: String, height: String, color: String)
    -> String
  {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    let heightValue = Double(height) ?? 0
    let yValue = Double(y) ?? 0
    let fontSize = number(min(32, max(14, heightValue * 0.34)))
    let fontSizeValue = Double(fontSize) ?? 14
    var result =
      "    <text x=\"\(x)\" y=\"\(number(yValue + fontSizeValue * 0.9))\" fill=\"\(color)\" font-family=\"system-ui, sans-serif\" font-size=\"\(fontSize)\">"
    for (index, line) in lines.enumerated() {
      let escaped = escapeXML(String(line))
      if index == 0 {
        result += escaped
      } else {
        result += "<tspan x=\"\(x)\" dy=\"1.2em\">\(escaped)</tspan>"
      }
    }
    return result + "</text>\n"
  }

  private func color(for role: BoardStyleRole) -> String {
    switch role {
    case .primary: return "#38598a"
    case .secondary: return "#5f6f86"
    case .emphasis: return "#9b4d72"
    case .caution: return "#a85d2b"
    }
  }

  private func number(_ value: Double) -> String {
    let value = value.isFinite ? value : 0
    return String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), value)
      .replacingOccurrences(of: #"\.?(0+)$"#, with: "", options: .regularExpression)
  }

  private func escapeXML(_ value: String) -> String {
    value
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
      .replacingOccurrences(of: "'", with: "&apos;")
  }
}

private struct JSONDocument: Encodable {
  let format: String
  let schemaVersion: Int
  let slides: [JSONSlide]
}

private struct JSONSlide: Encodable {
  let slideNumber: Int
  let elements: [JSONElement]

  init(_ scene: BoardScene) {
    slideNumber = scene.slideNumber
    elements = scene.elements.map(JSONElement.init)
  }
}

private struct JSONElement: Encodable {
  let kind: BoardElementKind
  let region: NormalizedRect
  let text: String?
  let points: [NormalizedPoint]
  let role: BoardStyleRole

  init(_ element: BoardElement) {
    kind = element.kind
    region = element.region.clamped()
    text = element.text
    points = element.points
    role = element.role
  }
}
