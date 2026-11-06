import AppKit
import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
    case general, typing, english, apps

    /// The whole window, title bar and tab bar included.
    static let windowSize = NSSize(width: 720, height: 720)

    var title: String {
        switch self {
        case .general: return "Chung"
        case .typing: return "Gõ phím"
        case .english: return "Từ tiếng Anh"
        case .apps: return "Ứng dụng"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .typing: return "keyboard"
        case .english: return "book"
        case .apps: return "square.grid.2x2"
        }
    }
}

final class SettingsNavigation: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Preference-style header (title bar + icon tabs, as in the design) over the selected tab.
struct SettingsRootView: View {
    @ObservedObject var navigation: SettingsNavigation

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                Color.clear.frame(height: 30)  // the transparent title bar: traffic lights and title
                HStack(spacing: 4) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        TabButton(tab: tab, isSelected: navigation.tab == tab) { navigation.tab = tab }
                    }
                }
                .padding(.top, 2)
                .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
            .background(SettingsPalette.header)
            .overlay(alignment: .bottom) { SettingsPalette.headerBorder.frame(height: 1) }

            Group {
                switch navigation.tab {
                case .general: GeneralTab()
                case .typing: TypingTab()
                case .english: EnglishTab()
                case .apps: AppsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: SettingsTab.windowSize.width, height: SettingsTab.windowSize.height)
        .background(SettingsPalette.page)
        .ignoresSafeArea()
    }
}

private struct TabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 17, weight: .regular))
                    .frame(width: 22, height: 22)
                Text(tab.title).font(.system(size: 11))
            }
            .foregroundColor(isSelected ? SettingsPalette.accent : SettingsPalette.tab)
            .frame(width: 84)
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? SettingsPalette.tabSelected : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Settings window; its title follows the selected tab.
final class SettingsWindowController {
    static let shared = SettingsWindowController()

    private let navigation = SettingsNavigation()
    private var window: NSWindow?
    private var titleSink: Any?

    private init() {}

    /// Creates the window on first use, optionally switches tab, and brings it to the front
    /// (the app is an accessory app, so it has to activate itself to take keyboard focus).
    func show(tab: SettingsTab? = nil) {
        if let tab { navigation.tab = tab }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: SettingsTab.windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: SettingsRootView(navigation: navigation))
        host.sizingOptions = []
        window.contentView = host
        // fullSizeContentView: the frame is the content, title bar included.
        window.setFrame(NSRect(origin: .zero, size: SettingsTab.windowSize), display: false)
        window.center()
        titleSink = navigation.$tab.sink { [weak window] in window?.title = $0.title }
        return window
    }
}
