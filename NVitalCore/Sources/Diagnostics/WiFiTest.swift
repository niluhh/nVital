import CoreWLAN
import Foundation

/// Checks the Wi-Fi card can scan for networks. Being connected to a network
/// is not required, and a switched-off radio is switched on for the test.
public final class WiFiTest: DiagnosticTest {
    public let identifier = "wifi"
    public let name = "Wi-Fi"
    public let summary = "Comprueba la tarjeta Wi-Fi y busca redes cercanas."
    public let category = DiagnosticCategory.connectivity

    /// Time the radio may take to come up after switching it on.
    let powerOnTimeout: TimeInterval = 8
    /// A scan right after power-on or a roam can come back empty.
    let scanAttempts = 3
    let delayBetweenScans: TimeInterval = 2

    private let lock = NSLock()
    /// Set while the radio is on only because of this test.
    private var interfaceToSwitchOff: CWInterface?

    public init() {}

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        guard let interface = CWWiFiClient.shared().interface() else {
            completion(.failed("No se ha encontrado ninguna interfaz Wi-Fi."))
            return
        }

        var measurements = [
            DiagnosticMeasurement("Interfaz", interface.interfaceName ?? "—"),
            DiagnosticMeasurement("Dirección MAC", interface.hardwareAddress() ?? "—"),
        ]

        if !interface.powerOn() {
            do {
                try interface.setPower(true)
            } catch {
                completion(.warning("El Wi-Fi está apagado y macOS no ha permitido encenderlo (\(error.localizedDescription)). Actívalo y repite la prueba.", measurements))
                return
            }
            switchOffWhenFinished(interface)
            measurements.append(DiagnosticMeasurement("Estado inicial", "Apagado (encendido para la prueba y apagado de nuevo al terminar)"))

            guard Self.wait(upTo: powerOnTimeout, context: context, until: { interface.powerOn() }) else {
                restorePower()
                completion(context.isCancelled ? .cancelled : .failed("El Wi-Fi no se ha encendido.", measurements))
                return
            }
        }

        let connectedRSSI = interface.rssiValue()
        if connectedRSSI != 0 {
            measurements.append(DiagnosticMeasurement("Conectado a una red", "Sí"))
            measurements.append(DiagnosticMeasurement("Señal de la red actual", "\(connectedRSSI) dBm"))
            measurements.append(DiagnosticMeasurement("Velocidad de transmisión", "\(Int(interface.transmitRate())) Mb/s"))
        } else {
            measurements.append(DiagnosticMeasurement("Conectado a una red", "No (no afecta al resultado)"))
        }

        let scan = scanForNetworks(with: interface, context: context)
        restorePower()

        if context.isCancelled {
            completion(.cancelled)
            return
        }
        switch scan {
        case .success(let networks):
            completion(Self.evaluate(rssiValues: networks.map { $0.rssiValue }, measurements: measurements))
        case .failure(let error):
            completion(.failed("Error al buscar redes: \(error.localizedDescription)", measurements))
        }
    }

    public func cancel() {
        restorePower()
    }

    static func evaluate(rssiValues: [Int], measurements: [DiagnosticMeasurement]) -> DiagnosticOutcome {
        var measurements = measurements
        measurements.append(DiagnosticMeasurement("Redes detectadas", "\(rssiValues.count)"))
        guard let strongest = rssiValues.max() else {
            return .warning("La tarjeta Wi-Fi responde, pero no ha encontrado ninguna red. Si hay redes cerca, puede haber un problema con las antenas.", measurements)
        }
        measurements.append(DiagnosticMeasurement("Señal más fuerte", "\(strongest) dBm"))

        if strongest < -80 {
            return .warning("Se detectan redes, pero la señal es muy débil. Puede haber un problema con las antenas.", measurements)
        }
        return .passed("La tarjeta Wi-Fi funciona y detecta redes.", measurements)
    }

    // MARK: - Private

    /// Retries while the scan comes back empty or fails.
    private func scanForNetworks(with interface: CWInterface, context: DiagnosticContext) -> Result<Set<CWNetwork>, Error> {
        var lastError: Error?
        for attempt in 1...scanAttempts {
            do {
                let networks = try interface.scanForNetworks(withName: nil)
                if !networks.isEmpty || attempt == scanAttempts {
                    return .success(networks)
                }
                lastError = nil
            } catch {
                lastError = error
            }
            if attempt < scanAttempts {
                // Pause before retrying; stop early if the run is cancelled.
                _ = Self.wait(upTo: delayBetweenScans, context: context, until: { context.isCancelled })
                if context.isCancelled { break }
            }
        }
        if let error = lastError {
            return .failure(error)
        }
        return .success([])
    }

    private func switchOffWhenFinished(_ interface: CWInterface) {
        lock.lock()
        interfaceToSwitchOff = interface
        lock.unlock()
    }

    /// Switches the radio off again if this test switched it on.
    private func restorePower() {
        lock.lock()
        let interface = interfaceToSwitchOff
        interfaceToSwitchOff = nil
        lock.unlock()
        try? interface?.setPower(false)
    }

    /// Polls `condition` until it is true, the time is up or the run is cancelled.
    private static func wait(upTo timeout: TimeInterval, context: DiagnosticContext, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            if context.isCancelled { return false }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return condition()
    }
}
