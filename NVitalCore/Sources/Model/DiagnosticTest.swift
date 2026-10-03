import Foundation

/// A single hardware diagnostic.
///
/// Conforming types live in NVitalCore (or in any other module of the suite)
/// and must not depend on AppKit. Anything that needs the user — pressing keys,
/// looking at the screen, listening to a tone — is requested through
/// `DiagnosticContext.request(_:completion:)`, which the host app fulfils.
public protocol DiagnosticTest: AnyObject {
    /// Stable identifier used in reports and to persist results (e.g. "wifi").
    var identifier: String { get }

    /// Short human-readable name (e.g. "Wi-Fi").
    var name: String { get }

    /// One sentence describing what the test checks.
    var summary: String { get }

    var category: DiagnosticCategory { get }

    /// `true` when the test cannot finish without the user's help.
    var requiresInteraction: Bool { get }

    /// Whether the test makes sense on this machine. Tests that return `false`
    /// are recorded as skipped without being run.
    func isApplicable(to machine: MachineInfo) -> Bool

    /// Runs the test. Called on a background queue.
    ///
    /// `completion` must be called exactly once, from any queue. Long-running
    /// tests should check `context.isCancelled` periodically.
    func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void)

    /// Called when the run is cancelled. Release hardware (camera, audio
    /// engine…) here. The runner records the result itself, so calling
    /// `completion` afterwards is allowed but ignored.
    func cancel()
}

public extension DiagnosticTest {
    var requiresInteraction: Bool { return false }

    func isApplicable(to machine: MachineInfo) -> Bool { return true }

    func cancel() {}
}

public enum DiagnosticCategory: String, Codable, CaseIterable {
    case connectivity
    case power
    case storage
    case media
    case input
    case display

    public var displayName: String {
        switch self {
        case .connectivity: return "Conectividad"
        case .power: return "Energía"
        case .storage: return "Almacenamiento"
        case .media: return "Audio y vídeo"
        case .input: return "Entrada"
        case .display: return "Pantalla"
        }
    }
}
