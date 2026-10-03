import Foundation

/// Asks the user to sweep the whole trackpad, click, secondary-click, scroll and pinch.
public final class TrackpadTest: DiagnosticTest {
    public let identifier = "trackpad"
    public let name = "Trackpad"
    public let summary = "Comprueba el movimiento por toda la superficie, los clics y los gestos."
    public let category = DiagnosticCategory.input
    public let requiresInteraction = true

    let columns = 8
    let rows = 5

    public init() {}

    public func isApplicable(to machine: MachineInfo) -> Bool {
        return machine.isPortable
    }

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        let request = TrackpadCaptureRequest(
            instructions: "Mueve el puntero por todas las casillas, haz clic, clic secundario, desplaza con dos dedos y pellizca para hacer zoom. Pulsa «Terminar» cuando acabes.",
            columns: columns,
            rows: rows)

        context.request(.trackpad(request)) { response in
            switch response {
            case .trackpad(let result):
                completion(Self.evaluate(result))
            case .unavailable:
                completion(.skipped("Esta prueba necesita al usuario."))
            case .cancelled:
                completion(.cancelled)
            default:
                completion(.skippedByUser)
            }
        }
    }

    static func evaluate(_ result: TrackpadCaptureResult) -> DiagnosticOutcome {
        let coverage = result.totalCells > 0 ? Double(result.visitedCells) / Double(result.totalCells) : 0
        func yesNo(_ value: Bool) -> String { return value ? "Sí" : "No" }
        let measurements = [
            DiagnosticMeasurement("Superficie recorrida", String(format: "%.0f %%", coverage * 100)),
            DiagnosticMeasurement("Clic", yesNo(result.primaryClick)),
            DiagnosticMeasurement("Clic secundario", yesNo(result.secondaryClick)),
            DiagnosticMeasurement("Desplazamiento", yesNo(result.scrolled)),
            DiagnosticMeasurement("Pellizco", yesNo(result.pinched)),
        ]

        var problems: [String] = []
        if coverage < 0.9 { problems.append("el puntero no ha recorrido toda la superficie") }
        if !result.primaryClick { problems.append("no se ha detectado el clic") }
        if !problems.isEmpty {
            return .failed("Fallo: " + problems.joined(separator: "; ") + ".", measurements)
        }

        var missingGestures: [String] = []
        if !result.secondaryClick { missingGestures.append("clic secundario") }
        if !result.scrolled { missingGestures.append("desplazamiento") }
        if !result.pinched { missingGestures.append("pellizco") }
        if !missingGestures.isEmpty {
            return .warning("No se han detectado: " + missingGestures.joined(separator: ", ") + ".", measurements)
        }
        return .passed("El trackpad responde en toda la superficie y reconoce los gestos.", measurements)
    }
}
