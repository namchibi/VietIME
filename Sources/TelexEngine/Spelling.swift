/// Checks whether a word is a well-formed Vietnamese syllable:
/// initial consonant + vowel nucleus + final consonant, plus the tone rule.
enum Spelling {
    // Longest first, so "ngh" wins over "ng" and "n".
    private static let initials = [
        "ngh", "ng", "gh", "gi", "kh", "nh", "ph", "th", "tr", "ch", "qu",
        "b", "c", "d", "đ", "g", "h", "k", "l", "m", "n", "p", "r", "s", "t", "v", "x",
    ]

    /// Vowel nucleus -> the final consonants it may take ("" = open syllable).
    private static let rhymes: [String: Set<String>] = [
        "a": ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"],
        "ă": ["c", "m", "n", "ng", "p", "t"],
        "â": ["c", "m", "n", "ng", "p", "t"],
        "e": ["", "c", "m", "n", "ng", "p", "t"],
        "ê": ["", "ch", "m", "n", "nh", "p", "t"],
        "i": ["", "ch", "m", "n", "nh", "p", "t"],
        "o": ["", "c", "m", "n", "ng", "p", "t"],
        "ô": ["", "c", "m", "n", "ng", "p", "t"],
        "ơ": ["", "m", "n", "p", "t"],
        "u": ["", "c", "m", "n", "ng", "p", "t"],
        "ư": ["", "c", "m", "n", "ng", "t"],
        "y": [""],
        "ai": [""], "ao": [""], "au": [""], "ay": [""], "âu": [""], "ây": [""],
        "eo": [""], "êu": [""], "ia": [""], "iu": [""], "oi": [""], "ôi": [""], "ơi": [""],
        "ua": [""], "ui": [""], "uơ": [""], "ưa": [""], "ưi": [""], "ưu": [""],
        "iê": ["c", "m", "n", "ng", "p", "t"],
        "yê": ["m", "n", "ng", "t"],
        "oa": ["", "c", "ch", "m", "n", "ng", "nh", "p", "t"],
        "oă": ["c", "m", "n", "ng", "t"],
        "oe": ["", "n", "t"],
        "oo": ["c", "ng"],
        "uâ": ["n", "ng", "t"],
        "uê": ["", "ch", "n", "nh"],
        "uô": ["c", "m", "n", "ng", "t"],
        "uy": ["", "ch", "n", "nh", "t"],
        "ươ": ["c", "m", "n", "ng", "p", "t"],
        "iêu": [""], "yêu": [""], "oai": [""], "oay": [""], "oeo": [""], "uây": [""],
        "uôi": [""], "ươi": [""], "ươu": [""], "uya": [""], "uyê": ["n", "t"], "uyu": [""],
    ]

    private static let frontVowels: Set<Character> = ["e", "ê", "i", "y"]

    private static let nucleusPrefixes: Set<String> = Set(rhymes.keys.flatMap { nucleus in
        (1...nucleus.count).map { String(nucleus.prefix($0)) }
    })

    /// Whether `vowels` is a vowel nucleus, or the start of one ("uâ" of "uây").
    static func isNucleusPrefix(_ vowels: String) -> Bool { nucleusPrefixes.contains(vowels) }

    /// `letters` are lowercase and carry diacritics but no tone mark.
    static func isValid(_ letters: [Character], tone: Int) -> Bool {
        let word = String(letters)
        var initial = ""
        for candidate in initials where word.hasPrefix(candidate) {
            // "gi"/"qu" only act as initials before another vowel ("gì" is g + i).
            if candidate == "gi" || candidate == "qu" {
                guard let next = word.dropFirst(2).first, Telex.isVowel(next) else { continue }
            }
            initial = candidate
            break
        }

        var rhyme = String(word.dropFirst(initial.count))
        guard let first = rhyme.first, Telex.isVowel(first) else { return false }
        switch initial {
        case "c" where frontVowels.contains(first): return false   // "ke", not "ce"
        case "k" where !frontVowels.contains(first): return false  // "ca", not "ka"
        case "gh", "ngh": if !["e", "ê", "i"].contains(first) { return false }
        case "g", "ng": if ["e", "ê"].contains(first) || (initial == "ng" && first == "i") { return false }
        default: break
        }
        if initial == "gi", first == "ê" { rhyme = "i" + rhyme }  // "giết" spells the "iêt" rhyme
        // After "qu" a "y" is the "uy" rhyme: "quỳnh" is "uynh", "quýt" is "uyt".
        if initial == "qu", first == "y" { rhyme = "u" + rhyme }

        let nucleus = String(rhyme.prefix(while: Telex.isVowel))
        let final = String(rhyme.dropFirst(nucleus.count))
        guard let finals = rhymes[nucleus], finals.contains(final) else { return false }
        // Syllables ending in c, ch, p, t only take sắc or nặng.
        if ["c", "ch", "p", "t"].contains(final), ![0, 1, 5].contains(tone) { return false }
        return true
    }

    // MARK: - Live typing

    /// Marks a later key can still add to a vowel: circumflex ("e" -> "ê") or
    /// horn/breve ("o" -> "ô", "ơ"). Tones are ignored: a tone key can replace
    /// the tone at any time.
    private static let vowelVariants: [Character: [Character]] = [
        "a": ["a", "â", "ă"], "e": ["e", "ê"], "o": ["o", "ô", "ơ"], "u": ["u", "ư"],
    ]

    private static func nucleusVariants(_ nucleus: [Character]) -> [String] {
        var result = [""]
        for c in nucleus {
            let options = vowelVariants[c] ?? [c]
            result = result.flatMap { prefix in options.map { prefix + String($0) } }
        }
        return result
    }

    /// Whether `letters` (lowercase, composed, no tone) can still become a valid
    /// syllable by typing more letters, tone keys or modifier keys. Errs on the
    /// side of "yes": a wrong "no" would corrupt real Vietnamese.
    static func isViablePrefix(_ letters: [Character]) -> Bool {
        // No vowel yet ("str", "ngh", "đ"): consonant keys alone are never rewritten.
        guard letters.contains(where: Telex.isVowel) else { return true }
        let word = String(letters)
        // Try every way to split off an initial; "gi"/"qu" may also be g/q + vowel.
        for initial in [""] + initials where word.hasPrefix(initial) {
            if isViableRhyme(initial: initial, rest: Array(letters.dropFirst(initial.count))) { return true }
        }
        return false
    }

    private static func isViableRhyme(initial: String, rest: [Character]) -> Bool {
        guard let first = rest.first else { return true }  // just the initial so far
        guard Telex.isVowel(first) else { return false }
        switch initial {
        case "c" where frontVowels.contains(first): return false
        case "k" where !frontVowels.contains(first): return false
        case "gh", "ngh": if !["e", "ê", "i"].contains(first) { return false }
        case "g", "ng": if ["e", "ê"].contains(first) || (initial == "ng" && first == "i") { return false }
        default: break
        }
        var rhyme = rest
        if initial == "gi", first == "ê" { rhyme.insert("i", at: 0) }  // "giết" spells the "iêt" rhyme
        if initial == "qu", first == "y" { rhyme.insert("u", at: 0) }  // "quỳnh" spells the "uynh" rhyme

        let nucleus = Array(rhyme.prefix(while: Telex.isVowel))
        let final = String(rhyme.dropFirst(nucleus.count))
        guard nucleus.count <= 3 else { return false }
        for variant in nucleusVariants(nucleus) {
            if final.isEmpty {
                if nucleusPrefixes.contains(variant) { return true }
            } else if let finals = rhymes[variant], finals.contains(where: { $0.hasPrefix(final) }) {
                return true
            }
        }
        return false
    }
}
