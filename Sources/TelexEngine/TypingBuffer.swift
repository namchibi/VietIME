import Foundation

/// The edit that brings the screen in line with the buffer: backspaces over the
/// tail that differs, then the text to type in its place.
public struct Rewrite: Equatable, Sendable {
    /// Narrow no-break space: invisible, replaces an inline completion, then is
    /// deleted again. Never left on screen.
    public static let placeholderCharacter = "\u{202F}"

    /// Backspaces over the end of the old text, not counting the placeholder.
    public var deleteCount: Int
    /// What to type after them; empty when only deletion is needed.
    public var text: String
    /// Browsers and Spotlight inline-complete what is typed ("ho" -> "ho@gmail.com"),
    /// so a plain backspace would only clear the suggestion and leave the old text
    /// behind. There the edit starts with `placeholderCharacter`, which the extra
    /// backspace then removes.
    public var placeholder: Bool

    public init(deleteCount: Int, text: String, placeholder: Bool = false) {
        self.deleteCount = deleteCount
        self.text = text
        self.placeholder = placeholder
    }

    /// The smallest edit from `old` to `new`, or nil when they are equal.
    /// `placeholder` is only used when something has to be deleted first.
    public static func between(_ old: String, _ new: String, placeholder: Bool = false) -> Rewrite? {
        guard old != new else { return nil }
        let common = old.commonPrefix(with: new).count
        let deleteCount = old.count - common
        return Rewrite(
            deleteCount: deleteCount,
            text: String(new.dropFirst(common)),
            placeholder: placeholder && deleteCount > 0
        )
    }

    /// Synthetic keystrokes for this edit, in order: the placeholder (when the app
    /// needs one), one Delete per removed character, then one key per new character.
    ///
    /// Never several characters in one event: Chrome, Electron apps (Zalo,
    /// Telegram, Slack, VS Code…) and others only insert the first character of
    /// such an event, so "tiêng" + "s" would end up as "tiế" instead of "tiếng".
    public func strokes() -> [KeyStroke] {
        var strokes: [KeyStroke] = []
        if placeholder {
            strokes.append(.text(Self.placeholderCharacter))
        }
        let deletes = deleteCount + (placeholder ? 1 : 0)
        strokes.append(contentsOf: Array(repeating: .backspace, count: deletes))
        strokes.append(contentsOf: text.map { KeyStroke.text(String($0)) })
        return strokes
    }
}

/// One synthetic key press: the Delete key, or one character.
public enum KeyStroke: Equatable, Sendable {
    case backspace
    case text(String)
}

/// The keys typed for one word and what that word looks like on screen.
///
/// Pure state, no AppKit: it computes the edit for each key and leaves turning
/// that edit into key events to the caller. Keeping it here is what makes the
/// buffer, backspace and rewrite logic (the part most likely to drift from the
/// screen) testable without an event tap.
public struct TypingBuffer {
    /// Longer than any Vietnamese syllable plus its modifier and tone keys
    /// ("nghiêng" is 7 letters, about 10-11 keys). The next key puts the raw keys
    /// back on screen (the word is English or a typo, never Vietnamese), and the
    /// rest of the word is left alone: a buffer that long is the likeliest to have
    /// drifted from the screen, and one wrong rewrite could delete a long stretch.
    public static let maxKeys = 12

    /// Everything the buffer needs to know about settings and the front app.
    public struct Config {
        public var toneStyle: ToneStyle
        public var livePreview: Bool
        public var restoreEnglish: Bool
        public var unikeyDoubleKeys: Bool
        public var englishWords: Set<String>
        /// True in browsers and Spotlight, whose text fields inline-complete.
        /// Elsewhere the placeholder is risky: an app that drops it loses one
        /// more character than the rewrite meant to delete.
        public var usesPlaceholder: Bool
        /// English dictionary verdict; a closure so the buffer stays pure.
        public var isEnglish: (String) -> Bool
        public init(
            toneStyle: ToneStyle = .modern,
            livePreview: Bool = false,
            restoreEnglish: Bool = true,
            unikeyDoubleKeys: Bool = true,
            englishWords: Set<String> = Telex.defaultEnglishWords,
            usesPlaceholder: Bool = false,
            isEnglish: @escaping (String) -> Bool = { _ in false }
        ) {
            self.toneStyle = toneStyle
            self.livePreview = livePreview
            self.restoreEnglish = restoreEnglish
            self.unikeyDoubleKeys = unikeyDoubleKeys
            self.englishWords = englishWords
            self.usesPlaceholder = usesPlaceholder
            self.isEnglish = isEnglish
        }

        /// The key events for `rewrite`.
        public func strokes(for rewrite: Rewrite) -> [KeyStroke] {
            rewrite.strokes()
        }
    }

    /// The raw keys typed for the current word.
    public private(set) var raw = ""
    /// What the current word looks like on screen.
    public private(set) var shown = ""
    /// Set once the word grows past `maxKeys`: every key then goes straight
    /// through until the word ends, so a buffer that no longer matches the screen
    /// can never rewrite (and delete) a long stretch.
    public private(set) var ignoringWord = false
    /// While `ignoringWord`: how many characters of the long word are on screen,
    /// so deleting all of them lets the next key start a new word.
    private var ignoredCount = 0
    /// The last finished word whose text changed, for the menu's "Từ vừa gõ".
    /// The menu asks the dictionary about it when it opens.
    public private(set) var lastConverted: (raw: String, result: String)?
    /// Text right before the caret that belongs to a word the buffer doesn't
    /// hold: the word a space just ended plus that space, or a word Delete left
    /// in a state no keys spell ("đượ"). Only further Deletes use it, each one
    /// trying to take the shortened text over; any other key clears it.
    private var unheld: String?

    public init() {}

    /// What to do with a letter key.
    public enum Action: Equatable {
        /// The key can go to the app untouched: it already shows what the buffer
        /// expects ("tieng" + "s" -> the "s" of "tiếng").
        case pass
        /// The key does something inside the word but nothing on screen (a "w"
        /// that adds no visible letter), so it must not reach the app, but
        /// there is nothing to send either.
        case swallow
        /// Send this edit instead of the key.
        case rewrite(Rewrite)
    }

    /// A letter key: returns what to do with it.
    public mutating func type(_ key: Character, _ config: Config) -> Action {
        unheld = nil
        if ignoringWord {
            ignoredCount += 1
            return .pass
        }
        if raw.count >= Self.maxKeys {
            // Put the keys back as typed ("ỉntenationa" -> "internationa" + "l")
            // while the buffer still matches the screen, then let the rest through.
            let typed = raw + String(key)
            let restore = shown == raw ? nil : Rewrite.between(shown, typed, placeholder: config.usesPlaceholder)
            reset()
            ignoringWord = true
            ignoredCount = typed.count
            return restore.map(Action.rewrite) ?? .pass
        }
        raw.append(key)
        let next = display(config)
        if next == shown + String(key) {
            shown = next
            return .pass
        }
        let rewrite = Rewrite.between(shown, next, placeholder: config.usesPlaceholder)
        shown = next
        guard let rewrite else { return .swallow }
        return .rewrite(rewrite)
    }

    /// A key that ends the word (space, punctuation, arrow, click…): returns the
    /// edit that finishes the word and clears it; the caller sends the key itself
    /// after that edit. `bySpace`: the key is a space, so a Delete right after it
    /// brings the word back for editing (see `backspace`).
    @discardableResult
    public mutating func finish(_ config: Config, bySpace: Bool = false) -> Rewrite? {
        if ignoringWord {
            // A word too long to be Vietnamese is now the last word typed, and it
            // was left as typed: nothing for the menu to offer.
            lastConverted = nil
            reset()
            return nil
        }
        guard !raw.isEmpty else {
            reset()
            return nil
        }
        let final = Telex.finalize(
            raw,
            englishWords: config.englishWords,
            isEnglish: config.isEnglish,
            toneStyle: config.toneStyle,
            restoreEnglish: config.restoreEnglish,
            unikeyDoubleKeys: config.unikeyDoubleKeys
        )
        lastConverted = final != raw ? (raw, final) : nil
        let rewrite = final == shown ? nil : Rewrite.between(shown, final, placeholder: config.usesPlaceholder)
        reset()
        if bySpace { unheld = final + " " }
        return rewrite
    }

    /// The user pressed Delete; the screen already removed a character. The buffer
    /// follows the shortened word, so marks typed next still apply to it.
    public mutating func backspace(_ config: Config) {
        if ignoringWord {
            // The long word is deleted one character at a time; once it is gone,
            // the next key starts a new word instead of being ignored too.
            ignoredCount -= 1
            if ignoredCount <= 0 { reset() }
            return
        }
        guard !raw.isEmpty else {
            // Delete right after the space that ended a word brings that word
            // back before the caret ("ddi", space, Delete, "f" -> "đì").
            if let text = unheld { adopt(String(text.dropLast()), config) }
            return
        }
        let expected = String(shown.dropLast())
        raw.removeLast()
        if display(config) == expected {
            shown = expected
            return
        }
        // The shorter keys spell something else: "vieets" shows "viết", Delete
        // leaves "viế", but "vieet" is "viêt". Take over what the screen shows
        // instead of dropping the word, so "tj" typed next still makes "việt".
        adopt(expected, config)
    }

    /// Makes `text`, which is on screen right before the caret, the word being
    /// typed, when Telex keys spell it exactly. Otherwise the buffer stays empty,
    /// so the next letter starts a new word, and `text` is kept for the next Delete.
    private mutating func adopt(_ text: String, _ config: Config) {
        reset()
        guard !text.isEmpty else { return }
        if let keys = Telex.keys(for: text), keys.count < Self.maxKeys {
            raw = keys
            if display(config) == text {
                shown = text
                return
            }
            raw = ""
        }
        unheld = text
    }

    /// Forgets the word being typed (app switch, click, hotkey).
    public mutating func reset() {
        raw = ""
        shown = ""
        ignoringWord = false
        ignoredCount = 0
        unheld = nil
    }

    /// The menu turned the last word into an always-English word: drop the suggestion.
    public mutating func clearLastConverted() { lastConverted = nil }

    /// What the word looks like while typing: live preview falls back to the raw
    /// keys as soon as the word can no longer become Vietnamese.
    ///
    /// The preview has to agree with `finish`: with English restore off the
    /// converted form is what stays, so that is what is shown, and doubled keys
    /// only collapse early when `finish` would collapse them too.
    private func display(_ config: Config) -> String {
        guard config.livePreview, config.restoreEnglish else {
            return Telex.transform(raw, toneStyle: config.toneStyle)
        }
        return Telex.liveText(raw, toneStyle: config.toneStyle, unikeyDoubleKeys: config.unikeyDoubleKeys)
    }
}
