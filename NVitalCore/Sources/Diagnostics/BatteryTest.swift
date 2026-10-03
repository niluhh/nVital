import Foundation
import IOKit.ps

/// Reads battery health from the SMC (via IOKit) and the power source info.
public final class BatteryTest: DiagnosticTest {
    public let identifier = "battery"
    public let name = "Batería"
    public let summary = "Lee la capacidad, los ciclos de carga y el estado de la batería."
    public let category = DiagnosticCategory.power

    /// Cycle count Apple rates current Mac laptops for.
    static let ratedCycleCount = 1000

    public init() {}

    public func isApplicable(to machine: MachineInfo) -> Bool {
        return machine.isPortable
    }

    public func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        guard let reading = Self.currentReading() else {
            completion(.failed("No se ha detectado la batería."))
            return
        }
        completion(Self.evaluate(reading))
    }

    static func hasInstalledBattery() -> Bool {
        guard let properties = IORegistry.properties(ofServiceMatching: "AppleSmartBattery") else { return false }
        return properties["BatteryInstalled"] as? Bool ?? false
    }

    // MARK: - Reading

    struct Reading: Equatable {
        var cycleCount: Int?
        /// mAh.
        var designCapacity: Int?
        /// mAh.
        var fullChargeCapacity: Int?
        /// Percentage of charge right now.
        var chargePercent: Int?
        var isCharging: Bool?
        var permanentFailure: Bool
        /// macOS' own verdict, e.g. "Check Battery" or "Permanent Battery Failure".
        var healthCondition: String?
    }

    static func currentReading() -> Reading? {
        guard let smart = IORegistry.properties(ofServiceMatching: "AppleSmartBattery"),
              smart["BatteryInstalled"] as? Bool ?? false else {
            return nil
        }

        let design = smart["DesignCapacity"] as? Int
        // Apple Silicon reports MaxCapacity as a percentage; the raw value is in mAh.
        var fullCharge = (smart["AppleRawMaxCapacity"] as? Int) ?? (smart["NominalChargeCapacity"] as? Int)
        if fullCharge == nil, let max = smart["MaxCapacity"] as? Int, max > 100 {
            fullCharge = max
        }

        var reading = Reading(cycleCount: smart["CycleCount"] as? Int,
                              designCapacity: design,
                              fullChargeCapacity: fullCharge,
                              chargePercent: nil,
                              isCharging: smart["IsCharging"] as? Bool,
                              permanentFailure: (smart["PermanentFailureStatus"] as? Int ?? 0) != 0,
                              healthCondition: nil)

        if let description = internalBatteryDescription() {
            if let current = description["Current Capacity"] as? Int, let max = description["Max Capacity"] as? Int, max > 0 {
                reading.chargePercent = current * 100 / max
            }
            reading.healthCondition = description["BatteryHealthCondition"] as? String
        }
        return reading
    }

    private static func internalBatteryDescription() -> [String: Any]? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return nil
        }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if description["Type"] as? String == "InternalBattery" {
                return description
            }
        }
        return nil
    }

    // MARK: - Evaluation

    static func evaluate(_ reading: Reading) -> DiagnosticOutcome {
        var measurements: [DiagnosticMeasurement] = []
        var health: Double?

        if let design = reading.designCapacity, let full = reading.fullChargeCapacity, design > 0 {
            let percent = Double(full) / Double(design) * 100
            health = percent
            measurements.append(DiagnosticMeasurement("Salud", String(format: "%.0f %%", percent)))
            measurements.append(DiagnosticMeasurement("Capacidad máxima", "\(full) mAh"))
            measurements.append(DiagnosticMeasurement("Capacidad de diseño", "\(design) mAh"))
        }
        if let cycles = reading.cycleCount {
            measurements.append(DiagnosticMeasurement("Ciclos de carga", "\(cycles)"))
        }
        if let charge = reading.chargePercent {
            measurements.append(DiagnosticMeasurement("Carga actual", "\(charge) %"))
        }
        if let charging = reading.isCharging {
            measurements.append(DiagnosticMeasurement("Cargando", charging ? "Sí" : "No"))
        }
        if let condition = reading.healthCondition {
            measurements.append(DiagnosticMeasurement("Estado según macOS", condition))
        }

        let condition = reading.healthCondition?.lowercased() ?? ""
        if reading.permanentFailure || condition.contains("failure") {
            return .failed("La batería ha registrado un fallo permanente. Debe sustituirse.", measurements)
        }
        if let health = health, health < 60 {
            return .failed("La batería conserva menos del 60 % de su capacidad original. Debe sustituirse.", measurements)
        }
        if !condition.isEmpty {
            return .warning("macOS recomienda revisar la batería.", measurements)
        }
        if let health = health, health < 80 {
            return .warning("La batería conserva menos del 80 % de su capacidad original.", measurements)
        }
        if let cycles = reading.cycleCount, cycles >= ratedCycleCount {
            return .warning("La batería ha superado los \(ratedCycleCount) ciclos de carga para los que está diseñada.", measurements)
        }
        if health == nil {
            return .warning("No se ha podido calcular la salud de la batería.", measurements)
        }
        return .passed("La batería está en buen estado.", measurements)
    }
}
