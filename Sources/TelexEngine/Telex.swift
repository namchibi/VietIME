/// Why `Telex.finalize` returned what it did.
public enum FinalizeReason: Equatable, Sendable {
    case unchanged  // text == raw, nothing to do
    case vietnamese  // valid Vietnamese syllable, converted
    case userEnglishWord  // raw is in englishWords, kept
    case notVietnamese  // not a valid syllable, raw kept
    case collapsedByDictionary  // doubled modifier dropped because the result is a dictionary word (pussh -> push)
    case collapsedByImpossibleDouble  // dropped because English never doubles that key (wwork, boook)
    case keptByDictionary  // raw itself is a dictionary word with a legit double (class, error)
    case restoreDisabled  // restoreEnglish == false, converted text returned as-is
}

/// Pure Telex engine: turns the raw keystrokes of one word into Vietnamese text.
///
/// The whole word is recomputed from its raw keys on every keystroke, so the
/// engine is stateless and order-free ("tieengs", "tiengse" and "tieesng" all
/// work).
public enum Telex {
    // Tone order: none, sắc (s), huyền (f), hỏi (r), ngã (x), nặng (j).
    private static let toneTable: [Character: [Character]] = [
        "a": ["a", "á", "à", "ả", "ã", "ạ"],
        "ă": ["ă", "ắ", "ằ", "ẳ", "ẵ", "ặ"],
        "â": ["â", "ấ", "ầ", "ẩ", "ẫ", "ậ"],
        "e": ["e", "é", "è", "ẻ", "ẽ", "ẹ"],
        "ê": ["ê", "ế", "ề", "ể", "ễ", "ệ"],
        "i": ["i", "í", "ì", "ỉ", "ĩ", "ị"],
        "o": ["o", "ó", "ò", "ỏ", "õ", "ọ"],
        "ô": ["ô", "ố", "ồ", "ổ", "ỗ", "ộ"],
        "ơ": ["ơ", "ớ", "ờ", "ở", "ỡ", "ợ"],
        "u": ["u", "ú", "ù", "ủ", "ũ", "ụ"],
        "ư": ["ư", "ứ", "ừ", "ử", "ữ", "ự"],
        "y": ["y", "ý", "ỳ", "ỷ", "ỹ", "ỵ"],
    ]
    private static let toneKeys: [Character: Int] = ["s": 1, "f": 2, "r": 3, "x": 4, "j": 5]
    private static let circumflex: [Character: Character] = ["a": "â", "e": "ê", "o": "ô"]
    private static let hornBreve: [Character: Character] = ["a": "ă", "o": "ơ", "u": "ư"]
    private static let marked: Set<Character> = ["ă", "â", "ê", "ô", "ơ", "ư"]

    /// English words Telex would otherwise change: ones that also spell a valid
    /// Vietnamese syllable ("of" -> "ò") and are far more likely to be meant as
    /// English, and "www", whose second "w" looks like it cancels the first.
    public static let defaultEnglishWords: Set<String> = ["of", "if", "or", "is", "us", "www"]

    private struct Letter {
        var char: Character  // lowercase, may carry a diacritic but never a tone
        var upper: Bool
        var fromW = false  // a standalone "ư" typed as "w"
    }

    private struct Word {
        var letters: [Letter] = []
        var tone = 0
        var undone: Set<Int> = []  // offsets of raw keys that cancelled the same key before them
        var plainUndone: Set<Int> = []  // those that can't be an English double letter ("ww", "ooo")
        var plainlyUndone: Bool { !plainUndone.isEmpty }

        mutating func undo(_ offset: Int, plain: Bool) {
            undone.insert(offset)
            if plain { plainUndone.insert(offset) }
        }
    }

    /// Converts the raw keys typed so far for a single word into its Vietnamese form.
    public static func transform(_ raw: String, toneStyle: ToneStyle = .modern) -> String {
        render(compose(raw), toneStyle: toneStyle)
    }

    /// Text to show while the word is still being typed. It is `transform(raw)`
    /// as long as `raw` can still grow into a valid Vietnamese syllable (more
    /// letters, a tone key or a modifier key may still arrive); once it can't,
    /// the raw keys are shown, so "push" never flashes as "púh". Doubled
    /// modifiers that English never spells ("wwork") are collapsed as soon as
    /// they stop being Vietnamese, matching what `finalize` will do with the
    /// same `unikeyDoubleKeys`.
    public static func liveText(_ raw: String, toneStyle: ToneStyle = .modern, unikeyDoubleKeys: Bool = true) -> String {
        let word = compose(raw)
        if Spelling.isViablePrefix(word.letters.map(\.char)) { return render(word, toneStyle: toneStyle) }
        if unikeyDoubleKeys, word.plainlyUndone { return collapse(raw, word) }
        return raw
    }

    /// Offsets in `raw` of the keys that only cancelled the same key before them
    /// ("pussh" -> [3]), and among them the ones English never spells
    /// ("wwork" -> [1]); both sorted.
    public static func cancelledKeys(in raw: String) -> (all: [Int], impossible: [Int]) {
        let word = compose(raw)
        return (word.undone.sorted(), word.plainUndone.sorted())
    }

    /// The text a finished word should end up as: its Vietnamese form when that
    /// is a valid syllable, otherwise the raw keys, so "class", "google" or
    /// "window" come out exactly as typed.
    ///
    /// A modifier pressed twice is ambiguous in English: "class" means the
    /// double "s", but "pussh" (Unikey habit) means "push" with the tone
    /// cancelled. `isEnglish` (a dictionary) decides; without a verdict the raw
    /// keys win, unless the word has a cancel English never spells ("wwork").
    public static func finalize(
        _ raw: String,
        englishWords: Set<String> = defaultEnglishWords,
        isEnglish: (String) -> Bool = { _ in false },
        toneStyle: ToneStyle = .modern,
        restoreEnglish: Bool = true,
        unikeyDoubleKeys: Bool = true
    ) -> String {
        finalizeWithReason(
            raw, englishWords: englishWords, isEnglish: isEnglish, toneStyle: toneStyle,
            restoreEnglish: restoreEnglish, unikeyDoubleKeys: unikeyDoubleKeys
        ).text
    }

    /// `finalize`, plus why the word ended up as it did.
    public static func finalizeWithReason(
        _ raw: String,
        englishWords: Set<String> = defaultEnglishWords,
        isEnglish: (String) -> Bool = { _ in false },
        toneStyle: ToneStyle = .modern,
        restoreEnglish: Bool = true,
        unikeyDoubleKeys: Bool = true
    ) -> (text: String, reason: FinalizeReason) {
        let word = compose(raw)
        let text = render(word, toneStyle: toneStyle)
        if text == raw { return (raw, .unchanged) }
        if !restoreEnglish { return (text, .restoreDisabled) }
        if englishWords.contains(raw.lowercased()) { return (raw, .userEnglishWord) }
        let chars = word.letters.map(\.char)
        // Words without a vowel ("đ", "w" typed as "ww") are deliberate, keep them.
        guard chars.contains(where: isVowel) else { return (text, .vietnamese) }
        if Spelling.isValid(chars, tone: word.tone) { return (text, .vietnamese) }

        guard unikeyDoubleKeys, !word.undone.isEmpty else { return (raw, .notVietnamese) }
        func known(_ w: String) -> Bool { englishWords.contains(w.lowercased()) || isEnglish(w) }
        if known(raw) { return (raw, .keptByDictionary) }
        let collapsed = collapse(raw, word)
        if known(collapsed) { return (collapsed, .collapsedByDictionary) }
        if word.plainlyUndone { return (collapsed, .collapsedByImpossibleDouble) }
        return (raw, .notVietnamese)
    }

    /// Telex keys that spell `text` ("Việt" -> "Vieetj"): each marked letter as
    /// its key pair, the tone key last. Nil when `text` holds something other
    /// than letters or more than one tone mark. The caller still has to check
    /// that the keys give `text` back: not every string is a syllable.
    public static func keys(for text: String) -> String? {
        var keys = ""
        var tone = 0
        for char in text {
            let upper = char.isUppercase
            var lower = Character(char.lowercased())
            if let (base, t) = untoned[lower] {
                if t != 0 {
                    guard tone == 0 else { return nil }
                    tone = t
                }
                lower = base
            }
            let spelled: String
            switch lower {
            case "â": spelled = "aa"
            case "ê": spelled = "ee"
            case "ô": spelled = "oo"
            case "ă": spelled = "aw"
            case "ơ": spelled = "ow"
            case "ư": spelled = "uw"
            case "đ": spelled = "dd"
            default:
                guard lower.isASCII, lower.isLetter else { return nil }
                spelled = String(lower)
            }
            // Only the first key carries the case: "Đ" is "Dd", like Shift+D, D.
            keys += upper ? spelled.prefix(1).uppercased() + spelled.dropFirst() : spelled
        }
        if tone != 0 {
            keys.append(toneKeys.first { $0.value == tone }!.key)
        }
        return keys
    }

    /// Toned vowel -> (vowel without tone, tone index).
    private static let untoned: [Character: (Character, Int)] = {
        var map: [Character: (Character, Int)] = [:]
        for (base, forms) in toneTable {
            for (tone, form) in forms.enumerated() { map[form] = (base, tone) }
        }
        return map
    }()

    /// `raw` without the keys that only cancelled an earlier identical key.
    private static func collapse(_ raw: String, _ word: Word) -> String {
        String(raw.enumerated().filter { !word.undone.contains($0.offset) }.map(\.element))
    }

    private static func compose(_ raw: String) -> Word {
        var word = Word()
        // The key just consumed as a modifier; pressing it again right away
        // undoes it ("aaa" -> "aa", "ass" -> "as", "ww" -> "w").
        var lastModifier: Character?

        for (offset, key) in raw.enumerated() {
            let upper = key.isUppercase
            let k = Character(key.lowercased())
            let repeated = lastModifier == k
            lastModifier = nil
            let literal = Letter(char: k, upper: upper)

            if let t = toneKeys[k], vowelRange(word.letters) != nil {
                if word.tone != t {
                    word.tone = t
                    lastModifier = k
                } else {
                    if repeated {
                        word.tone = 0
                        word.undo(offset, plain: k == "j")
                    }
                    word.letters.append(literal)
                }
                continue
            }
            if k == "z", word.tone != 0 {
                word.tone = 0
                continue
            }
            if let hat = circumflex[k], let range = vowelRange(word.letters) {
                if repeated, let i = range.last(where: { word.letters[$0].char == hat }) {
                    word.letters[i].char = k
                    word.letters.append(literal)
                    word.undo(offset, plain: true)
                    continue
                }
                // Free order ("tiengse"), but only into a real vowel cluster, so the
                // second "o" of "ngoeo" stays plain instead of making "ngôe".
                if let i = range.last(where: { word.letters[$0].char == k }),
                   Spelling.isNucleusPrefix(String(range.map { $0 == i ? hat : word.letters[$0].char })) {
                    word.letters[i].char = hat
                    lastModifier = k
                    continue
                }
            }
            // A "d" anywhere after the initial "d" makes it "đ" ("ddi", "did" -> "đi",
            // "duowcjd" -> "được"); away from the start a vowel must come first, so
            // "dnd" stays as typed.
            if k == "d", word.letters.count == 1 || vowelRange(word.letters) != nil {
                if word.letters[0].char == "d" {
                    word.letters[0].char = "đ"
                    lastModifier = k
                    continue
                }
                if repeated, word.letters[0].char == "đ" {
                    // "ddd" is never English, "didd" may be ("daddy").
                    let atStart = word.letters.count == 1
                    word.letters[0].char = "d"
                    word.letters.append(literal)
                    word.undo(offset, plain: atStart)
                    continue
                }
            }
            if k == "w" {
                if repeated, undoW(&word.letters) {
                    word.letters.append(literal)
                    word.undo(offset, plain: true)
                    continue
                }
                if applyW(&word.letters) {
                    lastModifier = k
                    continue
                }
                if vowelRange(word.letters) == nil {  // "w" alone -> "ư"
                    word.letters.append(Letter(char: "ư", upper: upper, fromW: true))
                    lastModifier = k
                    continue
                }
            }
            word.letters.append(literal)
        }

        // "ưo" only exists as "ươ", so "w" typed once is enough ("huwong" -> "hương").
        // Not for a standalone "w", so "two" stays English.
        if let range = vowelRange(word.letters) {
            for j in range.dropLast() where word.letters[j].char == "ư" && !word.letters[j].fromW
                && word.letters[j + 1].char == "o" {
                word.letters[j + 1].char = "ơ"
            }
        }
        // An open "ươ" is spelled "uơ" ("thuở", "huơ"); "ươ" needs a following letter.
        if let range = vowelRange(word.letters), range.count >= 2, range.last == word.letters.count - 1,
           word.letters[range[range.count - 2]].char == "ư", word.letters[range.last!].char == "ơ" {
            word.letters[range[range.count - 2]].char = "u"
        }
        return word
    }

    private static func render(_ word: Word, toneStyle: ToneStyle) -> String {
        var letters = word.letters
        if word.tone != 0, let i = tonePosition(letters, style: toneStyle), let forms = toneTable[letters[i].char] {
            letters[i].char = forms[word.tone]
        }
        return String(letters.map { $0.upper ? Character($0.char.uppercased()) : $0.char })
    }

    static func isVowel(_ c: Character) -> Bool { toneTable[c] != nil }

    /// Indices of the word's vowel nucleus, treating the "u" of "qu" and the
    /// "i" of "gi" (when followed by another vowel) as consonants.
    private static func vowelRange(_ word: [Letter]) -> [Int]? {
        guard let start = word.firstIndex(where: { isVowel($0.char) }) else { return nil }
        var end = start
        while end + 1 < word.count, isVowel(word[end + 1].char) { end += 1 }
        var range = Array(start...end)
        if range.count > 1, start > 0 {
            let prev = word[start - 1].char
            let first = word[start].char
            if (prev == "q" && first == "u") || (prev == "g" && first == "i" && start == 1) {
                range.removeFirst()
            }
        }
        return range
    }

    private static func applyW(_ word: inout [Letter]) -> Bool {
        guard let range = vowelRange(word) else { return false }
        let chars = range.map { word[$0].char }
        // "uo" -> "ươ"
        if let j = chars.indices.dropLast().first(where: { chars[$0] == "u" && chars[$0 + 1] == "o" }) {
            word[range[j]].char = "ư"
            word[range[j + 1]].char = "ơ"
            return true
        }
        // "a" first, then "o", then "u", but prefer one that makes a real vowel
        // cluster: "ua" -> "ưa" (sửa), not "uă"; "oa" -> "oă" (hoặc).
        let candidates = (["a", "o", "u"] as [Character]).compactMap { target in
            range.first(where: { word[$0].char == target })
        }
        guard let first = candidates.first else { return false }
        let i = candidates.first(where: { i in
            Spelling.isNucleusPrefix(String(range.map { $0 == i ? hornBreve[word[$0].char]! : word[$0].char }))
        }) ?? first
        word[i].char = hornBreve[word[i].char]!
        return true
    }

    private static func undoW(_ word: inout [Letter]) -> Bool {
        let reverse: [Character: Character] = ["ă": "a", "ơ": "o", "ư": "u"]
        var changed = false
        // A standalone "ư" made from "w" goes back to nothing, so "ww" -> "w".
        word.removeAll { letter in
            if letter.fromW { changed = true }
            return letter.fromW
        }
        for i in word.indices {
            if let plain = reverse[word[i].char] {
                word[i].char = plain
                changed = true
            }
        }
        return changed
    }

    /// Where the tone mark goes: "hoà", "thuý" in the modern style, "hòa",
    /// "thúy" in the classic one (only open oa/oe/uy differ).
    private static func tonePosition(_ word: [Letter], style: ToneStyle) -> Int? {
        guard let range = vowelRange(word) else { return nil }
        if let i = range.last(where: { marked.contains(word[$0].char) }) { return i }
        if range.count == 1 { return range[0] }
        let hasFinal = range.last! + 1 < word.count
        if hasFinal { return range.last! }
        if range.count == 3 { return range[1] }
        let pair = String(range.map { word[$0].char })
        return style == .modern && ["oa", "oe", "uy"].contains(pair) ? range[1] : range[0]
    }
}
