import Foundation

/// Asks the user to press every key of the built-in keyboard.
public final class KeyboardTest: DiagnosticTest {
    public let identifier = "keyboard"
    public let name = "Teclado"
    public let summary = "Comprueba que todas las teclas del teclado integrado responden."
    public let category = DiagnosticCategory.input
    public let requiresInteraction = true

    public init() {}

    public func isApplicable(to machine: MachineInfo) -> Bool {
        return machine.isPortable
    }

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        let request = KeyboardCaptureRequest(
            instructions: "Pulsa una vez cada tecla del teclado. Las teclas se iluminan al detectarse. Pulsa «Terminar» cuando acabes.",
            keys: Self.laptopKeys)

        context.request(.keyboard(request)) { response in
            switch response {
            case .keyboard(let result):
                completion(Self.evaluate(pressed: result.pressedKeyCodes, keys: Self.laptopKeys))
            case .unavailable:
                completion(.skipped("Esta prueba necesita al usuario."))
            case .cancelled:
                completion(.cancelled)
            default:
                completion(.skippedByUser)
            }
        }
    }

    static func evaluate(pressed: Set<UInt16>, keys: [KeyDescriptor]) -> DiagnosticOutcome {
        let required = keys.filter { $0.isRequired }
        let missing = required.filter { !pressed.contains($0.keyCode) }
        let missingOptional = keys.filter { !$0.isRequired && !pressed.contains($0.keyCode) }
        let detected = keys.filter { pressed.contains($0.keyCode) }.count

        var measurements = [DiagnosticMeasurement("Teclas detectadas", "\(detected) de \(keys.count)")]
        if !missing.isEmpty {
            measurements.append(DiagnosticMeasurement("Sin respuesta", missing.map { $0.label }.joined(separator: ", ")))
        }
        if !missingOptional.isEmpty {
            measurements.append(DiagnosticMeasurement("Opcionales sin pulsar", missingOptional.map { $0.label }.joined(separator: ", ")))
        }

        if missing.isEmpty {
            return .passed("Todas las teclas responden.", measurements)
        }
        let noun = missing.count == 1 ? "tecla no ha respondido" : "teclas no han respondido"
        return .failed("\(missing.count) \(noun).", measurements)
    }

    /// Mac laptop keyboard, identified by virtual key code (Carbon `kVK_*`).
    /// Key codes are physical positions, so labels follow the US layout.
    static let laptopKeys: [KeyDescriptor] = {
        func key(_ code: UInt16, _ label: String, _ row: Int, _ width: Double = 1, required: Bool = true) -> KeyDescriptor {
            return KeyDescriptor(keyCode: code, label: label, row: row, width: width, isRequired: required)
        }
        return [
            // Function row. F-keys are optional: they act as media keys by default
            // and do not exist on Touch Bar models; neither does a physical Escape.
            key(0x35, "esc", 0, 1.5, required: false),
            key(0x7A, "F1", 0, required: false), key(0x78, "F2", 0, required: false),
            key(0x63, "F3", 0, required: false), key(0x76, "F4", 0, required: false),
            key(0x60, "F5", 0, required: false), key(0x61, "F6", 0, required: false),
            key(0x62, "F7", 0, required: false), key(0x64, "F8", 0, required: false),
            key(0x65, "F9", 0, required: false), key(0x6D, "F10", 0, required: false),
            key(0x67, "F11", 0, required: false), key(0x6F, "F12", 0, required: false),

            key(0x32, "`", 1), key(0x12, "1", 1), key(0x13, "2", 1), key(0x14, "3", 1),
            key(0x15, "4", 1), key(0x17, "5", 1), key(0x16, "6", 1), key(0x1A, "7", 1),
            key(0x1C, "8", 1), key(0x19, "9", 1), key(0x1D, "0", 1), key(0x1B, "-", 1),
            key(0x18, "=", 1), key(0x33, "delete", 1, 1.5),

            key(0x30, "tab", 2, 1.5), key(0x0C, "Q", 2), key(0x0D, "W", 2), key(0x0E, "E", 2),
            key(0x0F, "R", 2), key(0x11, "T", 2), key(0x10, "Y", 2), key(0x20, "U", 2),
            key(0x22, "I", 2), key(0x1F, "O", 2), key(0x23, "P", 2), key(0x21, "[", 2),
            key(0x1E, "]", 2), key(0x2A, "\\", 2),

            key(0x39, "caps lock", 3, 1.75), key(0x00, "A", 3), key(0x01, "S", 3), key(0x02, "D", 3),
            key(0x03, "F", 3), key(0x05, "G", 3), key(0x04, "H", 3), key(0x26, "J", 3),
            key(0x28, "K", 3), key(0x25, "L", 3), key(0x29, ";", 3), key(0x27, "'", 3),
            key(0x24, "return", 3, 1.75),

            key(0x38, "shift", 4, 1.5), key(0x0A, "§", 4, required: false), key(0x06, "Z", 4),
            key(0x07, "X", 4), key(0x08, "C", 4), key(0x09, "V", 4), key(0x0B, "B", 4),
            key(0x2D, "N", 4), key(0x2E, "M", 4), key(0x2B, ",", 4), key(0x2C, ".", 4),
            key(0x2F, "/", 4), key(0x3C, "shift", 4, 2.25),

            key(0x3F, "fn", 5, required: false), key(0x3B, "control", 5), key(0x3A, "option", 5),
            key(0x37, "command", 5, 1.25), key(0x31, "space", 5, 5), key(0x36, "command", 5, 1.25),
            key(0x3D, "option", 5), key(0x7B, "←", 5), key(0x7E, "↑", 5), key(0x7D, "↓", 5),
            key(0x7C, "→", 5),
        ]
    }()
}
