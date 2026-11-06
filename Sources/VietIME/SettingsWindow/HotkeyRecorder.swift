import AppKit
import CoreGraphics
import SwiftUI

/// Captures one key combination with a local key-down monitor.
/// While recording, VietIME's own tap must not treat the hotkey as a toggle.
final class HotkeyRecorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?

    func start(onCapture: @escaping (Hotkey) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        KeyHandler.shared.isRecordingHotkey = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 {  // Esc cancels
                self.stop()
                return nil
            }
            let flags = Self.cgFlags(event.modifierFlags)
            guard !flags.isEmpty else { return nil }  // need at least one modifier; swallow the key
            onCapture(Hotkey(keyCode: event.keyCode, modifiers: flags.rawValue))
            self.stop()
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording { isRecording = false }
        KeyHandler.shared.isRecordingHotkey = false
    }

    private static func cgFlags(_ flags: NSEvent.ModifierFlags) -> CGEventFlags {
        var result = CGEventFlags()
        if flags.contains(.control) { result.insert(.maskControl) }
        if flags.contains(.option) { result.insert(.maskAlternate) }
        if flags.contains(.shift) { result.insert(.maskShift) }
        if flags.contains(.command) { result.insert(.maskCommand) }
        return result
    }

    deinit { stop() }
}

struct HotkeyRow: View {
    @ObservedObject var settings: Settings
    @StateObject private var recorder = HotkeyRecorder()

    var body: some View {
        SettingsRow(title: "Phím tắt") {
            HStack(spacing: 8) {
                Button {
                    if recorder.isRecording {
                        recorder.stop()
                    } else {
                        recorder.start { settings.hotkey = $0 }
                    }
                } label: {
                    Text(recorder.isRecording ? "Nhấn phím tắt…" : settings.hotkey.display)
                        .foregroundColor(recorder.isRecording ? SettingsPalette.secondary : .primary)
                        .frame(minWidth: 80, minHeight: 26, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Bấm rồi nhấn tổ hợp phím mới. Esc để huỷ")
                .accessibilityLabel("Phím tắt hiện tại: \(settings.hotkey.display). Bấm để ghi phím mới")
                if !recorder.isRecording {
                    Button {
                        settings.hotkey = .standard
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Color(nsColor: .tertiaryLabelColor))
                    }
                    .buttonStyle(.plain)
                    .help("Về mặc định (⌃⇧Space)")
                    .accessibilityLabel("Về mặc định")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6).fill(SettingsPalette.field))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(recorder.isRecording ? Color.accentColor : SettingsPalette.fieldBorder,
                                  lineWidth: recorder.isRecording ? 2 : 1)
            )
        }
        .onDisappear { recorder.stop() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            recorder.stop()
        }
    }
}
