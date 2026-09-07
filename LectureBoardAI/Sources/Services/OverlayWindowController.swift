import AppKit
import LectureBoardCore
import SwiftUI

@MainActor
protocol OverlayWindowControlling: AnyObject {
  func showDemo(scene: BoardScene, style: DigitalInkStyle, on screen: NSScreen?)
  func render(scene: BoardScene, style: DigitalInkStyle, in frame: CGRect)
  func hide()
}

@MainActor
final class OverlayWindowController: OverlayWindowControlling {
  private var panel: NSPanel?
  private var hostingView: NSHostingView<BoardSceneView>?

  func showDemo(scene: BoardScene, style: DigitalInkStyle, on screen: NSScreen?) {
    guard let screen else { return }
    render(scene: scene, style: style, frame: screen.frame, screen: screen)
  }

  func render(scene: BoardScene, style: DigitalInkStyle, in frame: CGRect) {
    let rawWidth = frame.size.width
    let rawHeight = frame.size.height
    let values = [
      frame.origin.x,
      frame.origin.y,
      rawWidth,
      rawHeight,
      frame.origin.x + rawWidth,
      frame.origin.y + rawHeight,
    ]
    guard
      values.allSatisfy(\.isFinite),
      rawWidth > 0,
      rawHeight > 0
    else {
      hide()
      return
    }

    let containingScreens = NSScreen.screens.filter { screen in
      frame.minX >= screen.frame.minX
        && frame.minY >= screen.frame.minY
        && frame.maxX <= screen.frame.maxX
        && frame.maxY <= screen.frame.maxY
    }
    guard containingScreens.count == 1, let screen = containingScreens.first else {
      hide()
      return
    }

    render(scene: scene, style: style, frame: frame, screen: screen)
  }

  private func render(
    scene: BoardScene,
    style: DigitalInkStyle,
    frame: CGRect,
    screen: NSScreen
  ) {

    if panel == nil {
      let panel = NSPanel(
        contentRect: frame,
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
      panel.collectionBehavior = [
        .canJoinAllApplications,
        .canJoinAllSpaces,
        .fullScreenAuxiliary,
        .ignoresCycle,
      ]
      panel.isReleasedWhenClosed = false
      self.panel = panel
    }

    let rootView = BoardSceneView(scene: scene, style: style)
    if let hostingView {
      hostingView.rootView = rootView
    } else {
      let hostingView = NSHostingView(rootView: rootView)
      hostingView.frame = panel?.contentView?.bounds ?? CGRect(origin: .zero, size: frame.size)
      hostingView.autoresizingMask = [.width, .height]
      panel?.contentView = hostingView
      self.hostingView = hostingView
    }
    panel?.setFrame(frame, display: true)
    panel?.orderFrontRegardless()
  }

  func hide() {
    panel?.orderOut(nil)
  }
}
