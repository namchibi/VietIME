import Foundation
import Testing
import TelexEngine

// MARK: - Rewrite

@Test func rewriteOnlyTouchesTheDifferingTail() {
    #expect(Rewrite.between("abc", "abc") == nil)
    #expect(Rewrite.between("", "") == nil)
    #expect(Rewrite.between("a", "ab") == Rewrite(deleteCount: 0, text: "b"))
    #expect(Rewrite.between("ho", "hô") == Rewrite(deleteCount: 1, text: "ô"))
    #expect(Rewrite.between("tieng", "tiếng") == Rewrite(deleteCount: 3, text: "ếng"))
    #expect(Rewrite.between("tiêng", "tiếng") == Rewrite(deleteCount: 3, text: "ếng"))
}

@Test func placeholderOnlyWhenSomethingIsDeleted() {
    #expect(Rewrite.between("ho", "hô", placeholder: true)?.placeholder == true)
    // Appending never needs it: there is no inline completion to replace.
    #expect(Rewrite.between("a", "ab", placeholder: true)?.placeholder == false)
}

@Test func plainAppsGetTheShortRewrite() {
    let rewrite = Rewrite.between("ho", "hô")!
    #expect(rewrite.strokes() == [.backspace, .text("ô")])
}

@Test func browsersGetThePlaceholderFirst() {
    let rewrite = Rewrite.between("ho", "hô", placeholder: true)!
    #expect(rewrite.strokes() == [
        .text(Rewrite.placeholderCharacter),  // replaces the inline completion
        .backspace,  // removes the placeholder
        .backspace,  // removes the "o"
        .text("ô"),
    ])
}

// MARK: - Key events

@Test func cacsKeepsItsFirstLetter() {
    // Outside browsers there is no placeholder: "cac" -> "các" deletes exactly
    // "ac", so an app can't lose the "c" by dropping an extra event.
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config(livePreview: true)
    for key in "cac" { #expect(buffer.type(key, config) == .pass) }
    let action = buffer.type("s", config)
    #expect(action == .rewrite(Rewrite(deleteCount: 2, text: "ác")))
    if case .rewrite(let rewrite) = action {
        #expect(config.strokes(for: rewrite) == [.backspace, .backspace, .text("á"), .text("c")])
    }
}

@Test func everyCharacterIsItsOwnKey() {
    // Chrome and Electron apps only insert the first character of a
    // multi-character event, so "ếng" in one event would lose "ng".
    #expect(Rewrite(deleteCount: 0, text: "tiếng").strokes() == ["t", "i", "ế", "n", "g"].map { .text(String($0)) })
    #expect(Rewrite(deleteCount: 2, text: "ếng").strokes() == [.backspace, .backspace, .text("ế"), .text("n"), .text("g")])
    let emoji = Rewrite(deleteCount: 0, text: "😀😀").strokes()
    #expect(emoji == [.text("😀"), .text("😀")])
}

// MARK: - Typing

/// Types `keys` through a fresh buffer the way `KeyHandler` does: every edit the
/// buffer returns is applied to `screen`, `.pass` lets the key itself through and
/// `.swallow` drops it; "⌫" is the Delete key. `screen` is what an app would
/// actually show.
private func screenAfterTyping(_ keys: String, _ config: TypingBuffer.Config) -> String {
    var buffer = TypingBuffer()
    return screenAfterTyping(keys, config, buffer: &buffer)
}

private func screenAfterTyping(_ keys: String, _ config: TypingBuffer.Config, buffer: inout TypingBuffer) -> String {
    var screen = ""
    for key in keys {
        if key == "⌫" {
            if !screen.isEmpty { screen.removeLast() }  // the real Delete key does this
            buffer.backspace(config)
        } else if key.isASCII && key.isLetter {
            switch buffer.type(key, config) {
            case .pass:
                screen.append(key)
            case .swallow:
                break
            case .rewrite(let rewrite):
                screen = applying(rewrite, to: screen)
            }
        } else {
            if let rewrite = buffer.finish(config, bySpace: key == " ") {
                screen = applying(rewrite, to: screen)
            }
            screen.append(key)
        }
    }
    return screen
}

/// What the app shows after a rewrite: the placeholder goes in at the caret and
/// is backspaced away again, then the deleted tail, then the new text.
private func applying(_ rewrite: Rewrite, to screen: String) -> String {
    var screen = screen
    if rewrite.placeholder {
        screen += Rewrite.placeholderCharacter
        screen.removeLast()
    }
    screen.removeLast(rewrite.deleteCount)
    screen += rewrite.text
    return screen
}

@Test(arguments: [
    ("tieengs", "tiếng"), ("vieejt", "việt"), ("nguwowif", "người"), ("dduwowcj", "được"),
    ("hoaf", "hoà"), ("thuowr", "thuở"), ("huwong", "hương"), ("nghieeng", "nghiêng"),
])
func typingKeepsTheScreenAndTheBufferInSync(raw: String, expected: String) {
    for livePreview in [false, true] {
        for placeholder in [false, true] {
            let config = TypingBuffer.Config(livePreview: livePreview, usesPlaceholder: placeholder)
            #expect(
                screenAfterTyping(raw + " ", config) == expected + " ",
                "\(raw) with livePreview \(livePreview), placeholder \(placeholder)"
            )
        }
    }
}

@Test func englishWordIsRestoredAtTheEnd() {
    let config = TypingBuffer.Config(isEnglish: { $0 == "push" })
    #expect(screenAfterTyping("pussh ", config) == "push ")
    #expect(screenAfterTyping("pussh ", TypingBuffer.Config(livePreview: true, isEnglish: { $0 == "push" })) == "push ")
}

@Test func finishingRemembersThePairAndResets() {
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    for key in "tieengs" { _ = buffer.type(key, config) }
    #expect(buffer.finish(config) == nil)  // the screen already shows "tiếng"
    #expect(buffer.lastConverted?.raw == "tieengs")
    #expect(buffer.lastConverted?.result == "tiếng")
    #expect(buffer.raw.isEmpty)
    #expect(buffer.shown.isEmpty)
}

@Test func aWordOnlyRetypesItsDifferingTail() {
    // "tiếng" (tieengs) needs four backspaces in total (one for "tie" -> "tiê",
    // three for "tiêng" -> "tiếng") and four characters ("ê", then "ếng").
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    var strokes = 0
    for key in "tieengs " {
        if key.isASCII && key.isLetter {
            if case .rewrite(let rewrite) = buffer.type(key, config) {
                strokes += config.strokes(for: rewrite).count
            }
        } else if let rewrite = buffer.finish(config) {
            strokes += config.strokes(for: rewrite).count
        }
    }
    #expect(strokes == 8)
}

@Test func backspaceKeepsTheBufferInSync() {
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    var screen = ""
    for key in "tieeng" {
        switch buffer.type(key, config) {
        case .pass:
            screen.append(key)
        case .swallow:
            break
        case .rewrite(let rewrite):
            screen = applying(rewrite, to: screen)
        }
    }
    #expect(screen == "tiêng")
    #expect(buffer.shown == screen)

    buffer.backspace(config)
    screen.removeLast()  // the real Delete key already did this
    #expect(buffer.shown == screen)
}

@Test func backspaceThatBreaksTheWordStartsFresh() {
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    _ = buffer.type("a", config)
    _ = buffer.type("a", config)
    #expect(buffer.shown == "â")
    buffer.backspace(config)  // raw "a" shows "a", but the screen lost a character
    #expect(buffer.raw.isEmpty)
    #expect(buffer.shown.isEmpty)
}

@Test func aWordPastTheLimitIsLeftAlone() {
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    for key in "abcdefghijkl" { _ = buffer.type(key, config) }
    #expect(buffer.raw.count == TypingBuffer.maxKeys)
    #expect(buffer.ignoringWord == false)

    // The 13th key: the screen shows "ạbcdeghiklmn"-style Telex output, so the
    // raw keys go back first, the new key with them.
    #expect(buffer.type("m", config) == .rewrite(Rewrite.between(Telex.transform("abcdefghijkl"), "abcdefghijklm")!))
    #expect(buffer.ignoringWord)
    #expect(buffer.raw.isEmpty)

    // Every key passes through until the word ends, so no rewrite can delete a
    // long stretch of text that was never in the buffer.
    #expect(buffer.type("n", config) == .pass)
    #expect(buffer.raw.isEmpty)
    #expect(buffer.finish(config) == nil)
    #expect(buffer.ignoringWord == false)
}

@Test(arguments: ["international", "understanding", "configuration", "implementation", "abcdefghijklmn"])
func longEnglishWordsEndUpAsTyped(word: String) {
    for livePreview in [false, true] {
        for placeholder in [false, true] {
            let config = TypingBuffer.Config(livePreview: livePreview, usesPlaceholder: placeholder)
            #expect(
                screenAfterTyping(word + " ", config) == word + " ",
                "\(word) with livePreview \(livePreview), placeholder \(placeholder)"
            )
        }
    }
}

@Test func aWordThatPassesTheLimitAsTypedNeedsNoRewrite() {
    // "bcdfghklmnpq" has no vowel, so Telex leaves it alone and the screen
    // already shows the raw keys: the 13th key just goes through.
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    for key in "bcdfghklmnpq" { _ = buffer.type(key, config) }
    #expect(buffer.type("r", config) == .pass)
    #expect(buffer.ignoringWord)
}

@Test func deletingALongWordLetsTheNextWordConvert() {
    // 15 keys, all deleted again, then a Vietnamese word with no space before it.
    let long = "abcdefghijklmno"
    let deletes = String(repeating: "⌫", count: long.count)
    let config = TypingBuffer.Config()
    #expect(screenAfterTyping(long + deletes + "vieejt ", config) == "việt ")
}

@Test func deletingPartOfALongWordKeepsIgnoringIt() {
    // Half of the long word is still on screen, so it is still not Vietnamese.
    let config = TypingBuffer.Config()
    #expect(screenAfterTyping("abcdefghijklmno⌫⌫⌫aa ", config) == "abcdefghijklaa ")
}

@Test func aLongWordClearsTheLastConvertedWord() {
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    _ = screenAfterTyping("as ", config, buffer: &buffer)
    #expect(buffer.lastConverted?.result == "á")
    _ = screenAfterTyping("international ", config, buffer: &buffer)
    #expect(buffer.lastConverted == nil)
}

// MARK: - Live preview agrees with the finished word

/// Typing `raw` shows the same thing just before and just after the space: what
/// the preview showed is what the word ends up as.
private func previewMatchesFinish(_ raw: String, _ config: TypingBuffer.Config) -> (preview: String, final: String) {
    var buffer = TypingBuffer()
    let preview = screenAfterTyping(raw, config, buffer: &buffer)
    var screen = preview
    if let rewrite = buffer.finish(config) { screen = applying(rewrite, to: screen) }
    return (preview, screen)
}

@Test func previewKeepsTheConvertedFormWhenEnglishRestoreIsOff() {
    let config = TypingBuffer.Config(livePreview: true, restoreEnglish: false)
    let result = previewMatchesFinish("class", config)
    #expect(result.preview == "clas")
    #expect(result.final == "clas")
}

@Test func previewKeepsDoubledKeysWhenUnikeyDoublesAreOff() {
    let config = TypingBuffer.Config(livePreview: true, unikeyDoubleKeys: false)
    let result = previewMatchesFinish("wwork", config)
    #expect(result.preview == "wwork")
    #expect(result.final == "wwork")
    // With the option on (the default) both collapse to "work".
    let collapsed = previewMatchesFinish("wwork", TypingBuffer.Config(livePreview: true))
    #expect(collapsed.preview == "work")
    #expect(collapsed.final == "work")
}

@Test func aModifierThatChangesNothingIsSwallowed() {
    // "nguwow": the second "w" leaves "nguơ" as it is, so it must not reach the
    // app (it would show up as a stray "w") and there is nothing to rewrite.
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    for key in "nguwow" {
        _ = buffer.type(key, config)
    }
    #expect(buffer.shown == "nguơ")
    #expect(buffer.type("i", config) == .rewrite(Rewrite(deleteCount: 2, text: "ươi")))
    #expect(buffer.shown == "ngươi")
}

@Test func backspaceWhilePastTheLimitKeepsIgnoring() {
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    for key in "abcdefghijklm" { _ = buffer.type(key, config) }
    #expect(buffer.ignoringWord)
    buffer.backspace(config)
    #expect(buffer.raw.isEmpty)
    #expect(buffer.ignoringWord)  // 12 of its 13 characters are still on screen
}

// MARK: - Cancelled keys

@Test func cancelledKeysPointAtTheKeyThatUndidAMark() {
    #expect(Telex.cancelledKeys(in: "pussh") == ([3], []))
    #expect(Telex.cancelledKeys(in: "success") == ([6], []))
    #expect(Telex.cancelledKeys(in: "wwork") == ([1], [1]))
    #expect(Telex.cancelledKeys(in: "tienee") == ([5], [5]))
    #expect(Telex.cancelledKeys(in: "tieengs") == ([], []))
}

// MARK: - Delete inside a word

@Test(arguments: [
    // Delete a letter, then finish the word with marks that still have to apply.
    ("vieets⌫tj ", "việt "), ("tieengs⌫⌫ng ", "tiếng "), ("nguwowif⌫i ", "người "),
    ("dduowcj⌫⌫ocj ", "được "), ("khoong⌫⌫ng ", "không "), ("tes⌫t ", "tt "),
    ("Vieets⌫tj ", "Việt "), ("hoaf⌫af ", "hoà "),
    // Delete back past the marked letter.
    ("vieets⌫⌫⌫ieetj ", "việt "), ("dduowcj⌫⌫⌫uowcj ", "được "),
    // A space, then Delete: the word before it is back and takes more marks.
    ("ddi ⌫f ", "đì "), ("cacs ⌫h ", "cách "), ("banj ⌫ ", "bạn "), ("tooi ⌫ ", "tôi "),
    ("vieet ⌫j ", "việt "),
    // Anything between the space and the Delete starts a new word.
    ("ddi a⌫f ", "đi f "), ("ddi  ⌫f ", "đi f "),
    // English words stay as typed when edited.
    ("push⌫h ", "push "), ("google ⌫s ", "googles "),
])
func deleteKeepsEditingTheWord(keys: String, expected: String) {
    for livePreview in [false, true] {
        for placeholder in [false, true] {
            let config = TypingBuffer.Config(livePreview: livePreview, usesPlaceholder: placeholder)
            #expect(
                screenAfterTyping(keys, config) == expected,
                "\(keys) with livePreview \(livePreview), placeholder \(placeholder)"
            )
        }
    }
}

@Test func deleteAfterAnArrowOrClickDoesNotResume() {
    var buffer = TypingBuffer()
    let config = TypingBuffer.Config()
    for key in "ddi" { _ = buffer.type(key, config) }
    _ = buffer.finish(config)  // not a space: an arrow, a click, Return…
    buffer.backspace(config)
    #expect(buffer.raw.isEmpty)
}
