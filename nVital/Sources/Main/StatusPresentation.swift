import AppKit
import NVitalCore

enum StatusPresentation {
    static func color(for status: DiagnosticStatus) -> NSColor {
        switch status {
        case .passed: return .systemGreen
        case .warning: return .systemOrange
        case .failed: return .systemRed
        case .error: return .systemPurple
        case .skipped: return .secondaryLabelColor
        }
    }
}
