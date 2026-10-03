@testable import NVitalCore
import XCTest

final class ReportTests: XCTestCase {
    static let machine = MachineInfo(modelIdentifier: "MacBookPro16,1", serialNumber: "C02TEST<1>",
                                     architecture: "Intel", processor: "Intel Core i7", memoryBytes: 16 << 30,
                                     systemVersion: "10.15.7", systemBuild: "19H15", isPortable: true)

    private func result(_ id: String, _ status: DiagnosticStatus, message: String = "ok") -> DiagnosticResult {
        let test = StubTest(identifier: id, outcome: DiagnosticOutcome(status: status, message: message))
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return DiagnosticResult(test: test, outcome: test.outcome, startedAt: date, finishedAt: date.addingTimeInterval(1))
    }

    func testOverallStatusIsWorstNonSkipped() {
        XCTAssertEqual(DiagnosticReport(machine: Self.machine, results: []).overallStatus, .skipped)
        XCTAssertEqual(DiagnosticReport(machine: Self.machine, results: [result("a", .passed), result("b", .skipped)]).overallStatus, .passed)
        XCTAssertEqual(DiagnosticReport(machine: Self.machine, results: [result("a", .passed), result("b", .warning)]).overallStatus, .warning)
        XCTAssertEqual(DiagnosticReport(machine: Self.machine, results: [result("a", .failed), result("b", .error)]).overallStatus, .failed)
    }

    func testJSONRoundTrip() throws {
        let report = DiagnosticReport(machine: Self.machine, results: [result("a", .passed), result("b", .failed)],
                                      appVersion: "1.0", generatedAt: Date(timeIntervalSince1970: 1_800_000_000))
        let decoded = try ReportRenderer.decode(json: ReportRenderer.json(report))
        XCTAssertEqual(decoded, report)
    }

    func testHTMLEscapesContent() {
        let report = DiagnosticReport(machine: Self.machine, results: [result("a", .failed, message: "<script>alert(1)</script>")])
        let html = ReportRenderer.html(report)
        XCTAssertFalse(html.contains("<script>"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
        XCTAssertTrue(html.contains("C02TEST&lt;1&gt;"))
    }

    func testTextContainsEveryResult() {
        let report = DiagnosticReport(machine: Self.machine, results: [result("a", .passed), result("b", .warning)])
        let text = ReportRenderer.text(report)
        XCTAssertTrue(text.contains("[CORRECTO] a"))
        XCTAssertTrue(text.contains("[AVISO] b"))
    }

    func testSuggestedFileNameIsSafe() {
        let report = DiagnosticReport(machine: Self.machine, results: [])
        let name = ReportRenderer.suggestedFileName(for: report, format: .html)
        XCTAssertTrue(name.hasPrefix("nVital-C02TEST1-"))
        XCTAssertTrue(name.hasSuffix(".html"))
    }
}
