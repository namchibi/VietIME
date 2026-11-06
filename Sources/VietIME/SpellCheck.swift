import AppKit

/// The macOS English dictionary.
///
/// `NSSpellChecker` loads its dictionary on the first call (measured at ~168 ms,
/// later calls ~0.2 ms), and it runs inside the event tap, so `warmUp()` pays the
/// load cost at launch. The tap only asks about a finished word that has a
/// cancelled double key and isn't Vietnamese ("class", "pussh"): `Telex.finalize`
/// needs the verdict to choose between the two. Every other word is only
/// recorded, and the menu asks about it when it opens.
///
/// Main thread only: `NSSpellChecker` is driven from the same run loop as the tap.
enum SpellCheck {
    /// NSSpellChecker can be slow even when warm; the menu asks about the same
    /// word on every open, so keep the verdicts.
    private static var cache: [String: Bool] = [:]
    private static let cacheLimit = 4096

    static func isEnglish(_ word: String) -> Bool {
        let key = word.lowercased()
        if let known = cache[key] { return known }
        let known = NSSpellChecker.shared.checkSpelling(
            of: word, startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        ).location == NSNotFound
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = known
        return known
    }

    /// Loads the dictionary once, so the first real check never costs 168 ms.
    /// Called from the main queue right after launch.
    static func warmUp() {
        _ = NSSpellChecker.shared.checkSpelling(
            of: "vietime", startingAt: 0, language: "en", wrap: false, inSpellDocumentWithTag: 0, wordCount: nil
        )
    }
}
