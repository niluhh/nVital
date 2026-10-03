import Foundation

/// Everything a test may need while running. One context is created per test run.
public final class DiagnosticContext {
    public let machine: MachineInfo

    private weak var interactionHandler: DiagnosticInteractionHandler?
    private let lock = NSLock()
    private var cancelled = false

    public init(machine: MachineInfo, interactionHandler: DiagnosticInteractionHandler?) {
        self.machine = machine
        self.interactionHandler = interactionHandler
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    /// Asks the host app to show something to the user.
    ///
    /// `completion` is called on the main queue. If there is no handler it
    /// receives `.unavailable`; if the run was cancelled, `.cancelled`.
    public func request(_ request: InteractionRequest, completion: @escaping (InteractionResponse) -> Void) {
        DispatchQueue.main.async {
            guard !self.isCancelled else {
                completion(.cancelled)
                return
            }
            guard let handler = self.interactionHandler else {
                completion(.unavailable)
                return
            }
            var answered = false
            handler.handle(request) { response in
                DispatchQueue.main.async {
                    guard !answered else { return }
                    answered = true
                    completion(self.isCancelled ? .cancelled : response)
                }
            }
        }
    }
}
