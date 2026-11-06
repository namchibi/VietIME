import AppKit
import Carbon
import IOKit

/// macOS "Secure Event Input": while any process has it on (a focused password
/// field, Terminal's Secure Keyboard Entry, a password manager, the lock screen…),
/// key presses never reach event taps, so VietIME silently stops converting.
/// It can't be bypassed; the best we can do is notice it and name the culprit.
enum SecureInput {
    static var isEnabled: Bool { IsSecureEventInputEnabled() }

    /// The app holding Secure Input, read from the console session in the I/O registry
    /// (the same `kCGSSessionSecureInputPID` that `ioreg -l | grep SecureInput` shows).
    /// When a windowless process turns it on, macOS records the frontmost app instead,
    /// so treat the name as a strong hint rather than proof.
    static func holderName() -> String? {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources")
        guard entry != MACH_PORT_NULL else { return nil }
        defer { IOObjectRelease(entry) }
        guard let users = IORegistryEntryCreateCFProperty(entry, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]] else { return nil }
        for user in users {
            guard let pid = (user["kCGSSessionSecureInputPID"] as? NSNumber)?.int32Value, pid > 0 else { continue }
            if let name = NSRunningApplication(processIdentifier: pid)?.localizedName { return name }
            var buffer = [CChar](repeating: 0, count: 256)
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0 { return String(cString: buffer) }
            return "PID \(pid)"
        }
        return nil
    }
}
