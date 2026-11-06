import AppKit
import SwiftUI

/// Colors from the design mockups, with dark-mode counterparts.
enum SettingsPalette {
    static let page = dynamic(0xEBEBEB, NSColor(hex: 0x232325))
    static let header = dynamic(0xF6F6F6, NSColor(hex: 0x2C2C2E))
    static let headerBorder = dynamic(0xD6D6D6, NSColor(white: 0, alpha: 0.5))
    static let tab = dynamic(0x4A4A4E, NSColor(hex: 0xAEAEB2))
    static let tabSelected = dynamic(0xE6E6E8, NSColor(white: 1, alpha: 0.10))
    static let accent = dynamic(0x0A63D8, NSColor(hex: 0x3B8CFF))
    static let box = dynamic(0xF6F6F6, NSColor(white: 1, alpha: 0.05))
    static let boxBorder = dynamic(0xDDDDDD, NSColor(white: 1, alpha: 0.10))
    static let boxFooter = dynamic(0xF0F0F0, NSColor(white: 1, alpha: 0.03))
    static let divider = dynamic(0xE3E3E3, NSColor(white: 1, alpha: 0.07))
    static let secondary = dynamic(0x636366, NSColor(hex: 0x98989D))
    static let body = dynamic(0x3A3A3C, NSColor(hex: 0xC7C7CC))
    static let field = dynamic(0xFFFFFF, NSColor(white: 1, alpha: 0.08))
    static let fieldBorder = dynamic(0xC9C9CE, NSColor(white: 1, alpha: 0.18))
    static let badge = dynamic(0xE3E3E8, NSColor(white: 1, alpha: 0.12))
    static let success = dynamic(0x1E7F3C, NSColor(hex: 0x4CC764))

    private static func dynamic(_ light: UInt32, _ dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// The page every tab sits in: 32 pt side margins, 18 pt between groups,
/// an optional footer pinned to the bottom.
struct SettingsPage<Content: View, Footer: View>: View {
    var spacing: CGFloat = 18
    var top: CGFloat = 20
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) { content }
                    .padding(.horizontal, 32)
                    .padding(.top, top)
                    .padding(.bottom, 20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer.padding(.horizontal, 32).padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .font(.system(size: 13))
    }
}

extension SettingsPage where Footer == EmptyView {
    init(spacing: CGFloat = 18, top: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.init(spacing: spacing, top: top, content: content, footer: { EmptyView() })
    }
}

/// A titled rounded box of rows, like a grouped Form section.
struct SettingsSection<Content: View>: View {
    var title: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                Text(title).font(.system(size: 13, weight: .semibold)).padding(.leading, 4)
            }
            SettingsBox { content }
        }
    }
}

struct SettingsBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SettingsPalette.box)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(SettingsPalette.boxBorder))
    }
}

struct RowDivider: View {
    var body: some View { SettingsPalette.divider.frame(height: 1) }
}

/// Title (+ optional subtitle and badge) on the left, a control on the right, at least 44 pt tall.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var badge: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title)
                    if let badge { SettingsBadge(text: badge) }
                }
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5))
                        .foregroundColor(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minHeight: 44)
    }
}

struct SettingsBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundColor(SettingsPalette.body)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(SettingsPalette.badge))
    }
}

struct SettingsSwitch: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(label, isOn: $isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// Small grey text under or between boxes.
struct SettingsFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .foregroundColor(SettingsPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 4)
    }
}

/// 30 pt white monospaced text field.
struct SettingsFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .font(.mono())
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(SettingsPalette.field))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SettingsPalette.fieldBorder))
    }
}

extension Font {
    static func mono(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
