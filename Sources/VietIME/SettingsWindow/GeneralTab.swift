import ApplicationServices
import ServiceManagement
import SwiftUI

/// Registers or removes the main app as a login item.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns false when the system refused (for example an unsigned dev build).
    @discardableResult
    static func set(_ on: Bool) -> Bool {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return true
        } catch {
            return false
        }
    }
}

struct GeneralTab: View {
    @ObservedObject var settings = Settings.shared
    @State private var accessibilityGranted = AXIsProcessTrusted()
    @State private var loginFailed = false

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return "VietIME \(v ?? "0.1.0")"
    }

    private var loginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchAtLogin },
            set: { wanted in
                let ok = LoginItem.set(wanted)
                settings.launchAtLogin = LoginItem.isEnabled
                loginFailed = !ok || settings.launchAtLogin != wanted
            }
        )
    }

    var body: some View {
        SettingsPage(spacing: 20, top: 22) {
            SettingsSection(title: "Bật/tắt tiếng Việt") {
                HotkeyRow(settings: settings)
                RowDivider()
                SettingsRow(title: "Hiện thông báo khi chuyển", subtitle: "Nhãn nhỏ dưới menu bar trong khoảng 1 giây") {
                    SettingsSwitch(label: "Hiện thông báo khi chuyển", isOn: $settings.showToast)
                }
            }
            SettingsSection(title: "Khởi động") {
                SettingsRow(
                    title: "Mở VietIME khi đăng nhập",
                    subtitle: loginFailed ? "Không bật được: cần bản app đã ký" : nil
                ) {
                    SettingsSwitch(label: "Mở VietIME khi đăng nhập", isOn: loginBinding)
                }
                RowDivider()
                SettingsRow(title: "Khi mở, gõ") {
                    Picker("Khi mở, gõ", selection: $settings.launchMode) {
                        Text("Như lần trước").tag(LaunchMode.last)
                        Text("Tiếng Việt").tag(LaunchMode.vietnamese)
                        Text("Tiếng Anh").tag(LaunchMode.english)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }
            SettingsSection(title: "Quyền") {
                SettingsRow(title: "Trợ năng (Accessibility)", subtitle: "Cần để nhận phím gõ và thay bằng chữ có dấu") {
                    if accessibilityGranted {
                        Label("Đã cấp", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(SettingsPalette.success)
                    } else {
                        HStack(spacing: 10) {
                            Label("Chưa cấp", systemImage: "exclamationmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.orange)
                            Button("Mở Cài đặt Hệ thống") { Self.openAccessibilitySettings() }
                        }
                    }
                }
            }
        } footer: {
            Text(version)
                .font(.system(size: 11.5))
                .foregroundColor(SettingsPalette.secondary)
                .frame(maxWidth: .infinity)
        }
        .onAppear {
            accessibilityGranted = AXIsProcessTrusted()
            settings.launchAtLogin = LoginItem.isEnabled
        }
        .onReceive(timer) { _ in accessibilityGranted = AXIsProcessTrusted() }
    }

    private static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
