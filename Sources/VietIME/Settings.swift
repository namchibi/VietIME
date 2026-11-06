import CoreGraphics
import Foundation
import TelexEngine

/// How VietIME treats one app.
enum AppMode: String, CaseIterable {
    case auto        // remember the last Vietnamese/English state used in that app
    case vietnamese  // switch to Vietnamese when the app comes to the front
    case english     // switch to English when the app comes to the front
    case off         // never touch a key in that app, hotkey included
}

/// What state VietIME starts in.
enum LaunchMode: String, CaseIterable {
    case last, vietnamese, english
}

/// The key combination that toggles Vietnamese on and off.
struct Hotkey: Equatable {
    var keyCode: UInt16
    var modifiers: UInt64  // CGEventFlags.rawValue, only control/option/shift/command bits

    static let modifierMask = CGEventFlags([.maskControl, .maskAlternate, .maskShift, .maskCommand])
    static let standard = Hotkey(keyCode: 49, modifiers: CGEventFlags([.maskControl, .maskShift]).rawValue)

    func matches(keyCode code: CGKeyCode, flags: CGEventFlags) -> Bool {
        UInt16(code) == keyCode && flags.intersection(Self.modifierMask).rawValue == modifiers
    }

    /// "⌃⇧Space"
    var display: String {
        let flags = CGEventFlags(rawValue: modifiers)
        var text = ""
        if flags.contains(.maskControl) { text += "⌃" }
        if flags.contains(.maskAlternate) { text += "⌥" }
        if flags.contains(.maskShift) { text += "⇧" }
        if flags.contains(.maskCommand) { text += "⌘" }
        return text + (Self.keyNames[keyCode] ?? "Phím \(keyCode)")
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
        13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
        24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
        35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 36: "Return", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
    ]
}

/// Every user preference, persisted in UserDefaults (domain dev.local.vietime).
/// The tap callback reads it directly; SwiftUI observes it through @Published.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let defaults = UserDefaults.standard

    // Chung
    @Published var hotkey: Hotkey { didSet { defaults.set(Int(hotkey.keyCode), forKey: "HotkeyCode"); defaults.set(hotkey.modifiers, forKey: "HotkeyModifiers") } }
    @Published var showToast: Bool { didSet { defaults.set(showToast, forKey: "ShowToast") } }
    @Published var launchAtLogin: Bool { didSet { defaults.set(launchAtLogin, forKey: "LaunchAtLogin") } }  // the Settings UI also registers the login item
    @Published var launchMode: LaunchMode { didSet { defaults.set(launchMode.rawValue, forKey: "LaunchMode") } }
    /// Vietnamese on/off as it was when the app last changed it, for `LaunchMode.last`.
    var lastEnabled: Bool { get { defaults.object(forKey: "LastEnabled") as? Bool ?? true } set { defaults.set(newValue, forKey: "LastEnabled") } }

    // Gõ phím
    @Published var toneStyle: ToneStyle { didSet { defaults.set(toneStyle.rawValue, forKey: "ToneStyle") } }
    @Published var restoreEnglish: Bool { didSet { defaults.set(restoreEnglish, forKey: "RestoreEnglish") } }
    @Published var unikeyDoubleKeys: Bool { didSet { defaults.set(unikeyDoubleKeys, forKey: "UnikeyDoubleKeys") } }
    @Published var livePreview: Bool { didSet { defaults.set(livePreview, forKey: "LivePreview") } }

    // Từ tiếng Anh (the key predates the settings window: `defaults write dev.local.vietime EnglishWords -array this has`)
    @Published var userEnglishWords: [String] { didSet { defaults.set(userEnglishWords, forKey: "EnglishWords") } }

    // Ứng dụng
    @Published var perAppMemory: Bool { didSet { defaults.set(perAppMemory, forKey: "PerAppMemory") } }
    /// bundle id -> mode. A missing entry means `.auto`.
    @Published var appModes: [String: AppMode] {
        didSet { defaults.set(appModes.mapValues(\.rawValue), forKey: "AppModes") }
    }
    /// bundle id -> the Vietnamese on/off state last used in that app (for `.auto` and `perAppMemory`).
    /// Kept in memory: the tap reads it on every app switch and hotkey press.
    @Published var appMemory: [String: Bool] {
        didSet { defaults.set(appMemory, forKey: "AppMemory") }
    }
    /// Display names for the apps in `appModes`, so the list shows "Slack" and not a bundle id.
    @Published var appNames: [String: String] {
        didSet { defaults.set(appNames, forKey: "AppNames") }
    }
    func mode(for bundleID: String) -> AppMode { appModes[bundleID] ?? .auto }

    /// Takes the app out of the Settings list.
    func removeApp(_ bundleID: String) {
        appModes[bundleID] = nil
    }

    /// Adds a word to the always-English list (lowercased, no duplicates).
    func addEnglishWord(_ word: String) {
        let word = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !word.isEmpty, !userEnglishWords.contains(word) { userEnglishWords.append(word) }
    }

    private init() {
        let d = UserDefaults.standard
        let code = d.object(forKey: "HotkeyCode") as? Int
        let mods = d.object(forKey: "HotkeyModifiers") as? UInt64
        // UInt16(exactly:): a hand-edited or corrupt value must not crash every launch.
        hotkey = code.flatMap { UInt16(exactly: $0) }.map { Hotkey(keyCode: $0, modifiers: mods ?? Hotkey.standard.modifiers) } ?? .standard
        showToast = d.object(forKey: "ShowToast") as? Bool ?? true
        launchAtLogin = d.object(forKey: "LaunchAtLogin") as? Bool ?? false
        launchMode = d.string(forKey: "LaunchMode").flatMap(LaunchMode.init) ?? .last
        toneStyle = d.string(forKey: "ToneStyle").flatMap(ToneStyle.init) ?? .modern
        restoreEnglish = d.object(forKey: "RestoreEnglish") as? Bool ?? true
        unikeyDoubleKeys = d.object(forKey: "UnikeyDoubleKeys") as? Bool ?? true
        livePreview = d.object(forKey: "LivePreview") as? Bool ?? false
        userEnglishWords = d.stringArray(forKey: "EnglishWords") ?? []
        perAppMemory = d.object(forKey: "PerAppMemory") as? Bool ?? true
        appModes = (d.dictionary(forKey: "AppModes") as? [String: String] ?? [:]).compactMapValues(AppMode.init)
        appMemory = d.dictionary(forKey: "AppMemory") as? [String: Bool] ?? [:]
        appNames = d.dictionary(forKey: "AppNames") as? [String: String] ?? [:]
        // Every character now goes out as its own key, so the per-app
        // "Từng phím" switch is gone; drop what an earlier build stored.
        d.removeObject(forKey: "SendEachKeyApps")
    }
}
