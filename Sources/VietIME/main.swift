import AppKit
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let menuController = MenuController()
    private var pollTimer: Timer?
    /// True once the event tap is running (Accessibility permission granted).
    private var running = false
    /// Vietnamese on/off at the last state change, to spot real changes on app switches.
    private var lastEnabled = KeyHandler.shared.enabled
    private var watchdog: Timer?
    /// Name of the app holding Secure Input while it keeps keys from reaching the tap.
    private var secureInputHolder: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menuController.menu
        statusItem.button?.imagePosition = .imageOnly
        menuController.onChange = { [weak self] in self?.refresh() }

        KeyHandler.shared.onStateChange = { [weak self] reason in self?.stateChanged(reason) }
        refresh()
        startTap()
        // NSSpellChecker loads its dictionary on the first call (~170 ms). Pay that
        // now, while nothing is being typed, instead of on the first finished word.
        DispatchQueue.main.async { SpellCheck.warmUp() }
    }

    /// Installs the event tap now if Accessibility is granted; otherwise shows onboarding and polls.
    private func startTap() {
        if AXIsProcessTrusted(), KeyHandler.shared.start() {
            tapStarted()
            return
        }
        refresh()
        OnboardingWindowController.shared.show()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted(), KeyHandler.shared.start() else { return }
            timer.invalidate()
            self?.pollTimer = nil
            self?.tapStarted()
        }
        RunLoop.main.add(timer, forMode: .common)  // keep polling while a menu is open
        pollTimer = timer
    }

    /// The tap is running: at launch, after onboarding, or once Accessibility came back.
    private func tapStarted() {
        running = true
        // `start()` has applied the launch mode by now; the value captured when
        // this delegate was created predates it.
        lastEnabled = KeyHandler.shared.enabled
        startWatchdog()
        OnboardingWindowController.shared.close()
        refresh()
    }

    /// Once a second: revive the tap if macOS dropped it, and notice Secure Input,
    /// which blocks the tap while the icon would otherwise still say "VI".
    private func startWatchdog() {
        guard watchdog == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.checkTap() }
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
        // Sleep/wake and fast user switching are when taps most often get dropped.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidBecomeActiveNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.checkTap() }
        }
        checkTap()
    }

    private func checkTap() {
        // Accessibility can be reset behind our back (macOS updates, a new build
        // signature, tccutil): the tap is dead then, so the icon must stop saying
        // "VI" and the onboarding window has to come back. The same check notices
        // the permission being granted again and starts the tap without a relaunch.
        let trusted = AXIsProcessTrusted()
        if running, !trusted {
            tapLog.error("Accessibility permission lost; stopping the event tap")
            KeyHandler.shared.stop()
            running = false
            refresh()
            OnboardingWindowController.shared.show()
        } else if !running, trusted, KeyHandler.shared.start() {
            tapLog.notice("Accessibility permission granted; event tap started")
            tapStarted()
        }

        KeyHandler.shared.ensureTapEnabled()
        let holder = SecureInput.isEnabled ? (SecureInput.holderName() ?? "một app khác") : nil
        guard holder != secureInputHolder else { return }
        if let holder {
            tapLog.notice("secure input enabled by \(holder, privacy: .public)")
        } else {
            tapLog.notice("secure input released")
            KeyHandler.shared.resetBuffer()  // keys typed while blocked never reached the buffer
        }
        secureInputHolder = holder
        menuController.secureInputHolder = holder
        refresh()
    }

    private func refresh() {
        let state: StatusIconState
        if !running {
            state = .noPermission
        } else if secureInputHolder != nil {
            state = .blocked
        } else if KeyHandler.shared.frontAppIsOff {
            state = .off
        } else {
            state = KeyHandler.shared.enabled ? .vietnamese : .english
        }
        statusItem.button?.image = StatusIcon.image(for: state)
        statusItem.button?.title = ""
        statusItem.button?.setAccessibilityLabel("VietIME")
        statusItem.button?.toolTip = {
            switch state {
            case .vietnamese: return "VietIME: Tiếng Việt"
            case .english: return "VietIME: English"
            case .off: return "VietIME: tắt trong app này"
            case .noPermission: return "VietIME: chưa có quyền Trợ năng"
            case .blocked: return "VietIME: bị chặn bởi Secure Input (\(secureInputHolder ?? "?"))"
            }
        }()
    }

    private func stateChanged(_ reason: StateChangeReason) {
        refresh()
        let handler = KeyHandler.shared
        let enabled = handler.enabled
        defer { lastEnabled = enabled }
        guard running, Settings.shared.showToast else { return }

        let app = handler.frontApp
        let isOff = handler.frontAppIsOff
        switch reason {
        case .hotkey:
            Toast.show(vietnamese: enabled, app: app?.name, mode: nil)
        case .menu:
            break  // the user is looking at the switch they just flipped
        case .appSwitch:
            // Not on every app switch: only when the app has its own rule or the state really changed.
            // "Tự nhớ" is the default, not a rule, whether Settings stored it or the menu removed it.
            guard let app else { return }
            let rule = Settings.shared.appModes[app.bundleID].flatMap { $0 == .auto ? nil : $0 }
            guard rule != nil || enabled != lastEnabled else { return }
            Toast.show(vietnamese: enabled && !isOff, app: app.name, mode: isOff ? .off : (rule ?? .auto))
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
