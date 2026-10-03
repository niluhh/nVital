import CoreGraphics
import Foundation

/// Reads the built-in display's properties and shows full-screen patterns so
/// the user can look for dead pixels, banding or backlight bleed.
public final class DisplayTest: DiagnosticTest {
    public let identifier = "display"
    public let name = "Pantalla"
    public let summary = "Muestra colores sólidos y patrones para detectar píxeles muertos y defectos."
    public let category = DiagnosticCategory.display
    public let requiresInteraction = true

    static let patterns: [DisplayPattern] = [
        DisplayPattern(name: "Blanco", kind: .solid(red: 1, green: 1, blue: 1)),
        DisplayPattern(name: "Negro", kind: .solid(red: 0, green: 0, blue: 0)),
        DisplayPattern(name: "Rojo", kind: .solid(red: 1, green: 0, blue: 0)),
        DisplayPattern(name: "Verde", kind: .solid(red: 0, green: 1, blue: 0)),
        DisplayPattern(name: "Azul", kind: .solid(red: 0, green: 0, blue: 1)),
        DisplayPattern(name: "Gris", kind: .solid(red: 0.5, green: 0.5, blue: 0.5)),
        DisplayPattern(name: "Degradado", kind: .horizontalGradient),
        DisplayPattern(name: "Damero", kind: .checkerboard(size: 8)),
    ]

    public init() {}

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        let display = Self.preferredDisplay()
        var measurements = Self.describe(display)

        if display.isBuiltIn == false && context.machine.hasBuiltInMedia {
            measurements.append(DiagnosticMeasurement("Nota", "La pantalla integrada no está activa (¿tapa cerrada?). Se usará la pantalla principal."))
        }

        let request = DisplayPatternRequest(
            instructions: "Se mostrarán \(Self.patterns.count) patrones a pantalla completa. Busca píxeles muertos o atascados, manchas, líneas y zonas con brillo irregular. Haz clic o pulsa una tecla para avanzar; esc para salir.",
            patterns: Self.patterns,
            displayID: display.id)

        context.request(.displayPatterns(request)) { response in
            switch response {
            case .acknowledged:
                self.askForDefects(context: context, measurements: measurements, completion: completion)
            case .unavailable:
                completion(.skipped("La revisión visual necesita al usuario.", measurements))
            case .cancelled:
                completion(.cancelled)
            default:
                completion(.skippedByUser)
            }
        }
    }

    private func askForDefects(context: DiagnosticContext, measurements: [DiagnosticMeasurement], completion: @escaping (DiagnosticOutcome) -> Void) {
        let question = ConfirmationRequest(
            title: "¿La pantalla se ha visto correctamente?",
            message: "Responde «No» si has visto píxeles muertos, manchas, líneas, zonas más claras o colores irregulares.",
            confirmTitle: "Sí, sin defectos",
            denyTitle: "No, hay defectos")
        context.request(.confirmation(question)) { response in
            switch response {
            case .confirmed(true):
                completion(.passed("La pantalla no presenta defectos visibles.", measurements))
            case .confirmed(false):
                completion(.failed("El usuario ha detectado defectos en la pantalla.", measurements))
            case .cancelled:
                completion(.cancelled)
            default:
                completion(.skippedByUser)
            }
        }
    }

    // MARK: - Display information

    struct DisplayDescription {
        let id: CGDirectDisplayID
        let isBuiltIn: Bool
    }

    /// The active built-in display if there is one, otherwise the main display.
    static func preferredDisplay() -> DisplayDescription {
        var count: UInt32 = 0
        _ = CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        _ = CGGetActiveDisplayList(count, &displays, &count)

        if let builtIn = displays.first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            return DisplayDescription(id: builtIn, isBuiltIn: true)
        }
        return DisplayDescription(id: CGMainDisplayID(), isBuiltIn: false)
    }

    static func describe(_ display: DisplayDescription) -> [DiagnosticMeasurement] {
        var measurements = [DiagnosticMeasurement("Pantalla", display.isBuiltIn ? "Integrada" : "Externa / principal")]
        if let mode = CGDisplayCopyDisplayMode(display.id) {
            measurements.append(DiagnosticMeasurement("Resolución", "\(mode.pixelWidth) × \(mode.pixelHeight) píxeles"))
            if mode.refreshRate > 0 {
                measurements.append(DiagnosticMeasurement("Frecuencia", String(format: "%.0f Hz", mode.refreshRate)))
            }
        }
        let size = CGDisplayScreenSize(display.id)
        if size.width > 0, size.height > 0 {
            let inches = (size.width * size.width + size.height * size.height).squareRoot() / 25.4
            measurements.append(DiagnosticMeasurement("Diagonal", String(format: "%.1f\"", inches)))
        }
        return measurements
    }
}
