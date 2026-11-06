import AppKit
import SwiftUI

struct AppsTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var selected: String?

    private func name(for id: String) -> String {
        if let name = settings.appNames[id], !name.isEmpty { return name }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return url.deletingPathExtension().lastPathComponent
        }
        return id.split(separator: ".").last.map(String.init) ?? id
    }

    private func icon(for id: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }

    private var ids: [String] {
        settings.appModes.keys.sorted { name(for: $0).localizedCaseInsensitiveCompare(name(for: $1)) == .orderedAscending }
    }

    private func modeBinding(_ id: String) -> Binding<AppMode> {
        Binding(
            get: { settings.appModes[id] ?? .auto },
            set: {
                settings.appModes[id] = $0
                KeyHandler.shared.reapplyAppMode()
            }
        )
    }


    private func addApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Thêm"
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url),
              let id = bundle.bundleIdentifier else { return }
        let display = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        settings.appNames[id] = display
        if settings.appModes[id] == nil { settings.appModes[id] = .english }
        selected = id
        KeyHandler.shared.reapplyAppMode()
    }

    private func removeSelected() {
        guard let id = selected else { return }
        settings.removeApp(id)
        selected = nil
        KeyHandler.shared.reapplyAppMode()
    }

    /// What the app is doing now, under its name.
    private func status(for id: String) -> String {
        switch settings.mode(for: id) {
        case .vietnamese: return "Luôn mở tiếng Việt"
        case .english: return "Luôn mở tiếng Anh"
        case .off: return "VietIME không đụng tới phím nào"
        case .auto:
            guard let remembered = settings.appMemory[id] else { return "Chưa dùng lần nào" }
            return remembered ? "Đang gõ tiếng Việt" : "Đang gõ tiếng Anh"
        }
    }

    var body: some View {
        SettingsPage {
            SettingsBox {
                SettingsRow(title: "Nhớ tiếng Việt/Anh theo từng ứng dụng",
                            subtitle: "Chuyển app là tự về chế độ dùng lần cuối ở app đó") {
                    SettingsSwitch(label: "Nhớ tiếng Việt/Anh theo từng ứng dụng", isOn: $settings.perAppMemory)
                }
            }
            SettingsSection(title: "Quy tắc riêng") {
                if settings.appModes.isEmpty {
                    Text("Chưa có quy tắc nào. Bấm + để thêm một ứng dụng.")
                        .foregroundColor(SettingsPalette.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 52)
                    RowDivider()
                }
                ForEach(ids, id: \.self) { id in
                    HStack(spacing: 12) {
                        Image(nsImage: icon(for: id)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(name(for: id)).foregroundColor(selected == id ? .white : .primary)
                            Text(status(for: id))
                                .font(.system(size: 11.5))
                                .foregroundColor(selected == id ? .white.opacity(0.8) : SettingsPalette.secondary)
                        }
                        Spacer(minLength: 0)
                        Picker("Chế độ cho \(name(for: id))", selection: modeBinding(id)) {
                            Text("Tự nhớ").tag(AppMode.auto)
                            Text("Luôn tiếng Việt").tag(AppMode.vietnamese)
                            Text("Luôn tiếng Anh").tag(AppMode.english)
                            Divider()
                            Text("Tắt VietIME").tag(AppMode.off)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 52)
                    .background(selected == id ? Color.accentColor : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { selected = selected == id ? nil : id }
                    RowDivider()
                }
                HStack(spacing: 2) {
                    Button(action: addApp) {
                        Image(systemName: "plus").frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .help("Thêm ứng dụng")
                    .accessibilityLabel("Thêm ứng dụng")
                    Button(action: removeSelected) {
                        Image(systemName: "minus").frame(width: 28, height: 28).contentShape(Rectangle())
                    }
                    .disabled(selected == nil)
                    .help("Bỏ ứng dụng đã chọn")
                    .accessibilityLabel("Bỏ ứng dụng đã chọn")
                    Spacer()
                }
                .buttonStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(SettingsPalette.body)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(SettingsPalette.boxFooter)
            }
            SettingsFootnote(text: "“Tắt VietIME” thì không đụng tới phím nào trong app đó. Nên dùng cho app có phím tắt một chữ: VietIME sửa chữ bằng cách gửi phím xoá, có thể xoá nhầm thứ đang chọn. Chỉ bật “Từng phím” khi app bỏ mất phần lớn chữ VietIME gửi: khi đó mỗi ký tự đi thành một phím riêng.")
        }
    }
}
