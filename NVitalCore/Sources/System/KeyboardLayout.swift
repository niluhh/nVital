import Carbon.HIToolbox
import Foundation

/// The keyboard in use: its physical shape and what each key types with the
/// current input source (e.g. "Ñ" with a Spanish layout).
public struct KeyboardLayout {
    public enum Shape: String {
        /// US style: Return on a single row, no key between left shift and Z.
        case ansi = "ANSI"
        /// European style: tall Return and an extra key next to left shift.
        case iso = "ISO"
        /// Japanese: tall Return plus the ¥, _, 英数 and かな keys.
        case jis = "JIS"
    }

    public let shape: Shape
    /// Input source name, e.g. "Español - ISO".
    public let name: String
    private let labels: [UInt16: String]

    public init(shape: Shape, name: String, labels: [UInt16: String] = [:]) {
        self.shape = shape
        self.name = name
        self.labels = labels
    }

    /// e.g. "Español - ISO (ISO)".
    public var description: String {
        return "\(name) (\(shape.rawValue))"
    }

    /// The character the key types, as printed on its keycap; `nil` for keys
    /// that do not type one (Return, arrows…).
    public func label(for keyCode: UInt16) -> String? {
        return labels[keyCode]
    }

    /// Reads the keyboard in use. Text Input Sources only work on the main thread.
    public static func current() -> KeyboardLayout {
        dispatchPrecondition(condition: .onQueue(.main))
        let keyboardType = LMGetKbdType()
        let shape = Shape(physicalType: KBGetLayoutType(Int16(keyboardType)))

        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue() else {
            return KeyboardLayout(shape: shape, name: "Desconocida")
        }
        var name = "Desconocida"
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        }

        var labels: [UInt16: String] = [:]
        if let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                guard let base = bytes.baseAddress else { return }
                let layout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
                // Every virtual key code; those that do not type a character are skipped.
                for keyCode in UInt16(0)..<0x80 {
                    labels[keyCode] = keycapLabel(keyCode, layout: layout, keyboardType: UInt32(keyboardType))
                }
            }
        }
        return KeyboardLayout(shape: shape, name: name, labels: labels)
    }

    private static func keycapLabel(_ keyCode: UInt16, layout: UnsafePointer<UCKeyboardLayout>, keyboardType: UInt32) -> String? {
        var deadKeyState: UInt32 = 0
        var length: UniCharCount = 0
        var characters = [UniChar](repeating: 0, count: 4)
        // No modifiers; dead keys (´ ` ^ ¨) give their own character.
        let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, keyboardType,
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                                    UniCharCount(characters.count), &length, &characters)
        guard status == 0, length > 0 else { return nil }

        let text = String(utf16CodeUnits: characters, count: Int(length)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return nil
        }
        // Keycaps show letters in upper case ("Ñ"), but ß stays ß rather than "SS".
        let upper = text.uppercased()
        return upper.count == text.count ? upper : text
    }
}

extension KeyboardLayout.Shape {
    /// From Carbon's `PhysicalKeyboardLayoutType` four-character codes.
    init(physicalType: UInt32) {
        switch physicalType {
        case 0x4953_4F20: self = .iso // "ISO "
        case 0x4A49_5320: self = .jis // "JIS "
        default: self = .ansi
        }
    }
}
