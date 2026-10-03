import Foundation

public enum ReportFormat: String, CaseIterable {
    case html
    case text
    case json

    public var fileExtension: String {
        switch self {
        case .html: return "html"
        case .text: return "txt"
        case .json: return "json"
        }
    }

    public var displayName: String {
        switch self {
        case .html: return "Página web (HTML)"
        case .text: return "Texto"
        case .json: return "JSON"
        }
    }
}

/// Turns a `DiagnosticReport` into a shareable document.
public enum ReportRenderer {
    public static func render(_ report: DiagnosticReport, as format: ReportFormat) throws -> Data {
        switch format {
        case .html: return Data(html(report).utf8)
        case .text: return Data(text(report).utf8)
        case .json: return try json(report)
        }
    }

    /// Suggested file name, e.g. "nVital-C02XXXX-2026-10-03-1530.html".
    public static func suggestedFileName(for report: DiagnosticReport, format: ReportFormat) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let serial = report.machine.serialNumber.filter { $0.isLetter || $0.isNumber }
        return "nVital-\(serial)-\(formatter.string(from: report.generatedAt)).\(format.fileExtension)"
    }

    // MARK: - JSON

    public static func json(_ report: DiagnosticReport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    public static func decode(json data: Data) throws -> DiagnosticReport {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DiagnosticReport.self, from: data)
    }

    // MARK: - Text

    public static func text(_ report: DiagnosticReport) -> String {
        var lines: [String] = []
        lines.append("INFORME DE DIAGNÓSTICO nVital")
        lines.append(String(repeating: "=", count: 40))
        lines.append("Fecha: \(formatDate(report.generatedAt))")
        lines.append("Resultado: \(report.verdict.uppercased())")
        lines.append("")
        for (label, value) in machineRows(report) {
            lines.append("\(label): \(value)")
        }
        lines.append("")

        for result in report.results {
            lines.append("[\(result.status.displayName.uppercased())] \(result.testName)")
            lines.append("    \(result.message)")
            for measurement in result.measurements {
                lines.append("    · \(measurement.label): \(measurement.value)")
            }
            lines.append("")
        }
        lines.append(summaryLine(report))
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - HTML

    public static func html(_ report: DiagnosticReport) -> String {
        let machine = machineRows(report)
            .map { "<tr><th>\(escape($0.0))</th><td>\(escape($0.1))</td></tr>" }
            .joined(separator: "\n")

        let results = report.results.map { result -> String in
            let measurements = result.measurements
                .map { "<li><span>\(escape($0.label))</span> \(escape($0.value))</li>" }
                .joined()
            return """
            <section class="result \(result.status.rawValue)">
              <header><span class="badge">\(escape(result.status.displayName))</span><h2>\(escape(result.testName))</h2><span class="category">\(escape(result.category.displayName))</span></header>
              <p>\(escape(result.message))</p>
              \(measurements.isEmpty ? "" : "<ul>\(measurements)</ul>")
            </section>
            """
        }.joined(separator: "\n")

        return """
        <!doctype html>
        <html lang="es">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Informe nVital · \(escape(report.machine.serialNumber))</title>
        <style>
          :root { --bg: #f5f5f7; --card: #fff; --text: #1d1d1f; --muted: #6e6e73; --line: #d2d2d7;
                  --passed: #1e8e3e; --warning: #b26a00; --failed: #d70015; --error: #8e44ad; --skipped: #6e6e73; }
          @media (prefers-color-scheme: dark) {
            :root { --bg: #1c1c1e; --card: #2c2c2e; --text: #f5f5f7; --muted: #a1a1a6; --line: #3a3a3c; }
          }
          * { box-sizing: border-box; }
          body { margin: 0; padding: 32px 16px; background: var(--bg); color: var(--text);
                 font: 15px/1.45 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif; }
          main { max-width: 760px; margin: 0 auto; }
          h1 { margin: 0 0 4px; font-size: 26px; }
          .meta { color: var(--muted); margin: 0 0 20px; }
          .verdict { padding: 16px 20px; border-radius: 12px; color: #fff; font-size: 18px; font-weight: 600; margin-bottom: 20px; }
          .verdict.passed { background: var(--passed); } .verdict.warning { background: var(--warning); }
          .verdict.failed { background: var(--failed); } .verdict.error { background: var(--error); }
          .verdict.skipped { background: var(--skipped); }
          .verdict small { display: block; font-weight: 400; font-size: 14px; opacity: .9; }
          table { width: 100%; border-collapse: collapse; background: var(--card); border-radius: 12px; overflow: hidden; margin-bottom: 20px; }
          th, td { text-align: left; padding: 8px 14px; border-bottom: 1px solid var(--line); }
          th { color: var(--muted); font-weight: 500; width: 40%; }
          tr:last-child th, tr:last-child td { border-bottom: 0; }
          .result { background: var(--card); border-radius: 12px; padding: 14px 18px; margin-bottom: 12px; border-left: 6px solid var(--skipped); }
          .result.passed { border-color: var(--passed); } .result.warning { border-color: var(--warning); }
          .result.failed { border-color: var(--failed); } .result.error { border-color: var(--error); }
          .result header { display: flex; align-items: baseline; gap: 10px; flex-wrap: wrap; }
          .result h2 { margin: 0; font-size: 17px; }
          .category { color: var(--muted); font-size: 13px; margin-left: auto; }
          .badge { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: .03em; }
          .passed .badge { color: var(--passed); } .warning .badge { color: var(--warning); }
          .failed .badge { color: var(--failed); } .error .badge { color: var(--error); } .skipped .badge { color: var(--skipped); }
          .result p { margin: 6px 0; }
          .result ul { margin: 6px 0 0; padding: 0; list-style: none; color: var(--muted); font-size: 14px; }
          .result li span { color: var(--text); }
          .result li span::after { content: ":"; }
          footer { color: var(--muted); font-size: 13px; text-align: center; margin-top: 24px; }
        </style>
        </head>
        <body>
        <main>
          <h1>Informe de diagnóstico</h1>
          <p class="meta">\(escape(formatDate(report.generatedAt)))</p>
          <div class="verdict \(report.overallStatus.rawValue)">\(escape(report.verdict))<small>\(escape(summaryLine(report)))</small></div>
          <table>
        \(machine)
          </table>
        \(results)
          <footer>Generado por nVital\(report.appVersion.map { " " + escape($0) } ?? "")</footer>
        </main>
        </body>
        </html>
        """
    }

    // MARK: - Helpers

    static func machineRows(_ report: DiagnosticReport) -> [(String, String)] {
        let machine = report.machine
        let memory = ByteCountFormatter.string(fromByteCount: Int64(machine.memoryBytes), countStyle: .memory)
        return [
            ("Modelo", machine.modelIdentifier),
            ("Número de serie", machine.serialNumber),
            ("Procesador", "\(machine.processor) (\(machine.architecture))"),
            ("Memoria", memory),
            ("macOS", "\(machine.systemVersion) (\(machine.systemBuild))"),
        ]
    }

    static func summaryLine(_ report: DiagnosticReport) -> String {
        return DiagnosticStatus.allCases
            .map { (status: $0, count: report.count(of: $0)) }
            .filter { $0.count > 0 }
            .map { "\($0.status.displayName): \($0.count)" }
            .joined(separator: " · ")
    }

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func escape(_ string: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(string.count)
        for character in string {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
