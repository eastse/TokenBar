import AppKit
import SwiftUI

/// Reusable backdrop for popover/panel content. Uses Liquid Glass on
/// macOS 26+ and falls back to an `NSVisualEffectView` (.popover material,
/// behindWindow) on older systems. Apply with `.background(GlassBackground())`.
///
/// Layering note: NSPopover already draws its own vibrant chrome behind the
/// content view. We deliberately apply the material to the *content* (this
/// view) rather than trying to strip the popover's frame view — a clear glass
/// layer over the system chrome reads as one surface, while hacking the
/// popover's private background view is fragile across OS releases.
struct GlassBackground: View {
    var cornerRadius: CGFloat = 0

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer {
                Rectangle()
                    .fill(.clear)
                    .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            VisualEffectBackground(material: .popover)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

/// Popover root backdrop: HUD-grade translucency sampling what's behind the
/// window (the .popover chrome reads nearly opaque in dark mode, burying the
/// wallpaper blur that makes Liquid Glass cards come alive).
struct PopoverBackdrop: View {
    var body: some View {
        VisualEffectBackground(material: .hudWindow)
    }
}

/// AppKit visual-effect bridge.
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Drag the host window from the SwiftUI view it backs. Drop into
/// `.background(WindowDragHandle())` on a region that should act as a
/// title-bar grip — SwiftUI controls on top still hit-test first, so only
/// the empty pixels between them trigger window drags.
struct WindowDragHandle: NSViewRepresentable {
    final class HandleView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
    func makeNSView(context: Context) -> NSView { HandleView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
