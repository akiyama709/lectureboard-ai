import Foundation
import LectureBoardCore
import SwiftUI

struct BoardSceneView: View {
  let scene: BoardScene
  let style: DigitalInkStyle

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topLeading) {
        ForEach(scene.elements) { element in
          elementView(element, in: proxy.size)
        }
      }
    }
    .allowsHitTesting(false)
  }

  @ViewBuilder
  private func elementView(_ element: BoardElement, in size: CGSize) -> some View {
    let frame = rect(element.region, in: size)
    let color = color(for: element.role)
    let variation = stableVariation(for: element)

    switch element.kind {
    case .text:
      Text(element.text ?? "")
        .font(
          .system(
            size: max(14, frame.height * 0.34),
            weight: element.role == .emphasis ? .semibold : .regular,
            design: .rounded
          )
        )
        .foregroundStyle(color)
        .multilineTextAlignment(.leading)
        .lineLimit(nil)
        .minimumScaleFactor(0.55)
        .frame(width: frame.width, height: frame.height, alignment: .topLeading)
        .position(x: frame.midX, y: frame.midY)
        .rotationEffect(.degrees(Double(variation) * 0.7))
        .offset(x: variation * 0.35, y: variation * -0.22)
    case .roundedRectangle:
      RoundedRectangle(cornerRadius: 12)
        .stroke(
          color,
          style: StrokeStyle(
            lineWidth: style.lineWidth,
            lineCap: .round,
            lineJoin: .round
          )
        )
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .rotationEffect(.degrees(Double(variation) * 0.45))
    case .ellipse:
      Ellipse()
        .stroke(color, lineWidth: style.lineWidth)
        .frame(width: frame.width, height: frame.height)
        .position(x: frame.midX, y: frame.midY)
        .rotationEffect(.degrees(Double(variation) * 0.45))
    case .line, .arrow:
      Path { path in
        let points = renderedPoints(
          for: element, defaultFrame: frame, size: size, variation: variation)
        guard let first = points.first else { return }
        path.move(to: first)
        for point in points.dropFirst() {
          path.addLine(to: point)
        }
        if element.kind == .arrow,
          points.count >= 2,
          let end = points.last
        {
          addArrowhead(
            to: &path,
            from: points[points.count - 2],
            end: end,
            lineWidth: style.lineWidth
          )
        }
      }
      .stroke(
        color,
        style: StrokeStyle(
          lineWidth: style.lineWidth,
          lineCap: .round,
          lineJoin: .round
        )
      )
    }
  }

  private func renderedPoints(
    for element: BoardElement,
    defaultFrame: CGRect,
    size: CGSize,
    variation: CGFloat
  ) -> [CGPoint] {
    let points =
      element.points.isEmpty
      ? [
        CGPoint(x: defaultFrame.minX, y: defaultFrame.midY),
        CGPoint(x: defaultFrame.maxX, y: defaultFrame.midY),
      ]
      : element.points.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }

    guard style.handDrawnVariation > 0 else { return points }
    return points.enumerated().map { index, point in
      let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
      return CGPoint(
        x: point.x + direction * variation * 0.28,
        y: point.y - direction * variation * 0.20
      )
    }
  }

  private func addArrowhead(
    to path: inout Path,
    from start: CGPoint,
    end: CGPoint,
    lineWidth: CGFloat
  ) {
    let angle = atan2(end.y - start.y, end.x - start.x)
    let length = max(8, lineWidth * 4.2)
    let spread = CGFloat.pi / 6
    let left = CGPoint(
      x: end.x - length * cos(angle - spread),
      y: end.y - length * sin(angle - spread)
    )
    let right = CGPoint(
      x: end.x - length * cos(angle + spread),
      y: end.y - length * sin(angle + spread)
    )
    path.move(to: left)
    path.addLine(to: end)
    path.addLine(to: right)
  }

  private func stableVariation(for element: BoardElement) -> CGFloat {
    guard style.handDrawnVariation > 0 else { return 0 }
    let checksum = element.id.uuidString.unicodeScalars.reduce(0) { partial, scalar in
      (partial &* 31 &+ Int(scalar.value)) % 2_001
    }
    let centered = CGFloat(checksum) / 1_000 - 1
    return centered * style.handDrawnVariation
  }

  private func rect(_ normalized: NormalizedRect, in size: CGSize) -> CGRect {
    CGRect(
      x: normalized.x * size.width,
      y: normalized.y * size.height,
      width: normalized.width * size.width,
      height: normalized.height * size.height
    )
  }

  private func color(for role: BoardStyleRole) -> Color {
    switch role {
    case .emphasis, .caution:
      return Color(nsColor: style.emphasisColor)
    case .primary, .secondary:
      return Color(nsColor: style.primaryColor)
    }
  }
}
