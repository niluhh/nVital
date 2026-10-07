import Foundation

/// Asks the user to press every key of the built-in keyboard, drawn with the
/// shape (ANSI, ISO or JIS) and characters of the layout in use.
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
        // Make the top row send F1–F12 so the keys are detected and do not
        // change the brightness or volume or open Mission Control meanwhile.
        let topRowSendsFunctionKeys = FunctionKeyMode.beginTemporaryOverride()

        // The keyboard layout can only be read on the main thread.
        DispatchQueue.main.async {
            let layout = KeyboardLayout.current()
            let keys = Self.keys(shape: layout.shape, hasTouchBar: context.machine.hasTouchBar, label: layout.label(for:))
            let functionKeysHint = topRowSendsFunctionKeys
                ? "Durante la prueba, F1–F12 funcionan como teclas de función: no cambian el brillo ni el volumen ni abren Mission Control."
                : "Para F1–F12, mantén pulsada la tecla fn a la vez."
            let request = KeyboardCaptureRequest(
                instructions: "Distribución detectada: \(layout.description). Pulsa una vez cada tecla del teclado; se iluminan al detectarse. \(functionKeysHint) Pulsa «Terminar» cuando acabes.",
                keys: keys)

            context.request(.keyboard(request)) { response in
                FunctionKeyMode.endTemporaryOverride()
                switch response {
                case .keyboard(let result):
                    let reliable = topRowSendsFunctionKeys && result.systemShortcutsBlocked
                    var outcome = Self.evaluate(pressed: result.pressedKeyCodes, keys: keys, functionKeysReliable: reliable)
                    outcome.measurements.insert(DiagnosticMeasurement("Distribución", layout.description), at: 0)
                    completion(outcome)
                case .unavailable:
                    completion(.skipped("Esta prueba necesita al usuario."))
                case .cancelled:
                    completion(.cancelled)
                default:
                    completion(.skippedByUser)
                }
            }
        }
    }

    public func cancel() {
        FunctionKeyMode.endTemporaryOverride()
    }

    /// - Parameter functionKeysReliable: `false` when macOS may have kept some
    ///   F-key presses for itself (e.g. F11 shows the desktop), so missing
    ///   F-keys are a warning rather than a failure.
    static func evaluate(pressed: Set<UInt16>, keys: [KeyDescriptor], functionKeysReliable: Bool = true) -> DiagnosticOutcome {
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
        if !functionKeysReliable && missing.allSatisfy({ functionKeyCodes.contains($0.keyCode) }) {
            return .warning("No se han detectado algunas teclas de función. macOS puede reservarlas para sus atajos (F11 muestra el escritorio): da permiso de Accesibilidad a nVital para bloquearlos y repite la prueba.", measurements)
        }
        let noun = missing.count == 1 ? "tecla no ha respondido" : "teclas no han respondido"
        return .failed("\(missing.count) \(noun).", measurements)
    }

    /// F1–F12.
    static let functionKeyCodes: Set<UInt16> = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]

    /// Mac laptop keyboard of the given shape, identified by virtual key code
    /// (Carbon `kVK_*`, i.e. physical positions). Keys that type a character
    /// take their label from `label`, falling back to the US keycap.
    static func keys(shape: KeyboardLayout.Shape, hasTouchBar: Bool,
                     label: @escaping (UInt16) -> String? = { _ in nil }) -> [KeyDescriptor] {
        func char(_ code: UInt16, _ usLabel: String, _ row: Int, _ width: Double = 1) -> KeyDescriptor {
            return KeyDescriptor(keyCode: code, label: label(code) ?? usLabel, row: row, width: width)
        }
        func control(_ code: UInt16, _ symbol: String, _ row: Int, _ width: Double = 1,
                     height: Int = 1, required: Bool = true) -> KeyDescriptor {
            return KeyDescriptor(keyCode: code, label: symbol, row: row, width: width, height: height, isRequired: required)
        }
        func chars(_ list: [(UInt16, String)], _ row: Int) -> [KeyDescriptor] {
            return list.map { char($0.0, $0.1, row) }
        }
        let digits: [(UInt16, String)] = [(0x12, "1"), (0x13, "2"), (0x14, "3"), (0x15, "4"), (0x17, "5"),
                                          (0x16, "6"), (0x1A, "7"), (0x1C, "8"), (0x19, "9"), (0x1D, "0")]
        let topLetters: [(UInt16, String)] = [(0x0C, "Q"), (0x0D, "W"), (0x0E, "E"), (0x0F, "R"), (0x11, "T"),
                                              (0x10, "Y"), (0x20, "U"), (0x22, "I"), (0x1F, "O"), (0x23, "P")]
        let homeLetters: [(UInt16, String)] = [(0x00, "A"), (0x01, "S"), (0x02, "D"), (0x03, "F"), (0x05, "G"),
                                               (0x04, "H"), (0x26, "J"), (0x28, "K"), (0x25, "L")]
        let bottomLetters: [(UInt16, String)] = [(0x06, "Z"), (0x07, "X"), (0x08, "C"), (0x09, "V"), (0x0B, "B"),
                                                 (0x2D, "N"), (0x2E, "M")]

        // Function row. On Touch Bar models F1–F12 are virtual keys shown only
        // while fn is held, so they are reported but not required. Escape is
        // always detectable, physical or on the Touch Bar.
        var keys = [control(0x35, "esc", 0, 1.5)]
        let functionCodes: [UInt16] = [0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F]
        for (index, code) in functionCodes.enumerated() {
            keys.append(control(code, "F\(index + 1)", 0, 1.125, required: !hasTouchBar))
        }

        // Every row is 15 units wide. On ISO and JIS the tall Return starts on
        // row 2 and fills the end of row 3 too.
        switch shape {
        case .ansi:
            keys += [char(0x32, "`", 1)] + chars(digits, 1)
                + [char(0x1B, "-", 1), char(0x18, "=", 1), control(0x33, "⌫", 1, 2)]
            keys += [control(0x30, "⇥", 2, 1.5)] + chars(topLetters, 2)
                + [char(0x21, "[", 2), char(0x1E, "]", 2), char(0x2A, "\\", 2, 1.5)]
            keys += [control(0x39, "⇪", 3, 1.75)] + chars(homeLetters, 3)
                + [char(0x29, ";", 3), char(0x27, "'", 3), control(0x24, "↩", 3, 2.25)]
            keys += [control(0x38, "⇧", 4, 2.25)] + chars(bottomLetters, 4)
                + [char(0x2B, ",", 4), char(0x2F, ".", 4), char(0x2C, "/", 4), control(0x3C, "⇧", 4, 2.75)]
        case .iso:
            // Apple ISO keyboards send 0x0A for the key left of 1 and 0x32 for
            // the one between left shift and Z.
            keys += [char(0x0A, "§", 1)] + chars(digits, 1)
                + [char(0x1B, "-", 1), char(0x18, "=", 1), control(0x33, "⌫", 1, 2)]
            keys += [control(0x30, "⇥", 2, 1.5)] + chars(topLetters, 2)
                + [char(0x21, "[", 2), char(0x1E, "]", 2), control(0x24, "↩", 2, 1.5, height: 2)]
            keys += [control(0x39, "⇪", 3, 1.5)] + chars(homeLetters, 3)
                + [char(0x29, ";", 3), char(0x27, "'", 3), char(0x2A, "\\", 3)]
            keys += [control(0x38, "⇧", 4, 1.25), char(0x32, "`", 4)] + chars(bottomLetters, 4)
                + [char(0x2B, ",", 4), char(0x2F, ".", 4), char(0x2C, "/", 4), control(0x3C, "⇧", 4, 2.75)]
        case .jis:
            keys += chars(digits, 1)
                + [char(0x1B, "-", 1), char(0x18, "^", 1), char(0x5D, "¥", 1), control(0x33, "⌫", 1, 2)]
            keys += [control(0x30, "⇥", 2, 1.5)] + chars(topLetters, 2)
                + [char(0x21, "@", 2), char(0x1E, "[", 2), control(0x24, "↩", 2, 1.5, height: 2)]
            keys += [control(0x3B, "⌃", 3, 1.5, required: false)] + chars(homeLetters, 3)
                + [char(0x29, ";", 3), char(0x27, ":", 3), char(0x2A, "]", 3)]
            keys += [control(0x38, "⇧", 4, 2.25)] + chars(bottomLetters, 4)
                + [char(0x2B, ",", 4), char(0x2F, ".", 4), char(0x2C, "/", 4), char(0x5E, "_", 4), control(0x3C, "⇧", 4, 1.75)]
        }

        let arrows = [control(0x7B, "←", 5), control(0x7E, "↑", 5), control(0x7D, "↓", 5), control(0x7C, "→", 5)]
        switch shape {
        case .ansi, .iso:
            keys += [control(0x3F, "fn", 5, required: false), control(0x3B, "⌃", 5), control(0x3A, "⌥", 5),
                     control(0x37, "⌘", 5, 1.25), control(0x31, "", 5, 4.5), control(0x36, "⌘", 5, 1.25),
                     control(0x3D, "⌥", 5)] + arrows
        case .jis:
            // Where control, caps lock and fn sit differs between JIS models,
            // so they are not required.
            keys += [control(0x3F, "fn", 5, required: false), control(0x39, "⇪", 5, required: false),
                     control(0x3A, "⌥", 5), control(0x37, "⌘", 5, 1.25), control(0x66, "英数", 5, 1.25),
                     control(0x31, "", 5, 3), control(0x68, "かな", 5, 1.25), control(0x36, "⌘", 5, 1.25)] + arrows
        }
        return keys
    }
}
