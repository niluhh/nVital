import CoreWLAN
import Foundation

/// Checks the Wi-Fi interface is present and powered, and scans for networks.
public final class WiFiTest: DiagnosticTest {
    public let identifier = "wifi"
    public let name = "Wi-Fi"
    public let summary = "Comprueba la tarjeta Wi-Fi y busca redes cercanas."
    public let category = DiagnosticCategory.connectivity

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

        guard interface.powerOn() else {
            completion(.warning("La interfaz Wi-Fi está apagada. Actívala y repite la prueba.", measurements))
            return
        }

        let connectedRSSI = interface.rssiValue()
        if connectedRSSI != 0 {
            measurements.append(DiagnosticMeasurement("Señal de la red actual", "\(connectedRSSI) dBm"))
            measurements.append(DiagnosticMeasurement("Velocidad de transmisión", "\(Int(interface.transmitRate())) Mb/s"))
        }

        let networks: Set<CWNetwork>
        do {
            networks = try interface.scanForNetworks(withName: nil)
        } catch {
            completion(.failed("Error al buscar redes: \(error.localizedDescription)", measurements))
            return
        }

        measurements.append(DiagnosticMeasurement("Redes detectadas", "\(networks.count)"))
        guard let strongest = networks.max(by: { $0.rssiValue < $1.rssiValue }) else {
            completion(.warning("La interfaz funciona pero no ha detectado ninguna red. Comprueba que haya redes cerca.", measurements))
            return
        }
        measurements.append(DiagnosticMeasurement("Señal más fuerte", "\(strongest.rssiValue) dBm"))

        if strongest.rssiValue < -80 {
            completion(.warning("Se detectan redes, pero la señal es muy débil. Puede haber un problema con las antenas.", measurements))
        } else {
            completion(.passed("La interfaz Wi-Fi funciona y detecta redes.", measurements))
        }
    }
}
