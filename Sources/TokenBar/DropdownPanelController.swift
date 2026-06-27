import AppKit

/// A NSPopover replacement that mimics the macOS Control Center dropdown
/// (Wi-Fi / battery menu): no anchor arrow, transient close (outside click /
/// Esc / app deactivate), Liquid-Glass `.popover` material, and a faster
/// open/close animation than NSPopover's default ~200ms.
///
/// Public surface intentionally mirrors the subset of `NSPopover` that
/// `StatusItemController` already uses, so swapping the call sites is a
/// near-mechanical edit.
@MainActor
final class DropdownPanelController: NSObject {
    /// Borderless panels are non-key by default — override so SwiftUI controls
    /// inside the dropdown receive keyboard focus (and our Esc local-monitor
    /// fires reliably). `performClose` is rerouted into our controller's
    /// graceful close path; the default implementation beeps on a borderless
    /// window because there's no real close button to "press".
    private final class KeyablePanel: NSPanel {
        weak var controller: DropdownPanelController?
        override var canBecomeKey: Bool { true }
        override func performClose(_ sender: Any?) {
            if let controller {
                controller.performClose(sender)
            } else {
                close()
            }
        }
    }

    private let panel: KeyablePanel
    private let effect: NSVisualEffectView

    /// Gap between the menu bar (positioning view's bottom) and the panel top.
    private let edgeGap: CGFloat = 0
    /// Corner radius of the panel chrome — tuned to match NSPopover's default
    /// curvature on macOS Tahoe.
    private static let cornerRadius: CGFloat = 14
    /// Open animation duration (sec). Tuned to feel like Control Center.
    private let openDuration: CFTimeInterval = 0.14
    /// Close animation duration (sec). Slightly shorter than open.
    private let closeDuration: CFTimeInterval = 0.10

    var animates: Bool = true
    var onClose: (() -> Void)?

    private weak var anchorView: NSView?
    private var anchorRect: NSRect = .zero
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var isClosing = false
    private(set) var isShown = false

    var contentViewController: NSViewController? {
        didSet {
            oldValue?.view.removeFromSuperview()
            if let view = contentViewController?.view {
                view.translatesAutoresizingMaskIntoConstraints = false
                effect.addSubview(view)
                NSLayoutConstraint.activate([
                    view.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
                    view.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
                    view.topAnchor.constraint(equalTo: effect.topAnchor),
                    view.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
                ])
            }
        }
    }

    var contentSize: NSSize = NSSize(width: 360, height: 480) {
        didSet {
            guard isShown else { return }
            // Keep the panel anchored to its current top edge (and x) and
            // grow/shrink downwards. Recomputing `idealFrame` here would
            // snap x back to the anchor's midX on every resize tick, which
            // reads as the panel "resetting position" mid-drag.
            let current = panel.frame
            let newFrame = NSRect(
                x: current.minX,
                y: current.maxY - contentSize.height,
                width: contentSize.width,
                height: contentSize.height)
            if animates {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    ctx.allowsImplicitAnimation = true
                    panel.animator().setFrame(newFrame, display: true)
                }
            } else {
                panel.setFrame(newFrame, display: true)
            }
        }
    }

    override init() {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 480),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false

        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        // `maskImage` is the supported way to clip an NSVisualEffectView to a
        // non-rectangular shape — both the material and the window shadow
        // follow the alpha of this image, so the dropdown reads as a single
        // rounded card with no rectangular corners poking out behind it.
        effect.maskImage = Self.roundedRectMask(radius: Self.cornerRadius)

        panel.contentView = effect
        self.panel = panel
        self.effect = effect
        super.init()
        panel.controller = self
    }

    /// Nine-slice rounded-rect alpha mask sized for `NSVisualEffectView.maskImage`.
    /// The cap insets keep the corners crisp while the center stretches with
    /// the panel.
    private static func roundedRectMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(
            size: NSSize(width: edge, height: edge),
            flipped: false
        ) { rect in
            let path = NSBezierPath(
                roundedRect: rect, xRadius: radius, yRadius: radius)
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.capInsets = NSEdgeInsets(
            top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    /// Shows the panel anchored below `positioningRect` in `positioningView`.
    /// The `preferredEdge` argument is accepted to stay source-compatible with
    /// NSPopover but ignored — the panel always drops down from the menu bar.
    func show(
        relativeTo positioningRect: NSRect,
        of positioningView: NSView,
        preferredEdge: NSRectEdge
    ) {
        _ = preferredEdge
        anchorView = positioningView
        anchorRect = positioningRect
        let frame = idealFrame(for: contentSize)

        if animates {
            // Start slightly above the resting position and transparent, then
            // settle in: mimics Control Center's quick drop-in.
            let startFrame = frame.offsetBy(dx: 0, dy: 8)
            panel.alphaValue = 0
            panel.setFrame(startFrame, display: false)
            panel.orderFrontRegardless()
            panel.makeKey()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = openDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ctx.allowsImplicitAnimation = true
                panel.animator().alphaValue = 1
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.alphaValue = 1
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panel.makeKey()
        }

        isShown = true
        isClosing = false
        installEventMonitors()
    }

    func performClose(_ sender: Any?) {
        guard isShown, !isClosing else { return }
        isClosing = true
        removeEventMonitors()

        if animates {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = closeDuration
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                ctx.allowsImplicitAnimation = true
                panel.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.finishClose() }
            })
        } else {
            finishClose()
        }
    }

    private func finishClose() {
        panel.orderOut(nil)
        isShown = false
        isClosing = false
        onClose?()
    }

    // MARK: - Layout

    private func idealFrame(for size: NSSize) -> NSRect {
        guard let view = anchorView,
              let viewWindow = view.window,
              let screen = viewWindow.screen ?? NSScreen.main
        else { return NSRect(origin: .zero, size: size) }
        let anchorScreen = viewWindow.convertToScreen(view.convert(anchorRect, to: nil))
        let vf = screen.visibleFrame
        var x = anchorScreen.midX - size.width / 2
        // Anchor the panel top to the screen's visible-area top (= the menu
        // bar's bottom edge). Using the status-item button's minY can land a
        // pixel inside the menu bar on Tahoe, so we clamp to vf.maxY instead.
        var y = vf.maxY - size.height - edgeGap
        x = max(vf.minX + 4, min(x, vf.maxX - size.width - 4))
        if y < vf.minY + 4 { y = vf.minY + 4 }
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    // MARK: - Transient behavior (outside click / Esc / app deactivate)

    private func installEventMonitors() {
        // Capture window identities up front (in main-actor context) and
        // forward only Sendable values into the monitor closure — NSEvent /
        // NSWindow are non-Sendable under Swift 6 strict concurrency.
        let anchorWindowID = anchorView?.window.map(ObjectIdentifier.init)
        let panelID = ObjectIdentifier(panel)
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            let type = event.type
            // keyCode asserts on non-keyboard events, so only read it when
            // the event actually is a keyDown.
            let keyCode: UInt16 = (type == .keyDown) ? event.keyCode : 0
            let eventWindowID = event.window.map(ObjectIdentifier.init)
            let consumed: Bool = MainActor.assumeIsolated {
                guard let self else { return false }
                if type == .keyDown {
                    if keyCode == 53 { // Esc
                        self.performClose(nil)
                        return true
                    }
                    return false
                }
                // Clicks inside the panel are normal interactions; clicks on
                // the status-item button must be left alone so its action can
                // toggle us closed (otherwise we'd close here and the button
                // would immediately re-open us).
                if eventWindowID == panelID { return false }
                if eventWindowID == anchorWindowID { return false }
                self.performClose(nil)
                return false
            }
            return consumed ? nil : event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.performClose(nil) }
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.performClose(nil) }
        }
    }

    private func removeEventMonitors() {
        if let m = localMonitor { NSEvent.removeMonitor(m); localMonitor = nil }
        if let m = globalMonitor { NSEvent.removeMonitor(m); globalMonitor = nil }
        if let o = resignObserver {
            NotificationCenter.default.removeObserver(o)
            resignObserver = nil
        }
    }
}
