import SwiftUI
import TelexEngine

/// macOS English dictionary verdict, same as the one the key handler uses.
func systemDictionaryKnows(_ word: String) -> Bool {
    SpellCheck.isEnglish(word)
}

/// Why `raw` came out as `result`, in the words of the "Thử gõ" table.
func reasonText(_ reason: FinalizeReason, raw: String, result: String) -> String {
    switch reason {
    case .unchanged: return "Giữ nguyên"
    case .vietnamese:
        return systemDictionaryKnows(raw) ? "Trùng âm tiết tiếng Việt" : "Âm tiết tiếng Việt hợp lệ"
    case .userEnglishWord: return "Trong danh sách từ tiếng Anh của bạn"
    case .notVietnamese: return "Không phải âm tiết tiếng Việt, giữ nguyên"
    case .collapsedByDictionary:
        return "Bỏ “\(firstDifference(raw, result))” gõ đúp vì “\(result)” có trong từ điển"
    case .collapsedByImpossibleDouble:
        let run = repeatedRun(in: raw, around: Telex.cancelledKeys(in: raw).impossible.first)
        return "Có “\(run)”, tiếng Anh không viết vậy nên bỏ hết phím gõ đúp"
    case .keptByDictionary:
        let run = repeatedRun(in: raw, around: Telex.cancelledKeys(in: raw).all.first)
        return "Giữ “\(run)” vì “\(result)” có trong từ điển"
    case .restoreDisabled: return "Đã tắt tự trả về tiếng Anh"
    }
}

/// The first key of `raw` that `result` dropped: "s" for pussh → push.
private func firstDifference(_ raw: String, _ result: String) -> String {
    let a = Array(raw.lowercased()), b = Array(result.lowercased())
    let i = zip(a, b).prefix { $0 == $1 }.count
    return i < a.count ? String(a[i]) : ""
}

/// The run of one repeated key around the key at `offset` in `raw`: "ss" for the
/// "s" that cancelled the tone in "success", "ddd" for the last "d" of "ddd".
/// Taken from the engine's cancelled keys, not from the first run in the word,
/// which would say "cc" for "success".
private func repeatedRun(in raw: String, around offset: Int?) -> String {
    let chars = raw.map { Character($0.lowercased()) }
    guard let offset, chars.indices.contains(offset) else { return "" }
    var start = offset
    var end = offset
    while start > 0, chars[start - 1] == chars[offset] { start -= 1 }
    while end + 1 < chars.count, chars[end + 1] == chars[offset] { end += 1 }
    return String(chars[start...end])
}

struct TypingTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var sample = "pussh class wworrktrree thuowr this"

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Kiểu gõ") {
                SettingsRow(title: "Kiểu gõ") {
                    Picker("Kiểu gõ", selection: .constant("Telex")) {
                        Text("Telex").tag("Telex")
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help("Hiện chỉ có Telex")
                }
                RowDivider()
                SettingsRow(title: "Đặt dấu") {
                    Picker("Đặt dấu", selection: $settings.toneStyle) {
                        Text("Kiểu mới: hoà, thuý").tag(ToneStyle.modern)
                        Text("Kiểu cũ: hòa, thúy").tag(ToneStyle.classic)
                    }
                    .labelsHidden()
                    .pickerStyle(.radioGroup)
                    .horizontalRadioGroupLayout()
                    .fixedSize()
                }
            }
            SettingsSection(title: "Gõ lẫn tiếng Anh") {
                SettingsRow(title: "Tự trả về từ tiếng Anh",
                            subtitle: "Gõ google rồi bấm cách thì ra google, không ra gôgle") {
                    SettingsSwitch(label: "Tự trả về từ tiếng Anh", isOn: $settings.restoreEnglish)
                }
                RowDivider()
                SettingsRow(title: "Hiểu gõ đúp kiểu Unikey",
                            subtitle: "pussh ra push, classs ra class. Dùng từ điển tiếng Anh của macOS") {
                    SettingsSwitch(label: "Hiểu gõ đúp kiểu Unikey", isOn: $settings.unikeyDoubleKeys)
                }
                RowDivider()
                SettingsRow(title: "Hiện tiếng Anh ngay khi đang gõ",
                            subtitle: "Không chờ dấu cách: gõ tới chữ h của push là thấy push, không thấy púh",
                            badge: "Thử nghiệm") {
                    SettingsSwitch(label: "Hiện tiếng Anh ngay khi đang gõ", isOn: $settings.livePreview)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Thử gõ").font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
                SettingsBox {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("pussh class wworrktrree thuowr this", text: $sample)
                            .textFieldStyle(SettingsFieldStyle())
                            .autocorrectionDisabled()
                            .accessibilityLabel("Thử gõ")
                        TryTypingTable(sample: sample, settings: settings)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
        }
    }
}

private struct TryTypingTable: View {
    let sample: String
    @ObservedObject var settings: Settings

    private var words: [String] {
        Array(sample.split(whereSeparator: \.isWhitespace).prefix(30).map(String.init))
    }

    var body: some View {
        let englishWords = Telex.defaultEnglishWords.union(settings.userEnglishWords)
        if words.isEmpty {
            Text("Gõ phím Telex thô vào ô trên để xem VietIME xử lý từng từ ra sao.")
                .font(.system(size: 11.5))
                .foregroundColor(SettingsPalette.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                row(Text("Phím gõ"), Text("Ra"), Text("Vì sao"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(SettingsPalette.secondary)
                    .padding(.bottom, 4)
                ForEach(Array(words.enumerated()), id: \.offset) { _, raw in
                    let result = Telex.finalizeWithReason(
                        raw,
                        englishWords: englishWords,
                        isEnglish: systemDictionaryKnows,
                        toneStyle: settings.toneStyle,
                        restoreEnglish: settings.restoreEnglish,
                        unikeyDoubleKeys: settings.unikeyDoubleKeys
                    )
                    RowDivider()
                    row(
                        Text(raw).font(.mono(12.5)).foregroundColor(SettingsPalette.body),
                        Text(result.text).font(.mono(12.5, weight: .semibold)),
                        HStack(spacing: 10) {
                            Text(reasonText(result.reason, raw: raw, result: result.text)).foregroundColor(SettingsPalette.body)
                            if result.reason != .userEnglishWord, result.text != raw, systemDictionaryKnows(raw) {
                                Button("Giữ tiếng Anh") { settings.addEnglishWord(raw) }
                                    .buttonStyle(.link)
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                        }
                    )
                    .font(.system(size: 12.5))
                    .frame(height: 28)
                }
            }
        }
    }

    private func row(_ keys: some View, _ output: some View, _ why: some View) -> some View {
        HStack(spacing: 12) {
            keys.lineLimit(1).frame(width: 120, alignment: .leading)
            output.lineLimit(1).frame(width: 90, alignment: .leading)
            why.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
