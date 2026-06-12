import AppKit
import SwiftUI

/// Owns the standalone settings window (gear button, Cmd-comma, `--settings`).
/// One window per app, kept alive across closes so its position persists;
/// `show()` re-fronts it. The popover stays `.transient` and uninvolved —
/// the window carries its own live preview instead of pinning the popover.
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        let firstShow = !window.isVisible
        // Accessory apps are never frontmost; activate or the window opens
        // behind whatever app currently has focus.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Dead-center on open (but never yank an already-open window).
        // NSWindow.center() sits noticeably above center, so place by hand —
        // and only after ordering front: the hosting view inflates the frame
        // by the title-bar safe area (580 -> 612) on its first layout, so
        // centering the pre-show frame sat ~16pt low. The move lands in the
        // same runloop turn, before the window is on screen.
        if firstShow {
            center(window)
        }
    }

    private func center(_ window: NSWindow) {
        guard let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }
        let visible = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visible.midX - window.frame.width / 2,
            y: visible.midY - window.frame.height / 2))
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: SettingsWindowView())
        let window = NSWindow(contentViewController: host)
        // NSWindow(contentViewController:) sizes lazily (the frame is still
        // 1x0 at show time, which broke the centering math) — force the
        // SwiftUI fitting size up front.
        window.setContentSize(host.view.fittingSize)
        window.title = "TokenBar Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        // The glass backdrop runs under the title bar (the popover look);
        // scroll views inset their content via the safe area.
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        // The hosting view inflates the frame by the title-bar safe area
        // (580 -> 612) in a layout pass after the first order-front that no
        // amount of layoutIfNeeded forces early — re-center once when it
        // lands so the first open sits dead-center (one-shot; later opens
        // start from the final size and never resize again).
        var token: NSObjectProtocol?
        token = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] notification in
            if let token { NotificationCenter.default.removeObserver(token) }
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.center(window) }
        }
        return window
    }
}
