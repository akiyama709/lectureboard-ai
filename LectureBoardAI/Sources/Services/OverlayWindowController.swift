import AppKit
import LectureBoardCore
import SwiftUI

@MainActor
final class OverlayWindowController {
  private var panel: NSPanel?
  private var hostingView: NSHostingView<BoardSceneView>?

  func show(scene: BoardScene, style: DigitalInkStyle, on screen: NSScreen? = NSScreen.main) {
    guard let screen else { return }

    if panel == nil {
      let panel = NSPanel(
        contentRect: screen.frame,
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false,
        screen: screen
      )
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.ignoresMouseEvents = true
      panel.level = .floating
      panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
      panel.isReleasedWhenClosed = false
      self.panel = panel
    }

    let rootView = BoardSceneView(scene: scene, style: style)
    let hostingView = NSHostingView(rootView: rootView)
    hostingView.frame = panel?.contentView?.bounds ?? screen.frame
    hostingView.autoresizingMask = [.width, .height]
    panel?.contentView = hostingView
    self.hostingView = hostingView
    panel?.setFrame(screen.frame, display: true)
    panel?.orderFrontRegardless()
  }

  func update(scene: BoardScene, style: DigitalInkStyle) {
    hostingView?.rootView = BoardSceneView(scene: scene, style: style)
  }

  func hide() {
    panel?.orderOut(nil)
  }
}
