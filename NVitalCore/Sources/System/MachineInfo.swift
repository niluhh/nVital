import Foundation

/// Identification of the Mac being diagnosed.
public struct MachineInfo: Codable, Equatable {
    /// e.g. "MacBookPro16,1" or "Mac14,2".
    public let modelIdentifier: String
    public let serialNumber: String
    /// "Apple Silicon" or "Intel".
    public let architecture: String
    public let processor: String
    public let memoryBytes: UInt64
    /// e.g. "10.13.6".
    public let systemVersion: String
    /// e.g. "17G14042".
    public let systemBuild: String
    /// MacBook-style machine with a built-in battery, keyboard and trackpad.
    public let isPortable: Bool

    public init(modelIdentifier: String, serialNumber: String, architecture: String, processor: String,
                memoryBytes: UInt64, systemVersion: String, systemBuild: String, isPortable: Bool) {
        self.modelIdentifier = modelIdentifier
        self.serialNumber = serialNumber
        self.architecture = architecture
        self.processor = processor
        self.memoryBytes = memoryBytes
        self.systemVersion = systemVersion
        self.systemBuild = systemBuild
        self.isPortable = isPortable
    }

    /// iMacs and laptops have a built-in camera, speakers, microphone and display.
    public var hasBuiltInMedia: Bool {
        return isPortable || modelIdentifier.hasPrefix("iMac")
    }

    /// MacBook Pro models (2016–2022) whose function row is a Touch Bar
    /// instead of physical F1–F12 keys.
    public var hasTouchBar: Bool {
        return MachineInfo.touchBarModels.contains(modelIdentifier)
    }

    static let touchBarModels: Set<String> = [
        "MacBookPro13,2", "MacBookPro13,3",
        "MacBookPro14,2", "MacBookPro14,3",
        "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
        "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
        "MacBookPro17,1",
        "Mac14,7",
    ]

    public static func current() -> MachineInfo {
        let model = Sysctl.string("hw.model") ?? "Desconocido"
        let isAppleSilicon = (Sysctl.integer("hw.optional.arm64") ?? 0) == 1
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let serial = IORegistry.property("IOPlatformSerialNumber", ofServiceMatching: "IOPlatformExpertDevice") as? String

        return MachineInfo(
            modelIdentifier: model,
            serialNumber: serial ?? "Desconocido",
            architecture: isAppleSilicon ? "Apple Silicon" : "Intel",
            processor: Sysctl.string("machdep.cpu.brand_string") ?? (isAppleSilicon ? "Apple" : "Intel"),
            memoryBytes: UInt64(Sysctl.integer("hw.memsize") ?? 0),
            systemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            systemBuild: Sysctl.string("kern.osversion") ?? "",
            isPortable: model.hasPrefix("MacBook") || BatteryTest.hasInstalledBattery()
        )
    }
}

enum Sysctl {
    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let value = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Reads 32- and 64-bit integer values.
    static func integer(_ name: String) -> Int64? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        if size == MemoryLayout<Int32>.size {
            return Int64(Int32(truncatingIfNeeded: value))
        }
        return value
    }
}
