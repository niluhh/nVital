import AppKit
import NVitalCore

/// Save panel with a format picker. Defaults to the folder that contains the
/// app, so reports end up on the same USB drive nVital is run from.
final class ReportExporter: NSObject {
    private let report: DiagnosticReport
    private let panel = NSSavePanel()
    private let formatPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private static var current: ReportExporter?

    private init(report: DiagnosticReport) {
        self.report = report
        super.init()
    }

    static func export(_ report: DiagnosticReport, from window: NSWindow) {
        let exporter = ReportExporter(report: report)
        current = exporter
        exporter.begin(from: window)
    }

    private var selectedFormat: ReportFormat {
        return ReportFormat.allCases[max(formatPopUp.indexOfSelectedItem, 0)]
    }

    private func begin(from window: NSWindow) {
        formatPopUp.addItems(withTitles: ReportFormat.allCases.map { $0.displayName })
        formatPopUp.target = self
        formatPopUp.action = #selector(formatChanged(_:))

        let label = NSTextField(labelWithString: "Formato:")
        let accessory = NSStackView(views: [label, formatPopUp])
        accessory.orientation = .horizontal
        accessory.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        panel.title = "Exportar informe"
        panel.accessoryView = accessory
        panel.canCreateDirectories = true
        panel.directoryURL = Bundle.main.bundleURL.deletingLastPathComponent()
        applyFormat()

        panel.beginSheetModal(for: window) { response in
            defer { ReportExporter.current = nil }
            guard response == .OK, let url = self.panel.url else { return }
            do {
                try ReportRenderer.render(self.report, as: self.selectedFormat).write(to: url, options: .atomic)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                NSAlert(error: error).beginSheetModal(for: window, completionHandler: nil)
            }
        }
    }

    @objc private func formatChanged(_ sender: Any?) {
        applyFormat()
    }

    private func applyFormat() {
        let format = selectedFormat
        panel.allowedFileTypes = [format.fileExtension]
        panel.nameFieldStringValue = ReportRenderer.suggestedFileName(for: report, format: format)
    }
}
