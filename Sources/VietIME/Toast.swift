import AppKit

/// The small dark pill shown under the menu bar when the state changes.
/// Borderless, non-activating and click-through: it never takes focus.
final class Toast {
    /// `mode` is the front app's rule, shown as the subtitle's second part; nil (hotkey) shows only the app name.
    static func show(vietnamese: Bool, app: String?, mode: AppMode?) {
        var parts: [String] = []
        if let app, !app.isEmpty { parts.append(app) }
        if let mode {
            switch mode {
            case .auto: parts.append("tự nhớ")
            case .vietnamese: parts.append("luôn tiếng Việt")
            case .english: parts.append("luôn tiếng Anh")
            case .off: parts.append("tắt VietIME")
            }
        }
        shared.present(vietnamese: vietnamese, subtitle: parts.joined(separator: " · "))
    }

    private static let shared = Toast()
    private let panel: NSPanel
    private var token = 0
    private var hideWork: DispatchWorkItem?

    private init() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 160, height: 44),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.alphaValue = 0
    }

    private func present(vietnamese: Bool, subtitle: String) {
        token += 1
        hideWork?.cancel()

        let (content, size) = makeContent(vietnamese: vietnamese, subtitle: subtitle)
        panel.contentView = content
        panel.setContentSize(size)

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        let area = screen.visibleFrame  // top edge = bottom of the menu bar
        panel.setFrameOrigin(NSPoint(x: (area.midX - size.width / 2).rounded(), y: (area.maxY - size.height - 12).rounded()))

        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            panel.animator().alphaValue = 1
        }

        let current = token
        let work = DispatchWorkItem { [weak self] in self?.dismiss(token: current) }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
    }

    private func dismiss(token current: Int) {
        guard current == token else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, current == self.token else { return }
            self.panel.orderOut(nil)
        })
    }

    private func makeContent(vietnamese: Bool, subtitle: String) -> (NSView, NSSize) {
        let effect = NSVisualEffectView()
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true

        let badge = ToastBadge(text: vietnamese ? "VI" : "EN", filled: vietnamese)

        let title = NSTextField(labelWithString: vietnamese ? "Tiếng Việt" : "English")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .white
        let texts = NSStackView(views: [title])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 0
        if !subtitle.isEmpty {
            let sub = NSTextField(labelWithString: subtitle)
            sub.font = .systemFont(ofSize: 11)
            sub.textColor = NSColor(white: 0.78, alpha: 1)
            sub.lineBreakMode = .byTruncatingTail
            texts.addArrangedSubview(sub)
        }

        let row = NSStackView(views: [badge, texts])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(row)
        let insets = NSEdgeInsets(top: 9, left: 10, bottom: 9, right: 16)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: insets.left),
            row.topAnchor.constraint(equalTo: effect.topAnchor, constant: insets.top),
        ])
        let fit = row.fittingSize
        let size = NSSize(width: ceil(fit.width + insets.left + insets.right), height: ceil(fit.height + insets.top + insets.bottom))
        effect.frame = NSRect(origin: .zero, size: size)
        return (effect, size)
    }
}

/// "VI" (solid white) or "EN" (white outline).
private final class ToastBadge: NSView {
    private let text: String
    private let filled: Bool
    private let attributes: [NSAttributedString.Key: Any]

    init(text: String, filled: Bool) {
        self.text = text
        self.filled = filled
        attributes = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: filled ? NSColor(red: 0.165, green: 0.165, blue: 0.173, alpha: 1) : NSColor.white,
            .kern: 0.4,
        ]
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(NSAttributedString(string: text, attributes: attributes).size().width) + 12, height: 20)
    }

    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds
        if filled {
            NSColor.white.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        } else {
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.75, dy: 0.75), xRadius: 4.5, yRadius: 4.5)
            path.lineWidth = 1.5
            NSColor.white.setStroke()
            path.stroke()
        }
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        string.draw(at: NSPoint(x: rect.midX - (size.width - 0.4) / 2, y: rect.midY - size.height / 2))
    }
}
