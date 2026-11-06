import AppKit
import ApplicationServices
import SwiftUI

/// The "give VietIME Accessibility permission" window. The app polls for the permission itself
/// (see AppDelegate); this window only explains and opens System Settings.
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?
    private var promptedOnce = false

    var isVisible: Bool { window?.isVisible ?? false }

    func show() {
        if window == nil {
            let view = OnboardingView(
                onLater: { [weak self] in self?.close() },
                onOpenSettings: { [weak self] in self?.openSystemSettings() }
            )
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            let host = NSHostingView(rootView: view)
            host.sizingOptions = []  // keep the window at the frame set below
            w.contentView = host
            // fullSizeContentView: the frame is the content, title bar included.
            w.setFrame(NSRect(x: 0, y: 0, width: 560, height: 600), display: false)
            w.delegate = self
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() {
        window?.close()
    }

    private func openSystemSettings() {
        // One system prompt per launch is enough: it is what makes the app appear in the Accessibility list.
        if !promptedOnce {
            promptedOnce = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct OnboardingView: View {
    let onLater: () -> Void
    let onOpenSettings: () -> Void

    private let steps = [
        "Bấm “Mở Cài đặt Hệ thống” bên dưới.",
        "Bật công tắc cạnh VietIME trong Quyền riêng tư & Bảo mật › Trợ năng.",
        "Quay lại đây. VietIME tự nhận, không cần mở lại app.",
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text("VI")
                .font(.system(size: 24, weight: .bold))
                .tracking(0.6)
                .foregroundColor(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 0.114, green: 0.114, blue: 0.122)))
                .frame(width: 72, height: 72)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white).shadow(color: .black.opacity(0.12), radius: 4, y: 1))

            VStack(spacing: 8) {
                Text("Cho phép VietIME nhận phím gõ")
                    .font(.system(size: 20, weight: .semibold))
                Text("VietIME cần quyền Trợ năng để thấy phím bạn gõ và thay bằng chữ có dấu. Mọi thứ xử lý ngay trên máy, không gửi đi đâu.")
                    .font(.system(size: 13))
                    .foregroundColor(SettingsPalette.body)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                ForEach(steps.indices, id: \.self) { i in
                    HStack(spacing: 12) {
                        Text("\(i + 1)")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(SettingsPalette.badge))
                        Text(steps[i])
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    if i < steps.count - 1 { RowDivider() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10).fill(SettingsPalette.box))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(SettingsPalette.boxBorder))

            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang chờ quyền…")
                    .font(.system(size: 12))
                    .foregroundColor(SettingsPalette.secondary)
            }

            HStack(spacing: 10) {
                Button(action: onLater) {
                    Text("Để sau").padding(.horizontal, 18).frame(height: 40)
                }
                .buttonStyle(OnboardingButtonStyle(primary: false))
                Button(action: onOpenSettings) {
                    Text("Mở Cài đặt Hệ thống").fontWeight(.semibold).padding(.horizontal, 18).frame(height: 40)
                }
                .buttonStyle(OnboardingButtonStyle(primary: true))
                .keyboardShortcut(.defaultAction)
            }

            Spacer(minLength: 0)

            Text("Đã bật mà vẫn chờ? Tắt rồi bật lại VietIME trong danh sách. macOS gắn quyền với chữ ký của app, nên sau khi build lại có thể phải cấp lại.")
                .font(.system(size: 11.5))
                .foregroundColor(SettingsPalette.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 44)
        .padding(.top, 36)
        .padding(.bottom, 28)
        .frame(width: 560, height: 600)
        .background(SettingsPalette.page)
        .ignoresSafeArea()
    }
}

private struct OnboardingButtonStyle: ButtonStyle {
    let primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundColor(primary ? .white : .primary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(primary ? Color(red: 0.039, green: 0.388, blue: 0.847) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(primary ? Color.clear : Color.primary.opacity(0.18)))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
