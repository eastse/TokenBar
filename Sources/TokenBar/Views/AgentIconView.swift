import AppKit
import SwiftUI
import TokenBarCore

/// Brand-icon disc for an agent, port of the clients.ts iconRaw/iconType
/// registry (the SVGs ship as bundle resources, rendered via NSImage's
/// native SVG support — the codexbar approach). 'mono' glyphs tint white
/// over the brand-color disc; 'full' icons carry their own design and fill
/// the disc as-is; agents without an icon keep the initial-letter disc.
@MainActor
enum AgentIconImage {
    fileprivate static let monoIds: Set<String> = [
        "claude", "gemini", "opencode", "copilot", "cursor", "amp", "pi",
        "kimi", "qwen", "warp",
    ]
    fileprivate static let fullIds: Set<String> = [
        "codex", "droid", "kilocode", "kilo", "synthetic", "codebuff",
        "antigravity", "kiro",
        // Official brand icons for the newer local clients (png/svg).
        "cline", "jcode", "micode", "gjc",
    ]

    /// Clients that share another client's brand icon. The Antigravity CLI is
    /// the same product family as the Antigravity IDE and uses its logo.
    fileprivate static let iconAliases: [String: String] = [
        "antigravity-cli": "antigravity",
    ]

    /// Full icons whose mark is dark and mostly transparent, so they need a
    /// light disc behind to stay visible on a dark popover.
    fileprivate static let lightBackedIds: Set<String> = ["cline"]

    /// Resolve the id whose `agent-icons/<id>.svg` should render for a client.
    fileprivate static func iconId(_ clientId: String) -> String {
        iconAliases[clientId] ?? clientId
    }

    private static var cache: [String: NSImage] = [:]

    fileprivate static func sourceImage(_ id: String) -> NSImage? {
        if let cached = cache[id] { return cached }
        guard monoIds.contains(id) || fullIds.contains(id) else { return nil }
        let bundle = Bundle.tokenBarResources
        // SVG (vector) preferred; some brand icons ship only as PNG.
        guard let url = bundle.url(
                forResource: id, withExtension: "svg", subdirectory: "agent-icons")
                ?? bundle.url(
                    forResource: id, withExtension: "png", subdirectory: "agent-icons"),
              let image = NSImage(contentsOf: url)
        else { return nil }
        cache[id] = image
        return image
    }

    static func image(
        clientId: String, size: CGFloat, monochrome: Bool = false, dark: Bool = true
    ) -> NSImage {
        let style = ClientRegistry.style(clientId)
        let iconId = Self.iconId(clientId)
        let output = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            if monochrome {
                let ink: NSColor = dark ? .white : .black
                if let source = sourceImage(iconId) {
                    let mark = rect.insetBy(dx: size * 0.08, dy: size * 0.08)
                    if fullIds.contains(iconId) {
                        drawWhiteMarkMask(source, in: mark, color: ink, size: size)
                    } else {
                        source.draw(in: mark, from: .zero, operation: .sourceOver, fraction: 1)
                        ink.setFill()
                        mark.fill(using: .sourceIn)
                    }
                } else {
                    let text = String(style.displayName.prefix(1)).uppercased()
                    let font = NSFont.systemFont(ofSize: size * 0.72, weight: .bold)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: ink,
                    ]
                    let textSize = text.size(withAttributes: attrs)
                    text.draw(
                        at: NSPoint(
                            x: rect.midX - textSize.width / 2,
                            y: rect.midY - textSize.height / 2),
                        withAttributes: attrs)
                }
                return true
            }

            if fullIds.contains(iconId), let source = sourceImage(iconId) {
                NSGraphicsContext.current?.saveGraphicsState()
                NSBezierPath(ovalIn: rect).addClip()
                if lightBackedIds.contains(iconId) {
                    NSColor.white.setFill()
                    NSBezierPath(ovalIn: rect).fill()
                }
                source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                NSGraphicsContext.current?.restoreGraphicsState()
            } else {
                NSColor(hex: style.color).setFill()
                NSBezierPath(ovalIn: rect).fill()

                if monoIds.contains(iconId), let source = sourceImage(iconId) {
                    let mark = rect.insetBy(dx: size * 0.18, dy: size * 0.18)
                    source.draw(in: mark, from: .zero, operation: .sourceOver, fraction: 1)
                    NSColor.white.setFill()
                    mark.fill(using: .sourceIn)
                } else {
                    let text = String(style.displayName.prefix(1)).uppercased()
                    let font = NSFont.systemFont(ofSize: size * 0.55, weight: .bold)
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: NSColor.white,
                    ]
                    let textSize = text.size(withAttributes: attrs)
                    text.draw(
                        at: NSPoint(
                            x: rect.midX - textSize.width / 2,
                            y: rect.midY - textSize.height / 2),
                        withAttributes: attrs)
                }
            }
            return true
        }
        output.isTemplate = false
        return output
    }

    private static func drawWhiteMarkMask(
        _ source: NSImage, in rect: NSRect, color: NSColor, size: CGFloat
    ) {
        let scale = max(2, Int(size.rounded(.up)))
        let width = scale
        let height = scale
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)
        else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        source.draw(
            in: NSRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        guard let data = rep.bitmapData else { return }
        let bytesPerRow = rep.bytesPerRow
        for y in 0..<height {
            for x in 0..<width {
                let p = data + y * bytesPerRow + x * 4
                let r = Int(p[0])
                let g = Int(p[1])
                let b = Int(p[2])
                let a = Int(p[3])
                let whiteness = min(r, min(g, b))
                let markAlpha = max(0, min(255, (whiteness - 170) * 3))
                p[0] = UInt8(markAlpha)
                p[1] = UInt8(markAlpha)
                p[2] = UInt8(markAlpha)
                p[3] = UInt8(a * markAlpha / 255)
            }
        }

        guard let mask = NSImage(size: NSSize(width: width, height: height), flipped: false, drawingHandler: { target in
            rep.draw(in: target)
            return true
        }).cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        NSImage(cgImage: mask, size: rect.size)
            .draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        rect.fill(using: .sourceIn)
        NSGraphicsContext.current?.restoreGraphicsState()
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1)
    }
}

struct AgentIconView: View {
    let clientId: String
    var size: CGFloat = 14

    var body: some View {
        let style = ClientRegistry.style(clientId)
        let iconId = AgentIconImage.iconId(clientId)
        ZStack {
            if AgentIconImage.fullIds.contains(iconId),
               let image = AgentIconImage.sourceImage(iconId)
            {
                ZStack {
                    if AgentIconImage.lightBackedIds.contains(iconId) {
                        Circle().fill(.white)
                    }
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(Circle())
                }
            } else {
                Circle().fill(Color(hex: style.color))
                if AgentIconImage.monoIds.contains(iconId),
                   let image = AgentIconImage.sourceImage(iconId)
                {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size * 0.64, height: size * 0.64)
                        .foregroundStyle(.white)
                } else {
                    Text(String(style.displayName.prefix(1)).uppercased())
                        .font(.system(size: size * 0.55, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
    }
}
