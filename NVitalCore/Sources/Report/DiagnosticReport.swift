import Foundation

/// Result of a diagnostic session: machine identification plus one result per test run.
public struct DiagnosticReport: Codable, Equatable {
    public let generatedAt: Date
    public let appVersion: String?
    public let machine: MachineInfo
    public let results: [DiagnosticResult]

    public init(machine: MachineInfo, results: [DiagnosticResult], appVersion: String? = nil, generatedAt: Date = Date()) {
        self.machine = machine
        self.results = results
        self.appVersion = appVersion
        self.generatedAt = generatedAt
    }

    /// Worst status among the results, ignoring skipped tests.
    /// `.skipped` when nothing was actually run.
    public var overallStatus: DiagnosticStatus {
        let ran = results.map { $0.status }.filter { $0 != .skipped }
        return ran.max { $0.severity < $1.severity } ?? .skipped
    }

    public func count(of status: DiagnosticStatus) -> Int {
        return results.filter { $0.status == status }.count
    }

    public var verdict: String {
        switch overallStatus {
        case .passed: return "Todas las pruebas son correctas"
        case .warning: return "Correcto con avisos"
        case .failed: return "Se han detectado fallos"
        case .error: return "Algunas pruebas no se han podido completar"
        case .skipped: return "No se ha ejecutado ninguna prueba"
        }
    }
}
