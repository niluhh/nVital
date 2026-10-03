import Foundation
import IOKit
import IOKit.hidsystem

/// What the top row of Apple keyboards sends: special features (brightness,
/// Mission Control, volume…) or the standard F1–F12 keys.
///
/// This is the live state behind "Use F1, F2, etc. keys as standard function
/// keys". Changing it here does not touch the user's saved preference, which
/// macOS applies again at the next login.
public enum FunctionKeyMode: Int {
    /// macOS default: the top row controls brightness, volume, Mission Control…
    /// and F1–F12 need fn.
    case specialFeatures = 0
    /// The top row sends F1–F12; the special features need fn.
    case standardFunctionKeys = 1

    /// Live mode, falling back to the user's saved preference when the HID
    /// system cannot be read.
    public static var current: FunctionKeyMode {
        if let parameters = IORegistry.property("HIDParameters", ofServiceMatching: "IOHIDSystem") as? [String: Any],
           let value = parameters["HIDFKeyMode"] as? Int,
           let mode = FunctionKeyMode(rawValue: value) {
            return mode
        }
        return preferred
    }

    /// The mode chosen in System Settings, which macOS applies at login.
    public static var preferred: FunctionKeyMode {
        return UserDefaults.standard.bool(forKey: "com.apple.keyboard.fnState") ? .standardFunctionKeys : .specialFeatures
    }

    /// Changes the live mode. Returns `false` if the HID system refused it.
    @discardableResult
    public static func set(_ mode: FunctionKeyMode) -> Bool {
        let service = IOServiceGetMatchingService(0, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }

        var connection: io_connect_t = 0
        let paramConnectType: UInt32 = 1 // kIOHIDParamConnectType
        guard IOServiceOpen(service, mach_task_self_, paramConnectType, &connection) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connection) }

        let value = NSNumber(value: mode.rawValue)
        return IOHIDSetCFTypeParameter(connection, "HIDFKeyMode" as CFString, value) == KERN_SUCCESS
    }

    // MARK: - Temporary override

    private static let lock = NSLock()
    /// Mode to put back, saved so it survives a crash during the keyboard test.
    private static let savedModeKey = "NVitalCore.functionKeyModeToRestore"

    /// Makes the top row send F1–F12 until `endTemporaryOverride()`.
    /// Returns `true` when the top row now sends F1–F12.
    @discardableResult
    public static func beginTemporaryOverride() -> Bool {
        lock.lock()
        defer { lock.unlock() }

        // Restore to the user's preference rather than the live mode, which
        // the registry may report stale: that is what macOS applies at login.
        if UserDefaults.standard.object(forKey: savedModeKey) == nil {
            UserDefaults.standard.set(preferred.rawValue, forKey: savedModeKey)
        }
        if set(.standardFunctionKeys) {
            return true
        }
        UserDefaults.standard.removeObject(forKey: savedModeKey)
        return current == .standardFunctionKeys
    }

    /// Puts back the mode saved by `beginTemporaryOverride()`, if any.
    /// Safe to call at any time, e.g. at launch to recover from a crash.
    public static func endTemporaryOverride() {
        lock.lock()
        defer { lock.unlock() }

        guard let raw = UserDefaults.standard.object(forKey: savedModeKey) as? Int else { return }
        if let mode = FunctionKeyMode(rawValue: raw) {
            set(mode)
        }
        UserDefaults.standard.removeObject(forKey: savedModeKey)
    }
}
