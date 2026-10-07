import Foundation
import IOBluetooth

/// Checks the Bluetooth controller is present and powered on.
public final class BluetoothTest: DiagnosticTest {
    public let identifier = "bluetooth"
    public let name = "Bluetooth"
    public let summary = "Comprueba que el controlador Bluetooth está presente y encendido."
    public let category = DiagnosticCategory.connectivity

    public init() {}

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        // Calls back on the main queue: IOBluetooth is not documented as thread-safe.
        SystemPermissions.request(.bluetooth) { status in
            guard status != .denied else {
                completion(.error(Permission.bluetooth.deniedMessage))
                return
            }
            completion(Self.inspectController())
        }
    }

    private static func inspectController() -> DiagnosticOutcome {
        guard let controller = IOBluetoothHostController.default(),
              let address = controller.addressAsString(), !address.isEmpty else {
            return .failed("No se ha encontrado el controlador Bluetooth.")
        }

        let isOn = controller.powerState == kBluetoothHCIPowerStateON
        let pairedCount = IOBluetoothDevice.pairedDevices()?.count ?? 0
        let measurements = [
            DiagnosticMeasurement("Dirección", address),
            DiagnosticMeasurement("Estado", isOn ? "Encendido" : "Apagado"),
            DiagnosticMeasurement("Dispositivos enlazados", "\(pairedCount)"),
        ]

        if isOn {
            return .passed("El controlador Bluetooth está presente y encendido.", measurements)
        }
        return .warning("El controlador Bluetooth está presente pero apagado. Actívalo y repite la prueba.", measurements)
    }
}
