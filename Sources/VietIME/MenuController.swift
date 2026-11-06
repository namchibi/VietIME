import AppKit

/// The status item's menu. Rebuilt from scratch every time it opens, so it always reflects live state.
final class MenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()
    /// Called after the user changed something from the menu (toggle, app mode), so the icon can refresh.
    var onChange: (() -> Void)?
    /// Set by the app delegate while Secure Input blocks the tap; shown as a warning at the top.
    var secureInputHolder: String?

    override init() {
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuild()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    // MARK: - Building

    private struct ModeChoice {
        let bundleID: String
        let appName: String
        let mode: AppMode
    }

    private static let modeTitles: [(AppMode, String)] = [
        (.auto, "Tự nhớ"), (.vietnamese, "Luôn tiếng Việt"), (.english, "Luôn tiếng Anh"), (.off, "Tắt VietIME"),
    ]

    private func rebuild() {
        menu.removeAllItems()
        let handler = KeyHandler.shared

        let toggleItem = NSMenuItem()
        toggleItem.view = ToggleRowView(isOn: handler.enabled, hint: "Bật/tắt nhanh: \(Settings.shared.hotkey.display)") {
            // Same bookkeeping as the hotkey (next launch, per-app memory), no toast.
            KeyHandler.shared.userToggle()
            KeyHandler.shared.onStateChange?(.menu)
        }
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        if let holder = secureInputHolder {
            for (text, color) in [
                ("⚠︎ Secure Input đang bật — \(holder)", NSColor.labelColor),
                ("macOS không cho VietIME nhận phím lúc này.", NSColor.secondaryLabelColor),
                ("Rời ô mật khẩu hoặc thoát app đó để gõ lại.", NSColor.secondaryLabelColor),
            ] {
                let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
                item.isEnabled = false
                item.attributedTitle = NSAttributedString(string: text, attributes: [
                    .font: NSFont.menuFont(ofSize: 0), .foregroundColor: color,
                ])
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        if let last = handler.lastConversionForMenu {
            let header = NSMenuItem(title: "Từ vừa gõ", action: nil, keyEquivalent: "")
            header.isEnabled = false
            header.attributedTitle = NSAttributedString(string: "Từ vừa gõ", attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
            menu.addItem(header)

            let pair = NSMenuItem(title: "\(last.raw) → \(last.result)", action: nil, keyEquivalent: "")
            pair.isEnabled = false
            pair.attributedTitle = NSAttributedString(string: "\(last.raw) → \(last.result)", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                .foregroundColor: NSColor.labelColor,
            ])
            menu.addItem(pair)

            let shown = last.raw.count > 24 ? String(last.raw.prefix(24)) + "…" : last.raw
            let keep = NSMenuItem(title: "Luôn giữ “\(shown)” là tiếng Anh", action: #selector(keepEnglish), keyEquivalent: "")
            keep.target = self
            menu.addItem(keep)
            menu.addItem(.separator())
        }

        if let app = handler.frontApp {
            let current = Settings.shared.mode(for: app.bundleID)
            let currentTitle = Self.modeTitles.first { $0.0 == current }?.1 ?? ""
            let appItem = NSMenuItem(title: "Trong \(app.name) · \(currentTitle)", action: nil, keyEquivalent: "")
            // "Trong Slack" left, the current mode right-aligned in grey, as in the design.
            let paragraph = NSMutableParagraphStyle()
            paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 212)]
            let title = NSMutableAttributedString(string: "Trong \(app.name)\t", attributes: [
                .font: NSFont.menuFont(ofSize: 0), .paragraphStyle: paragraph,
            ])
            title.append(NSAttributedString(string: currentTitle, attributes: [
                .font: NSFont.menuFont(ofSize: 0), .paragraphStyle: paragraph,
                .foregroundColor: NSColor.secondaryLabelColor,
            ]))
            appItem.attributedTitle = title
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for (mode, title) in Self.modeTitles {
                let item = NSMenuItem(title: title, action: #selector(chooseMode(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ModeChoiceBox(ModeChoice(bundleID: app.bundleID, appName: app.name, mode: mode))
                item.state = mode == current ? .on : .off
                submenu.addItem(item)
            }
            appItem.submenu = submenu
            menu.addItem(appItem)
            menu.addItem(.separator())
        }

        let settings = NSMenuItem(title: "Cài đặt…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Thoát VietIME", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    // NSMenuItem.representedObject wants a reference type.
    private final class ModeChoiceBox: NSObject {
        let choice: ModeChoice
        init(_ choice: ModeChoice) { self.choice = choice }
    }

    // MARK: - Actions

    @objc private func keepEnglish() {
        KeyHandler.shared.keepLastConversionEnglish()
        onChange?()
    }

    @objc private func chooseMode(_ sender: NSMenuItem) {
        guard let choice = (sender.representedObject as? ModeChoiceBox)?.choice else { return }
        let settings = Settings.shared
        if choice.mode == .auto {
            // "Tự nhớ" is the default, so the app leaves the Settings list.
            settings.removeApp(choice.bundleID)
        } else {
            settings.appModes[choice.bundleID] = choice.mode
        }
        if settings.appNames[choice.bundleID] != choice.appName {
            settings.appNames[choice.bundleID] = choice.appName
        }
        KeyHandler.shared.reapplyAppMode()
        onChange?()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        SettingsWindowController.shared.show()
    }
}

/// The first menu row: "Tiếng Việt" + hint on the left, a switch on the right.
private final class ToggleRowView: NSView {
    private let onToggle: () -> Void
    private let toggle = NSSwitch()

    init(isOn: Bool, hint: String, onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        super.init(frame: NSRect(x: 0, y: 0, width: 270, height: 42))
        autoresizingMask = [.width]

        let title = NSTextField(labelWithString: "Tiếng Việt")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        let subtitle = NSTextField(labelWithString: hint)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        let texts = NSStackView(views: [title, subtitle])
        texts.orientation = .vertical
        texts.alignment = .leading
        texts.spacing = 1
        texts.translatesAutoresizingMaskIntoConstraints = false

        toggle.state = isOn ? .on : .off
        toggle.controlSize = .small
        toggle.target = self
        toggle.action = #selector(flip)
        toggle.setAccessibilityLabel("Gõ tiếng Việt")
        toggle.translatesAutoresizingMaskIntoConstraints = false

        addSubview(texts)
        addSubview(toggle)
        NSLayoutConstraint.activate([
            texts.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            texts.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
            texts.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -8),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    /// A click on the row (not only on the switch) toggles too.
    override func mouseDown(with event: NSEvent) {
        toggle.state = toggle.state == .on ? .off : .on
        flip()
    }

    @objc private func flip() {
        onToggle()
        // Let the switch animation land, then close the menu so the icon and toast are visible.
        let menu = enclosingMenuItem?.menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { menu?.cancelTracking() }
    }
}
