import AppKit

/// What the menu bar icon shows.
enum StatusIconState: Hashable {
    case vietnamese    // solid badge, "VI" knocked out
    case english       // outlined badge "EN"
    case noPermission  // dashed outline "VI" + dot at the top right
    case off           // front app is set to .off: dimmed "EN" outline with a slash
    case blocked       // Secure Input keeps keys from the tap: "VI" outline with a slash
}

/// Template images drawn in code, so macOS tints them for light/dark menu bars.
enum StatusIcon {
    // Wide enough for the EN badge and the no-permission dot; fixed so the status item never resizes.
    static let size = NSSize(width: 27, height: 18)
    private static var cache: [StatusIconState: NSImage] = [:]

    static func image(for state: StatusIconState) -> NSImage {
        if let cached = cache[state] { return cached }
        let image = NSImage(size: size, flipped: true) { _ in
            draw(state)
            return true
        }
        image.isTemplate = true
        cache[state] = image
        return image
    }

    // Badge sizes from the design: 15pt tall, 4pt corners, "VI" 20pt wide, "EN" 24.5pt wide,
    // centred in the fixed image so the badge sits on the menu bar's midline.
    private static let badgeHeight: CGFloat = 15
    private static let radius: CGFloat = 4

    private static func badge(width: CGFloat) -> NSRect {
        NSRect(x: (size.width - width) / 2, y: (size.height - badgeHeight) / 2, width: width, height: badgeHeight)
    }

    private static func draw(_ state: StatusIconState) {
        let ink = NSColor.black
        let vi = badge(width: 20)
        let en = badge(width: 24.5)
        switch state {
        case .vietnamese:
            ink.setFill()
            NSBezierPath(roundedRect: vi, xRadius: radius, yRadius: radius).fill()
            drawText("VI", in: vi, color: ink, knockOut: true)
        case .english:
            outline(en, color: ink, dashed: false)
            drawText("EN", in: en, color: ink, knockOut: false)
        case .noPermission:
            outline(vi, color: ink, dashed: true)
            drawText("VI", in: vi, color: ink, knockOut: false)
            let center = NSPoint(x: vi.maxX - 0.5, y: vi.minY + 2)
            // Ring knocked out of the badge, then the dot itself.
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSBezierPath(ovalIn: NSRect(x: center.x - 3.6, y: center.y - 3.6, width: 7.2, height: 7.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            ink.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - 2.6, y: center.y - 2.6, width: 5.2, height: 5.2)).fill()
        case .off:
            let dim = ink.withAlphaComponent(0.5)
            outline(en, color: dim, dashed: false)
            drawText("EN", in: en, color: dim, knockOut: false)
            drawSlash(across: en, color: ink)
        case .blocked:
            outline(vi, color: ink, dashed: false)
            drawText("VI", in: vi, color: ink, knockOut: false)
            drawSlash(across: vi, color: ink)
        }
    }

    /// A diagonal stroke over the badge, with a knocked-out gap around it.
    private static func drawSlash(across badge: NSRect, color: NSColor) {
        let slash = NSBezierPath()
        slash.move(to: NSPoint(x: badge.minX + 2.25, y: badge.maxY))
        slash.line(to: NSPoint(x: badge.maxX - 1.25, y: badge.minY))
        slash.lineCapStyle = .round
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        slash.lineWidth = 3.8
        NSColor.black.setStroke()
        slash.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceOver
        slash.lineWidth = 1.5
        color.setStroke()
        slash.stroke()
    }

    private static func outline(_ badge: NSRect, color: NSColor, dashed: Bool) {
        let path = NSBezierPath(roundedRect: badge.insetBy(dx: 0.75, dy: 0.75), xRadius: radius - 0.5, yRadius: radius - 0.5)
        path.lineWidth = 1.5
        if dashed { path.setLineDash([2.6, 2], count: 2, phase: 0) }
        color.setStroke()
        path.stroke()
    }

    private static func drawText(_ text: String, in badge: NSRect, color: NSColor, knockOut: Bool) {
        let kern: CGFloat = 0.4
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
            .foregroundColor: color,
            .kern: kern,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let origin = NSPoint(x: badge.midX - (size.width - kern) / 2, y: badge.midY - size.height / 2)
        if knockOut { NSGraphicsContext.current?.compositingOperation = .destinationOut }
        string.draw(at: origin)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    }
}
