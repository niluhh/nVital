import Foundation

public protocol DiagnosticRunnerDelegate: AnyObject {
    func runner(_ runner: DiagnosticRunner, didStart test: DiagnosticTest)
    func runner(_ runner: DiagnosticRunner, didFinish test: DiagnosticTest, with result: DiagnosticResult)
    /// Called when every requested test has finished or the run was cancelled.
    func runnerDidFinish(_ runner: DiagnosticRunner, cancelled: Bool)
}

/// Runs diagnostics one after another and keeps the latest result of each.
///
/// Must be used from the main queue; delegate callbacks are delivered there too.
public final class DiagnosticRunner {
    public let tests: [DiagnosticTest]
    public let machine: MachineInfo
    public weak var delegate: DiagnosticRunnerDelegate?
    public weak var interactionHandler: DiagnosticInteractionHandler?

    /// Maximum duration of a test that does not need the user.
    public var timeout: TimeInterval = 120

    public private(set) var isRunning = false
    public private(set) var currentTest: DiagnosticTest?
    /// Latest result per test identifier.
    public private(set) var results: [String: DiagnosticResult] = [:]

    private var queue: [DiagnosticTest] = []
    private var currentContext: DiagnosticContext?
    private var currentStart = Date()
    private var runToken = 0
    private let workQueue = DispatchQueue(label: "com.nil.nvital.core.runner", qos: .userInitiated, attributes: .concurrent)

    public init(tests: [DiagnosticTest] = DiagnosticSuite.standardTests(), machine: MachineInfo = .current()) {
        self.tests = tests
        self.machine = machine
    }

    /// Runs `selection` (all tests if `nil`) in suite order.
    public func run(_ selection: [DiagnosticTest]? = nil) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !isRunning else { return }
        let selected = selection ?? tests
        queue = tests.filter { test in selected.contains { $0 === test } }
        isRunning = true
        runNext()
    }

    public func cancel() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard isRunning else { return }
        queue.removeAll()
        if let test = currentTest {
            currentContext?.cancel()
            interactionHandler?.cancelPendingInteraction()
            test.cancel()
            finish(test, with: .cancelled, token: runToken)
        }
        isRunning = false
        delegate?.runnerDidFinish(self, cancelled: true)
    }

    public func result(for test: DiagnosticTest) -> DiagnosticResult? {
        return results[test.identifier]
    }

    public func makeReport(appVersion: String? = nil) -> DiagnosticReport {
        return DiagnosticReport(machine: machine,
                                results: tests.compactMap { results[$0.identifier] },
                                appVersion: appVersion)
    }

    // MARK: - Private

    private func runNext() {
        guard isRunning else { return }
        guard !queue.isEmpty else {
            isRunning = false
            currentTest = nil
            delegate?.runnerDidFinish(self, cancelled: false)
            return
        }

        let test = queue.removeFirst()
        runToken += 1
        let token = runToken
        currentTest = test
        currentStart = Date()
        delegate?.runner(self, didStart: test)

        guard test.isApplicable(to: machine) else {
            finish(test, with: .skipped("No aplicable a este equipo."), token: token)
            return
        }

        let context = DiagnosticContext(machine: machine, interactionHandler: interactionHandler)
        currentContext = context

        if !test.requiresInteraction {
            let timeout = self.timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self, self.runToken == token, self.currentTest === test else { return }
                context.cancel()
                test.cancel()
                self.finish(test, with: .error("La prueba no ha terminado en \(Int(timeout)) segundos."), token: token)
            }
        }

        workQueue.async {
            test.run(in: context) { [weak self] outcome in
                DispatchQueue.main.async {
                    self?.finish(test, with: outcome, token: token)
                }
            }
        }
    }

    private func finish(_ test: DiagnosticTest, with outcome: DiagnosticOutcome, token: Int) {
        // Ignore late completions from a test that already timed out or was cancelled.
        guard token == runToken, currentTest === test else { return }
        let result = DiagnosticResult(test: test, outcome: outcome, startedAt: currentStart, finishedAt: Date())
        results[test.identifier] = result
        currentTest = nil
        currentContext = nil
        delegate?.runner(self, didFinish: test, with: result)
        // Start the next test on a fresh main-queue turn. A run started
        // meanwhile bumps `runToken`, which makes this call a no-op.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.runToken == token, self.currentTest == nil else { return }
            self.runNext()
        }
    }
}
