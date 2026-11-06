import AppKit
import Foundation

/// Follows the frontmost app so each app can have its own Vietnamese/English
/// state (see `AppMode`), and tells the key tap when VietIME's own windows are
/// in front so they receive raw keys.
final class AppTracker {
    static let shared = AppTracker()

    /// The frontmost app other than VietIME itself.
    private(set) var frontApp: (bundleID: String, name: String)?
    /// True while VietIME's own app (Settings window...) is frontmost. Cached so
    /// the tap never has to ask the system per keystroke.
    private(set) var ownAppIsFront = false

    private var observer: NSObjectProtocol?
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    /// Whether the front app was "off" when its mode was last applied, so a rule
    /// change from Settings can tell that it just left "off" and refresh the icon.
    private var appliedOff = false

    var frontAppIsOff: Bool {
        guard let id = frontApp?.bundleID else { return false }
        return Settings.shared.mode(for: id) == .off
    }

    /// Starts observing and applies the mode of the app that is in front right now. Idempotent.
    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.activated(app)
        }
        if let app = NSWorkspace.shared.frontmostApplication { activated(app) }
    }

    private func activated(_ app: NSRunningApplication) {
        let handler = KeyHandler.shared
        if app.processIdentifier == ownPID {
            ownAppIsFront = true
            handler.resetBuffer()
            return
        }
        ownAppIsFront = false

        let settings = Settings.shared
        let wasOff = frontAppIsOff
        let before = handler.enabled

        // Remember the state we leave behind.
        if let old = frontApp?.bundleID {
            let oldMode = settings.mode(for: old)
            if oldMode != .off, settings.perAppMemory || oldMode == .auto,
               settings.appMemory[old] != before {
                settings.appMemory[old] = before
            }
        }

        if let id = app.bundleIdentifier {
            let name = app.localizedName ?? id
            frontApp = (id, name)
            if settings.appNames[id] != name { settings.appNames[id] = name }
        } else {
            // A bare executable (some Java/Python tools) has no bundle id, so no
            // per-app rule can apply to it, and the previous app's must not:
            // its "off" mode, "Từng phím", hotkey memory and menu entry.
            frontApp = nil
        }
        handler.resetBuffer(forgetLastWord: true)

        applyMode()
        appliedOff = frontAppIsOff
        if handler.enabled != before || wasOff || frontAppIsOff {
            handler.onStateChange?(.appSwitch)
        }
    }

    /// Applies the front app's mode to `KeyHandler.enabled` (no notification).
    private func applyMode() {
        guard let id = frontApp?.bundleID else { return }
        let settings = Settings.shared
        switch settings.mode(for: id) {
        case .vietnamese: KeyHandler.shared.enabled = true
        case .english: KeyHandler.shared.enabled = false
        case .auto:
            if settings.perAppMemory, let remembered = settings.appMemory[id] {
                KeyHandler.shared.enabled = remembered
            }
        case .off: break
        }
    }

    /// The user changed the front app's mode (menu or Settings): apply it now.
    func reapply() {
        let before = KeyHandler.shared.enabled
        let wasOff = appliedOff
        applyMode()
        appliedOff = frontAppIsOff
        if KeyHandler.shared.enabled != before || wasOff || frontAppIsOff {
            KeyHandler.shared.onStateChange?(.appSwitch)
        }
    }

    /// Records `enabled` for the front app after a hotkey toggle.
    func rememberCurrentState(_ enabled: Bool) {
        guard let id = frontApp?.bundleID else { return }
        if Settings.shared.appMemory[id] != enabled { Settings.shared.appMemory[id] = enabled }
    }
}
