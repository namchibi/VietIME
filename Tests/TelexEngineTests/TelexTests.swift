import Foundation
import Testing
@testable import TelexEngine

@Test(arguments: [
    // basic diacritics
    ("aa", "â"), ("ee", "ê"), ("oo", "ô"), ("aw", "ă"), ("ow", "ơ"), ("uw", "ư"), ("ddi", "đi"),
    ("w", "ư"), ("nhw", "như"), ("ww", "w"), ("aaa", "aa"), ("uww", "uw"), ("ddd", "dd"),
    // tones
    ("as", "á"), ("af", "à"), ("ar", "ả"), ("ax", "ã"), ("aj", "ạ"), ("asz", "a"), ("ass", "as"),
    // real words
    ("vieejt", "việt"), ("tieengs", "tiếng"), ("nguwowif", "người"), ("dduwowcj", "được"),
    ("hoaf", "hoà"), ("thuys", "thuý"), ("khoer", "khoẻ"), ("toans", "toán"), ("hoangf", "hoàng"),
    ("mais", "mái"), ("caos", "cáo"), ("quas", "quá"), ("gias", "giá"), ("gif", "gì"),
    ("ngoaif", "ngoài"), ("muwas", "mứa"), ("cuwus", "cứu"), ("thuyeenf", "thuyền"),
    ("tuaans", "tuấn"), ("Vieejt", "Việt"), ("DDaay", "Đây"), ("VIEEJT", "VIỆT"),
    ("thuowr", "thuở"), ("huow", "huơ"), ("xooong", "xoong"), ("ngoeof", "ngoèo"),
    // free order
    ("tiengse", "tiếng"), ("vietje", "việt"),
    // no vowel: tone keys stay literal
    ("s", "s"), ("nhs", "nhs"),
    // a modifier key only undoes itself when pressed twice in a row
    ("window", "ưindow"), ("asns", "áns"),
    // "w" on "ua" marks the "u" ("ưa"), except after "q" where "u" is a consonant
    ("suawr", "sửa"), ("muaw", "mưa"), ("cuawr", "cửa"), ("giuawx", "giữa"), ("luawr", "lửa"),
    ("quaw", "quă"), ("hoawcj", "hoặc"),
    // a later "d" turns the initial "d" into "đ"
    ("did", "đi"), ("Did", "Đi"), ("DID", "ĐI"), ("duowcjd", "được"), ("dongd", "đong"), ("didd", "did"),
    // "ưo" is completed to "ươ"
    ("huwong", "hương"), ("nguwoif", "người"), ("dduwocj", "được"), ("thuwor", "thuở"), ("ruwouj", "rượu"),
])
func transform(raw: String, expected: String) {
    #expect(Telex.transform(raw) == expected)
}

@Test(arguments: [
    "window", "class", "access", "google", "book", "words", "swift", "Facebook", "yes", "for",
    "with", "user", "fast", "www", "hello", "camelCase", "github", "code", "free",
    "of", "if", "or", "is",
    "two", "dead", "died", "decide", "divide", "divided", "deadline", "dude",
])
func englishWordsComeOutAsTyped(word: String) {
    #expect(Telex.finalize(word) == word)
}

@Test(arguments: [
    ("ww", "w"), ("dd", "đ"), ("vieejt", "việt"), ("thuowr", "thuở"),
    ("suawr", "sửa"), ("did", "đi"), ("huwong", "hương"),
])
func finalizeKeepsDeliberateText(raw: String, expected: String) {
    #expect(Telex.finalize(raw) == expected)
}

/// Stand-in for the system dictionary.
private let dictionary: Set<String> = ["push", "merge", "class", "error", "password", "book", "did", "dad"]

@Test(arguments: [
    // a modifier pressed twice to cancel it drops out when that spells a word
    ("pussh", "push"), ("merrge", "merge"), ("classs", "class"), ("errror", "error"), ("passsword", "password"),
    // a real double letter stays
    ("class", "class"), ("error", "error"), ("password", "password"),
    // "ww", "jj", "ooo", "ddd" never occur in English, so they drop out even in unknown words
    ("wworrktrree", "worktree"), ("boook", "book"), ("www", "www"),
    // "did" means "đi"; a second "d" cancels it back to the English word
    ("didd", "did"), ("dadd", "dad"),
    // unknown word, ambiguous double: keep every key, as before
    ("stderr", "stderr"), ("useEffect", "useEffect"),
])
func cancelledModifiers(raw: String, expected: String) {
    #expect(Telex.finalize(raw, isEnglish: dictionary.contains) == expected)
}

@Test func userEnglishWords() {
    #expect(Telex.finalize("this") == "thí")
    #expect(Telex.finalize("this", englishWords: ["this"]) == "this")
}

/// Every word of real Vietnamese text, typed in plain Telex, must survive the
/// whole pipeline unchanged.
private let vietnameseText = """
    tôi yêu tiếng nước tôi từ khi mới ra đời người ơi mẹ hiền ru những câu xa vời à à ơi tiếng ru muôn đời
    khuya khuỷu khuấy quyết quyển huyền thuở huơ rượu cười tươi chuyện tuyết hoà thuý khoẻ hoặc xoắn
    ngoằn ngoèo oái oăm giết giếng giữ giường gìn gì giàu giỏi gieo giặt giấy quốc quả quý quê quay quân
    quăng ếch kệch huých uỵch huynh khuynh toát loét hoạch oanh xoong boong soóc đường đi được ước uống
    ăn ở anh em ông bà cháu chắt nghỉ nghe ghế ghi kiếm kìa kỹ cửa mưa gửi cứu hưu bướu ngược thường
    nhanh chóng sách vở bút mực thước kẻ thịt cá rau muống bánh mì phở bò hủ tiếu yên yếm ngoáy khuyên
    hoen khoét thuế huệch tuềnh xuân khuâng khuất buồn thuốc chuông nuôi ươm lượm bướp mướt hươu
    quỳnh quýt quỵt quyến quyện Quỳnh
    """

private let vietnameseWords = vietnameseText.split(whereSeparator: \.isWhitespace).map(String.init)

@Test func vietnameseRoundTrip() {
    for word in vietnameseWords {
        let raw = telexKeys(for: word)
        #expect(Telex.finalize(raw) == word, "typed \(raw)")
    }
}

/// Plain Telex keystrokes for a Vietnamese word: diacritics right after their
/// letter, the tone key at the end.
private func telexKeys(for word: String) -> String {
    var keys = ""
    var tone = ""
    var previous = ""
    for letter in word {
        var letterKeys = ""
        for scalar in String(letter).decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar {
            case "\u{0302}": letterKeys.append(letterKeys.last!)  // circumflex: â ê ô
            case "\u{0306}", "\u{031B}": letterKeys.append("w")  // breve ă, horn ơ ư
            case "\u{0301}": tone = "s"
            case "\u{0300}": tone = "f"
            case "\u{0309}": tone = "r"
            case "\u{0303}": tone = "x"
            case "\u{0323}": tone = "j"
            case "đ": letterKeys.append("dd")
            default: letterKeys.unicodeScalars.append(scalar)
            }
        }
        // A plain "oo" has to be typed "ooo", since "oo" means "ô".
        keys += previous == "o" && letterKeys == "o" ? "oo" : letterKeys
        previous = letterKeys
    }
    return keys + tone
}

// MARK: - Tone style

@Test(arguments: [
    ("hoaf", "hòa"), ("khoer", "khỏe"), ("thuys", "thúy"), ("quys", "qúy"),
    // closed syllables and other vowel clusters are unaffected
    ("hoangf", "hoàng"), ("khuyur", "khuỷu"), ("toans", "toán"), ("tieengs", "tiếng"),
    ("mais", "mái"), ("ngoaif", "ngoài"), ("thuyeenf", "thuyền"), ("khoer", "khỏe"),
])
func classicToneStyle(raw: String, expected: String) {
    // "quys": the "u" of "qu" is a consonant, so "qúy" is wrong, "quý" right (checked below)
    if raw == "quys" { #expect(Telex.transform(raw, toneStyle: .classic) == "quý"); return }
    #expect(Telex.transform(raw, toneStyle: .classic) == expected)
    #expect(Telex.finalize(raw, toneStyle: .classic) == expected)
}

@Test(arguments: [("hoaf", "hoà"), ("khoer", "khoẻ"), ("thuys", "thuý"), ("hoangf", "hoàng")])
func modernToneStyleIsDefault(raw: String, expected: String) {
    #expect(Telex.transform(raw) == expected)
    #expect(Telex.transform(raw, toneStyle: .modern) == expected)
    #expect(Telex.liveText(raw, toneStyle: .modern) == expected)
}

@Test func classicLiveText() {
    #expect(Telex.liveText("hoaf", toneStyle: .classic) == "hòa")
}

// MARK: - Live text

/// Every prefix of every Vietnamese word's keystrokes must be shown exactly
/// as plain Telex would, so typing Vietnamese is never disturbed mid-word.
@Test func liveTextNeverDisturbsVietnamese() {
    let freeOrder = ["tiengse", "vietje", "nguwowif", "dduwowcj", "tieesng", "thuyeenf", "thuowr", "huow"]
    let raws = vietnameseWords.map(telexKeys(for:)) + freeOrder
    for raw in raws {
        for n in 1...raw.count {
            let prefix = String(raw.prefix(n))
            #expect(Telex.liveText(prefix) == Telex.transform(prefix), "typing \(raw), at \(prefix)")
            // Same with capitals.
            let upper = prefix.capitalized
            #expect(Telex.liveText(upper) == Telex.transform(upper), "typing \(raw), at \(upper)")
        }
    }
}

@Test(arguments: [
    "push", "merge", "worktree", "class", "github", "window", "swift", "hello", "error",
    "stderr", "branch", "commit", "print", "return", "import", "function", "string", "const",
    "react", "python", "docker", "terminal", "console", "slack", "build",
])
func liveTextShowsEnglishAsTypedByTheEnd(word: String) {
    #expect(Telex.liveText(word) == word, "\(word) -> \(Telex.liveText(word))")
}

@Test(arguments: [
    ("th", "th"), ("thu", "thu"), ("thuo", "thuo"), ("thuow", "thuơ"), ("tieng", "tieng"),
    ("tiengs", "tiéng"), ("gi", "gi"), ("qu", "qu"), ("ngh", "ngh"), ("nghe", "nghe"),
    ("push", "push"), ("puh", "puh"), ("pus", "pú"), ("hel", "hel"), ("wh", "wh"),
    ("ww", "w"), ("wwo", "wo"), ("wwork", "work"), ("pussh", "pussh"),
])
func liveTextExamples(raw: String, expected: String) {
    #expect(Telex.liveText(raw) == expected)
}

// MARK: - finalizeWithReason and flags

@Test(arguments: [
    ("hello", "hello", FinalizeReason.unchanged),
    ("vieejt", "việt", .vietnamese),
    ("a", "a", .unchanged),
    ("this", "this", .userEnglishWord),
    ("pussh", "push", .collapsedByDictionary),
    ("boook", "book", .collapsedByImpossibleDouble),
    ("class", "class", .keptByDictionary),
    ("stderr", "stderr", .notVietnamese),
])
func reasons(raw: String, expected: String, reason: FinalizeReason) {
    let r = Telex.finalizeWithReason(
        raw, englishWords: Telex.defaultEnglishWords.union(["this"]),
        isEnglish: ["push", "class"].contains)
    #expect(r.text == expected)
    #expect(r.reason == reason)
}

@Test func restoreEnglishFalseIsPlainTelex() {
    for raw in ["window", "class", "this", "pussh", "vieejt", "ww", "of"] {
        let r = Telex.finalizeWithReason(raw, restoreEnglish: false)
        #expect(r.text == Telex.transform(raw))
        #expect(r.reason == (r.text == raw ? .unchanged : .restoreDisabled))
    }
    #expect(Telex.finalize("hoaf", toneStyle: .classic, restoreEnglish: false) == "hòa")
}

@Test func unikeyDoubleKeysFalseSkipsCollapsing() {
    #expect(Telex.finalize("pussh", isEnglish: ["push"].contains) == "push")
    #expect(Telex.finalize("pussh", isEnglish: ["push"].contains, unikeyDoubleKeys: false) == "pussh")
    #expect(Telex.finalize("wwork", unikeyDoubleKeys: false) == "wwork")
    #expect(Telex.finalize("vieejt", unikeyDoubleKeys: false) == "việt")
}

@Test(arguments: [
    "Việt", "tiếng", "người", "được", "đi", "Đà", "thuở", "khuyên", "quyết", "giờ", "gì",
    "hoà", "khoẻ", "nghiêng", "ươn", "ĂN", "Ư", "hello",
])
func keysSpellTheTextBack(text: String) {
    let keys = Telex.keys(for: text)
    #expect(keys != nil)
    #expect(keys.map { Telex.transform($0) } == text, "\(text) -> \(keys ?? "nil")")
}

@Test func keysForTextThatIsNotOneWord() {
    #expect(Telex.keys(for: "a b") == nil)
    #expect(Telex.keys(for: "áà") == nil)  // two tones
    #expect(Telex.keys(for: "x1") == nil)
}
