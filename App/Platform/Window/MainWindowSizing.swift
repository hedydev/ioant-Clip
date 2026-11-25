#if os(macOS)
import AppKit
import SwiftUI

/// One-time upgrade of the old undersized restored window. Subsequent launches
/// defer to native window restoration; do not continuously resize user windows.
struct MainWindowSizing: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowProbe { WindowProbe() }
    func updateNSView(_ nsView: WindowProbe, context: Context) {}

    final class WindowProbe: NSView {
        private static let migrationKey = "ioant.clip.window.initialSize.v2"
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !ClipPreferencesScope.defaults.bool(forKey: Self.migrationKey) else { return }
            DispatchQueue.main.async { [weak window] in
                guard let window, !ClipPreferencesScope.defaults.bool(forKey: Self.migrationKey),
                      let screen = window.screen ?? NSScreen.main else { return }
                // Full screen is user-controlled. Never resize a full-screen window.
                guard !window.styleMask.contains(.fullScreen) else { return }
                let visible = screen.visibleFrame.insetBy(dx: 12, dy: 12)
                let current = window.frame
                let desired = PresentationMetrics.initialWindowSize(available: visible.size, current: current.size)
                if current.width < desired.width || current.height < desired.height {
                    let x = min(max(current.midX - desired.width / 2, visible.minX), visible.maxX - desired.width)
                    let y = min(max(current.midY - desired.height / 2, visible.minY), visible.maxY - desired.height)
                    window.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: desired), display: true)
                }
                ClipPreferencesScope.defaults.set(true, forKey: Self.migrationKey)
            }
        }
    }
}
#endif
