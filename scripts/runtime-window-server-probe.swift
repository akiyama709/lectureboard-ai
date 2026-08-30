import CoreGraphics
import Foundation

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard
  let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
    as? [[String: Any]],
  !windows.isEmpty
else {
  exit(1)
}

let hasIdentifiableWindow = windows.contains { window in
  window[kCGWindowNumber as String] != nil
    && window[kCGWindowOwnerPID as String] != nil
}
exit(hasIdentifiableWindow ? 0 : 1)
