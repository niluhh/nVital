import Foundation

public enum DiagnosticStatus: String, Codable, CaseIterable {
    case passed
    case warning
    case failed
    case skipped
    case error

    public var displayName: String {
        switch self {
        case .passed: return "Correcto"
        case .warning: return "Aviso"
        case .failed: return "Fallo"
        case .skipped: return "Omitida"
        case .error: return "Error"
        }
    }

    /// Higher is worse. Used to compute the overall verdict of a report.
    var severity: Int {
        switch self {
        case .skipped: return 0
        case .passed: return 1
        case .warning: return 2
        case .error: return 3
        case .failed: return 4
        }
    }
}

/// A labelled value shown in the report (e.g. "Ciclos de carga: 312").
public struct DiagnosticMeasurement: Codable, Equatable {
    public let label: String
    public let value: String

    public init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}

/// What a test returns. The runner turns it into a `DiagnosticResult`.
public struct DiagnosticOutcome: Equatable {
    public var status: DiagnosticStatus
    public var message: String
    public var measurements: [DiagnosticMeasurement]

    public init(status: DiagnosticStatus, message: String, measurements: [DiagnosticMeasurement] = []) {
        self.status = status
        self.message = message
        self.measurements = measurements
    }

    public static func passed(_ message: String, _ measurements: [DiagnosticMeasurement] = []) -> DiagnosticOutcome {
        return DiagnosticOutcome(status: .passed, message: message, measurements: measurements)
    }

    public static func warning(_ message: String, _ measurements: [DiagnosticMeasurement] = []) -> DiagnosticOutcome {
        return DiagnosticOutcome(status: .warning, message: message, measurements: measurements)
    }

    public static func failed(_ message: String, _ measurements: [DiagnosticMeasurement] = []) -> DiagnosticOutcome {
        return DiagnosticOutcome(status: .failed, message: message, measurements: measurements)
    }

    public static func skipped(_ message: String, _ measurements: [DiagnosticMeasurement] = []) -> DiagnosticOutcome {
        return DiagnosticOutcome(status: .skipped, message: message, measurements: measurements)
    }

    public static func error(_ message: String, _ measurements: [DiagnosticMeasurement] = []) -> DiagnosticOutcome {
        return DiagnosticOutcome(status: .error, message: message, measurements: measurements)
    }

    static let skippedByUser = DiagnosticOutcome.skipped("Omitida por el usuario.")
    static let cancelled = DiagnosticOutcome.skipped("Cancelada.")
}

/// The recorded result of running one test.
public struct DiagnosticResult: Codable, Equatable {
    public let testIdentifier: String
    public let testName: String
    public let category: DiagnosticCategory
    public let status: DiagnosticStatus
    public let message: String
    public let measurements: [DiagnosticMeasurement]
    public let startedAt: Date
    public let finishedAt: Date

    public var duration: TimeInterval {
        return finishedAt.timeIntervalSince(startedAt)
    }

    public init(test: DiagnosticTest, outcome: DiagnosticOutcome, startedAt: Date, finishedAt: Date) {
        self.testIdentifier = test.identifier
        self.testName = test.name
        self.category = test.category
        self.status = outcome.status
        self.message = outcome.message
        self.measurements = outcome.measurements
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }
}
