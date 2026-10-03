@testable import NVitalCore
import XCTest

final class StubTest: DiagnosticTest {
    let identifier: String
    var name: String { return identifier }
    let summary = "Stub"
    let category = DiagnosticCategory.connectivity
    let outcome: DiagnosticOutcome
    var delay: TimeInterval = 0
    var applicable = true
    private(set) var runCount = 0
    private(set) var cancelCount = 0

    init(identifier: String, outcome: DiagnosticOutcome = .passed("ok")) {
        self.identifier = identifier
        self.outcome = outcome
    }

    func isApplicable(to machine: MachineInfo) -> Bool {
        return applicable
    }

    func run(in context: DiagnosticContext, completion: @escaping (DiagnosticOutcome) -> Void) {
        runCount += 1
        let outcome = self.outcome
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            completion(outcome)
        }
    }

    func cancel() {
        cancelCount += 1
    }
}

private final class RecordingDelegate: DiagnosticRunnerDelegate {
    var started: [String] = []
    var finished: [DiagnosticResult] = []
    var onFinish: ((Bool) -> Void)?

    func runner(_ runner: DiagnosticRunner, didStart test: DiagnosticTest) {
        started.append(test.identifier)
    }

    func runner(_ runner: DiagnosticRunner, didFinish test: DiagnosticTest, with result: DiagnosticResult) {
        finished.append(result)
    }

    func runnerDidFinish(_ runner: DiagnosticRunner, cancelled: Bool) {
        onFinish?(cancelled)
    }
}

final class RunnerTests: XCTestCase {
    func testRunsTestsInSuiteOrderAndBuildsReport() {
        let a = StubTest(identifier: "a")
        let b = StubTest(identifier: "b", outcome: .failed("broken"))
        let c = StubTest(identifier: "c")
        c.applicable = false
        let runner = DiagnosticRunner(tests: [a, b, c], machine: ReportTests.machine)
        let delegate = RecordingDelegate()
        runner.delegate = delegate

        let done = expectation(description: "finished")
        delegate.onFinish = { cancelled in
            XCTAssertFalse(cancelled)
            done.fulfill()
        }
        runner.run([c, b, a])
        wait(for: [done], timeout: 5)

        XCTAssertEqual(delegate.started, ["a", "b", "c"])
        XCTAssertEqual(delegate.finished.map { $0.status }, [.passed, .failed, .skipped])
        XCTAssertEqual(c.runCount, 0)
        XCTAssertFalse(runner.isRunning)

        let report = runner.makeReport()
        XCTAssertEqual(report.results.map { $0.testIdentifier }, ["a", "b", "c"])
        XCTAssertEqual(report.overallStatus, .failed)
    }

    func testTimeoutRecordsError() {
        let slow = StubTest(identifier: "slow")
        slow.delay = 3
        let runner = DiagnosticRunner(tests: [slow], machine: ReportTests.machine)
        runner.timeout = 0.2
        let delegate = RecordingDelegate()
        runner.delegate = delegate

        let done = expectation(description: "finished")
        delegate.onFinish = { _ in done.fulfill() }
        runner.run()
        wait(for: [done], timeout: 5)

        XCTAssertEqual(delegate.finished.map { $0.status }, [.error])
        XCTAssertEqual(slow.cancelCount, 1)
    }

    func testCancelStopsRemainingTests() {
        let first = StubTest(identifier: "first")
        first.delay = 2
        let second = StubTest(identifier: "second")
        let runner = DiagnosticRunner(tests: [first, second], machine: ReportTests.machine)
        let delegate = RecordingDelegate()
        runner.delegate = delegate

        let done = expectation(description: "finished")
        delegate.onFinish = { cancelled in
            XCTAssertTrue(cancelled)
            done.fulfill()
        }
        runner.run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { runner.cancel() }
        wait(for: [done], timeout: 5)

        XCTAssertEqual(delegate.started, ["first"])
        XCTAssertEqual(delegate.finished.map { $0.status }, [.skipped])
        XCTAssertEqual(first.cancelCount, 1)
        XCTAssertEqual(second.runCount, 0)
    }

    func testRequestWithoutHandlerIsUnavailable() {
        let context = DiagnosticContext(machine: ReportTests.machine, interactionHandler: nil)
        let answered = expectation(description: "answered")
        context.request(.notice(NoticeRequest(title: "t", message: "m"))) { response in
            if case .unavailable = response { answered.fulfill() }
        }
        wait(for: [answered], timeout: 2)
    }
}
