import LectureBoardCore
import SwiftUI

struct BoardPreviewView: View {
  let scene: BoardScene
  let style: DigitalInkStyle

  var body: some View {
    GroupBox("board.preview") {
      ZStack {
        RoundedRectangle(cornerRadius: 14)
          .fill(Color(nsColor: .textBackgroundColor))
        RoundedRectangle(cornerRadius: 14)
          .stroke(.secondary.opacity(0.35))

        BoardSceneView(scene: scene, style: style)
          .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .aspectRatio(16 / 9, contentMode: .fit)
      .padding(.vertical, 10)
    }
  }
}
