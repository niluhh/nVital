import Foundation
import IOKit

/// Small read-only helpers over the IOKit registry.
enum IORegistry {
    /// `MACH_PORT_NULL` selects the default main port on every macOS version
    /// (`kIOMasterPortDefault` is deprecated, `kIOMainPortDefault` needs 12.0).
    private static let mainPort: mach_port_t = 0

    /// All properties of the first service of class `className`.
    static func properties(ofServiceMatching className: String) -> [String: Any]? {
        let service = IOServiceGetMatchingService(mainPort, IOServiceMatching(className))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var properties: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = properties?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    /// One property of the first service of class `className`.
    static func property(_ key: String, ofServiceMatching className: String) -> Any? {
        let service = IOServiceGetMatchingService(mainPort, IOServiceMatching(className))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        return IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
