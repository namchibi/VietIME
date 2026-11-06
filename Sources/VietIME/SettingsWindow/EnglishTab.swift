import SwiftUI
import TelexEngine

struct EnglishTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var newWord = ""

    /// Built-in words, most common first.
    private var defaults: [String] {
        let order = ["of", "if", "or", "is", "us", "www"]
        return order.filter(Telex.defaultEnglishWords.contains)
            + Telex.defaultEnglishWords.subtracting(order).sorted()
    }

    /// What the word would become if it were not in the list.
    private func withoutList(_ word: String) -> String {
        Telex.finalize(
            word,
            englishWords: [],
            isEnglish: { _ in false },
            toneStyle: settings.toneStyle,
            restoreEnglish: settings.restoreEnglish,
            unikeyDoubleKeys: settings.unikeyDoubleKeys
        )
    }

    private func add() {
        settings.addEnglishWord(newWord)
        newWord = ""
    }

    private var canAdd: Bool { !newWord.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        SettingsPage(spacing: 14) {
            Text("Những từ này luôn giữ tiếng Anh, kể cả khi trùng âm tiết tiếng Việt.")
                .foregroundColor(SettingsPalette.body)
                .padding(.leading, 4)
            HStack(spacing: 8) {
                TextField("Thêm từ, ví dụ: these", text: $newWord)
                    .textFieldStyle(SettingsFieldStyle())
                    .autocorrectionDisabled()
                    .onSubmit { if canAdd { add() } }
                    .accessibilityLabel("Từ mới")
                Button(action: { if canAdd { add() } }) {
                    Text("Thêm")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(SettingsPalette.accent))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
            SettingsBox {
                columns(
                    Text("Bạn thêm · \(settings.userEnglishWords.count)"),
                    Text("Nếu không có trong danh sách"),
                    Color.clear
                )
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(SettingsPalette.secondary)
                .padding(.top, 8)
                .padding(.bottom, 4)
                if settings.userEnglishWords.isEmpty {
                    RowDivider()
                    Text("Chưa có từ nào. Thêm ở ô trên, hoặc bấm “Luôn giữ tiếng Anh” trong menu.")
                        .foregroundColor(SettingsPalette.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                }
                ForEach(settings.userEnglishWords, id: \.self) { word in
                    RowDivider()
                    let alt = withoutList(word)
                    columns(
                        Text(word).font(.mono()),
                        Text(alt != word ? "thành “\(alt)”" : "giữ nguyên").foregroundColor(SettingsPalette.secondary),
                        Button {
                            settings.userEnglishWords.removeAll { $0 == word }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 15))
                                .foregroundColor(Color(nsColor: .systemGray))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Xoá “\(word)”")
                        .accessibilityLabel("Xoá \(word)")
                    )
                    .frame(height: 36)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Có sẵn · \(defaults.count)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(SettingsPalette.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                        ForEach(defaults, id: \.self) { word in
                            Text(word)
                                .font(.mono())
                                .frame(maxWidth: .infinity)
                                .frame(height: 28)
                                .background(RoundedRectangle(cornerRadius: 6).fill(SettingsPalette.field))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsPalette.boxBorder))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 10)
                .padding(.bottom, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsPalette.boxFooter)
                .overlay(alignment: .top) { SettingsPalette.boxBorder.frame(height: 1) }
            }
            SettingsFootnote(text: "Không cần thêm push, merge, class…: từ không phải âm tiết tiếng Việt đã tự trả về khi bấm cách, phần gõ đúp có từ điển macOS lo. Chỉ thêm những từ trùng âm tiết Việt như trên. Bấm “Luôn giữ tiếng Anh” trong menu cũng thêm vào đây.")
        }
    }

    /// Word, what it would become, delete button: the list's three columns.
    private func columns(_ word: some View, _ alt: some View, _ action: some View) -> some View {
        HStack(spacing: 0) {
            word.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            alt.lineLimit(1).frame(width: 200, alignment: .leading)
            action.frame(width: 32)
        }
        .padding(.horizontal, 14)
    }
}
