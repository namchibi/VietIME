import AppKit
import Combine
import CoreGraphics
import Foundation
import OSLog
import TelexEngine

enum StateChangeReason { case hotkey, menu, appSwitch }

/// `log stream --predicate 'subsystem == "dev.local.vietime"'` to watch it live.
let tapLog = Logger(subsystem: "dev.local.vietime", category: "tap")

/// Intercepts key presses through a CGEventTap and rewrites the current word
/// by sending backspaces followed by the new Unicode text.
final class KeyHandler {
    static let shared = KeyHandler()

    /// Marks events we post ourselves so the tap lets them through untouched.
    private static let syntheticMarker: Int64 = 0x5649_4554  // "VIET"
    private static let backspaceKey: CGKeyCode = 51
    private static let spaceKey: CGKeyCode = 49
    /// Virtual keys that carry the rewritten text; the Unicode string, not the
    /// key code, is what the app inserts. The first one the user is not holding
    /// down is used: VS Code, Chrome and other apps drop a press of a key that
    /// is physically held, and the key just typed usually still is. Typing
    /// "na" + "f" fast, the "à" went out on A while A was still down, so only
    /// the Delete landed and "này" came out as "ny"; "aa" -> "â" lost the "â"
    /// the same way. A first, as it always was; the others are letters too, so
    /// every app treats them as plain typing.
    private static let textKeys: [CGKeyCode] = [0, 12, 6, 7, 8, 9, 11]  // a q z x c v b

    /// A key from `textKeys` that is not held down right now.
    private static func freeTextKey() -> CGKeyCode {
        textKeys.first { !CGEventSource.keyState(.hidSystemState, key: $0) } ?? textKeys[0]
    }

    /// Apps whose text fields inline-complete what is typed ("ho" ->
    /// "ho@gmail.com"), so a rewrite starts with the placeholder there. Only
    /// there: apps that drop the placeholder would lose one character more
    /// than the rewrite meant to delete ("cacs" -> "ác" instead of "các").
    /// Prefixes cover the beta/dev channels too.
    private static let placeholderAppPrefixes = [
        "com.apple.Safari", "com.apple.Spotlight",
        "com.google.Chrome", "org.chromium", "com.microsoft.edgemac",
        "com.brave.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "company.thebrowser.", "org.mozilla.firefox",
    ]

    /// Vietnamese on/off for the front app. Setting it resets the word buffer.
    var enabled = true { didSet { reset() } }
    /// Called on the main thread when `enabled` changes through the hotkey, the menu or an app switch.
    var onStateChange: ((StateChangeReason) -> Void)?
    /// While true the tap passes everything through (the Settings UI is recording a shortcut).
    var isRecordingHotkey = false

    var frontApp: (bundleID: String, name: String)? { AppTracker.shared.frontApp }
    var frontAppIsOff: Bool { AppTracker.shared.frontAppIsOff }

    /// The last word that was changed, but only when the English dictionary knows
    /// the raw keys; otherwise nil. The check runs when the menu opens, never while typing.
    var lastConversionForMenu: (raw: String, result: String)? {
        guard let last = buffer.lastConverted, SpellCheck.isEnglish(last.raw) else { return nil }
        return last
    }

    private var buffer = TypingBuffer()
    private var tap: CFMachPort?
    private var loopSource: CFRunLoopSource?
    private let source = CGEventSource(stateID: .privateState)
    private var started = false
    /// Built-in English words plus the user's own, rebuilt when the user's list changes.
    private var englishWords = Telex.defaultEnglishWords
    private var englishWordsSink: AnyCancellable?

    private init() {
        englishWordsSink = Settings.shared.$userEnglishWords.sink { [weak self] words in
            self?.englishWords = Telex.defaultEnglishWords.union(words)
        }
    }

    func start() -> Bool {
        if !started {
            started = true
            switch Settings.shared.launchMode {
            case .vietnamese: enabled = true
            case .english: enabled = false
            case .last: enabled = Settings.shared.lastEnabled
            }
            AppTracker.shared.start()
        }
        // Already running: the watchdog and the onboarding poll both call this.
        if tap != nil { return true }

        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { proxy, type, event, _ in
                let t0 = DispatchTime.now().uptimeNanoseconds
                let r = KeyHandler.shared.handle(type, event, proxy: proxy)
                KeyHandler.shared.diag(type, event, result: r, t0: t0)
                return r
            },
            userInfo: nil
        ) else { return false }
        self.tap = tap
        let loopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.loopSource = loopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Stops the tap, e.g. after Accessibility was revoked; `start()` builds a new one.
    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let loopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), loopSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.loopSource = nil
        self.tap = nil
        reset()
    }

    private func reset() {
        buffer.reset()
    }

    /// Forgets the word being typed. `forgetLastWord` also drops the menu's
    /// "Từ vừa gõ": another app is in front, so that word was typed elsewhere.
    func resetBuffer(forgetLastWord: Bool = false) {
        reset()
        if forgetLastWord { buffer.clearLastConverted() }
    }

    /// Vietnamese on/off because the user asked for it (hotkey or menu switch):
    /// remembered for the next launch (`LaunchMode.last`) and for the front app.
    func userToggle() {
        enabled.toggle()
        Settings.shared.lastEnabled = enabled
        AppTracker.shared.rememberCurrentState(enabled)
    }

    /// Turns the tap back on if macOS disabled it without telling the callback
    /// (after sleep/wake or a long main-thread stall). Called by a watchdog timer.
    func ensureTapEnabled() {
        guard let tap, !CGEvent.tapIsEnabled(tap: tap) else { return }
        tapLog.error("event tap found disabled; re-enabling")
        reset()
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func reapplyAppMode() { AppTracker.shared.reapply() }

    func keepLastConversionEnglish() {
        guard let last = buffer.lastConverted else { return }
        Settings.shared.addEnglishWord(last.raw)
        buffer.clearLastConverted()
    }

    /// Everything the buffer needs to know for the front app, read once per key.
    private var typingConfig: TypingBuffer.Config {
        let settings = Settings.shared
        return TypingBuffer.Config(
            toneStyle: settings.toneStyle,
            livePreview: settings.livePreview,
            restoreEnglish: settings.restoreEnglish,
            unikeyDoubleKeys: settings.unikeyDoubleKeys,
            englishWords: englishWords,
            usesPlaceholder: Self.usesPlaceholder(app: AppTracker.shared.frontApp?.bundleID),
            isEnglish: SpellCheck.isEnglish
        )
    }

    private static func usesPlaceholder(app bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return placeholderAppPrefixes.contains { bundleID.hasPrefix($0) }
    }

    private func handle(_ type: CGEventType, _ event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            tapLog.error("event tap disabled by \(type == .tapDisabledByTimeout ? "timeout" : "user input", privacy: .public); re-enabling")
            reset()  // keys typed meanwhile never reached us, so the buffer no longer matches the screen
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass
        }
        // Recording a shortcut, or typing in VietIME's own windows: raw keys.
        if isRecordingHotkey || AppTracker.shared.ownAppIsFront { return pass }
        if event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker { return pass }
        guard type == .keyDown else {
            // A click moves the caret: finish the word where it still is first,
            // so "gôgle" + a click on Send goes out as "google".
            return finishWord(before: event, typingConfig, proxy: proxy)
        }

        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Apps set to "off" never see us, hotkey included.
        if AppTracker.shared.frontAppIsOff { return pass }

        if Settings.shared.hotkey.matches(keyCode: keyCode, flags: flags) {
            // Holding the shortcut repeats it; only the first press toggles.
            guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return nil }
            let config = typingConfig
            if let rewrite = buffer.finish(config) { send(rewrite, config, proxy: proxy) }
            userToggle()
            onStateChange?(.hotkey)
            return nil
        }
        guard enabled else { return pass }
        let config = typingConfig
        if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            // ⌥⌫ and ⌘⌫ delete the word anyway. Any other shortcut (⌘↩ to send,
            // ⌘S, ⌃C…) has to act on the finished word, not the Telex form.
            if keyCode == Self.backspaceKey {
                reset()
                return pass
            }
            return finishWord(before: event, config, proxy: proxy)
        }
        if keyCode == Self.backspaceKey {
            // Known gap: in an address bar showing an inline completion
            // ("ho|me.com") the first Delete only clears the suggestion, yet the
            // buffer drops a character. It can't tell the two apart without
            // asking Accessibility from inside the tap, and treating every
            // browser Delete as unknown would break fixing a typo mid-word in
            // every web text field, which is far more common.
            buffer.backspace(config)
            return pass
        }

        guard let char = typedCharacter(event), char.isASCII, char.isLetter else {
            // Space, Return, digits, punctuation, arrows, Escape…: the word is over.
            // After a space a Delete may bring the word back (see `TypingBuffer.backspace`).
            return finishWord(before: event, config, bySpace: keyCode == Self.spaceKey, proxy: proxy)
        }

        switch buffer.type(char, config) {
        case .pass:
            return pass
        case .swallow:
            return nil
        case .rewrite(let rewrite):
            send(rewrite, config, proxy: proxy)
            return nil
        }
    }

    /// Ends the word before `event` reaches the app. When finishing changes the
    /// text ("gôgle" -> "google"), the edit goes out first and `event` is sent
    /// again behind it; otherwise `event` passes untouched.
    private func finishWord(
        before event: CGEvent, _ config: TypingBuffer.Config, bySpace: Bool = false, proxy: CGEventTapProxy
    ) -> Unmanaged<CGEvent>? {
        guard let rewrite = buffer.finish(config, bySpace: bySpace) else { return Unmanaged.passUnretained(event) }
        send(rewrite, config, proxy: proxy)
        repost(event, proxy: proxy)
        return nil
    }

    // TEMP diagnostics
    func diag(_ type: CGEventType, _ event: CGEvent, result: Unmanaged<CGEvent>?, t0: UInt64) {
        guard type == .keyDown || type == .leftMouseDown else { return }
        let synthetic = event.getIntegerValueField(.eventSourceUserData) == Self.syntheticMarker
        let wait = Double(Int64(t0) - Int64(event.timestamp)) / 1e6
        let dt = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let ch = typedCharacter(event).map { String($0) } ?? "?"
        let pid = event.getIntegerValueField(.eventSourceUnixProcessID)
        let rep = event.getIntegerValueField(.keyboardEventAutorepeat)
        tapLog.notice("""
            DIAG \(type == .keyDown ? "key" : "click", privacy: .public) code=\(code, privacy: .public) ch=[\(ch, privacy: .public)] \
            flags=\(String(event.flags.rawValue, radix: 16), privacy: .public) rep=\(rep, privacy: .public) pid=\(pid, privacy: .public) \
            syn=\(synthetic, privacy: .public) out=\(result == nil ? "swallow" : "pass", privacy: .public) \
            raw=[\(self.buffer.raw, privacy: .public)] shown=[\(self.buffer.shown, privacy: .public)] \
            app=\(AppTracker.shared.frontApp?.bundleID ?? "?", privacy: .public) wait=\(wait, format: .fixed(precision: 2), privacy: .public) dt=\(dt, format: .fixed(precision: 2), privacy: .public)
            """)
    }

    private func typedCharacter(_ event: CGEvent) -> Character? {
        var length = 0
        var buffer = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &buffer)
        guard length == 1 else { return nil }
        return String(utf16CodeUnits: buffer, count: 1).first
    }

    /// Turns what is on screen into the finished word: the buffer builds the
    /// edit, this turns it into key events.
    private func send(_ rewrite: Rewrite, _ config: TypingBuffer.Config, proxy: CGEventTapProxy) {
        // Counts and the app only, never the text typed. Watch with:
        // log stream --level debug --predicate 'subsystem == "dev.local.vietime"'
        tapLog.notice("DIAG rewrite del=\(rewrite.deleteCount, privacy: .public) text=[\(rewrite.text, privacy: .public)] ph=\(rewrite.placeholder, privacy: .public) key=\(Self.freeTextKey(), privacy: .public) aHeld=\(CGEventSource.keyState(.hidSystemState, key: 0), privacy: .public)")
        tapLog.debug("""
            rewrite in \(AppTracker.shared.frontApp?.bundleID ?? "?", privacy: .public): \
            delete \(rewrite.deleteCount, privacy: .public), \
            type \(rewrite.text.count, privacy: .public), \
            placeholder \(rewrite.placeholder, privacy: .public)
            """)
        let textKey = Self.freeTextKey()
        for stroke in config.strokes(for: rewrite) {
            switch stroke {
            case .backspace:
                postKey(Self.backspaceKey, text: nil, proxy: proxy)
            case .text(let text):
                postKey(textKey, text: text, proxy: proxy)
            }
        }
    }

    /// Sends the user's key or click again, behind the events we just posted.
    private func repost(_ event: CGEvent, proxy: CGEventTapProxy) {
        guard let copy = event.copy() else { return }
        copy.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
        copy.tapPostEvent(proxy)
    }

    /// Posts straight into the tap's own position (`tapPostEvent`) instead of
    /// queueing after it, so keys typed quickly can never slip between our
    /// backspaces and the new text.
    private func postKey(_ keyCode: CGKeyCode, text: String?, proxy: CGEventTapProxy) {
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: Self.syntheticMarker)
            // The key-up carries the text too, as it always has: without it the
            // key-up is a plain "a" (key code 0) release.
            if let text {
                let units = Array(text.utf16)
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            event.tapPostEvent(proxy)
        }
    }
}
