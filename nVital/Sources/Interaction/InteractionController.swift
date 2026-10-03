import AppKit
import NVitalCore

/// Shows the UI that interactive tests ask for, as sheets on the main window.
final class InteractionController: DiagnosticInteractionHandler {
    weak var window: NSWindow?

    private var pendingCompletion: ((InteractionResponse) -> Void)?
    private var activeSheet: SheetController?
    private var activeAlert: NSAlert?
    private var displayController: DisplayPatternController?

    func handle(_ request: InteractionRequest, completion: @escaping (InteractionResponse) -> Void) {
        guard let window = window else {
            completion(.unavailable)
            return
        }
        pendingCompletion = completion

        switch request {
        case .confirmation(let confirmation):
            showAlert(title: confirmation.title, message: confirmation.message,
                      buttons: [confirmation.confirmTitle, confirmation.denyTitle], in: window) { index in
                index == 0 ? .confirmed(true) : .confirmed(false)
            }
        case .notice(let notice):
            showAlert(title: notice.title, message: notice.message, buttons: [notice.buttonTitle], in: window) { _ in
                .acknowledged
            }
        case .keyboard(let keyboard):
            present(KeyboardSheetController(request: keyboard), in: window)
        case .trackpad(let trackpad):
            present(TrackpadSheetController(request: trackpad), in: window)
        case .cameraPreview(let camera):
            present(CameraPreviewSheetController(request: camera), in: window)
        case .displayPatterns(let patterns):
            showPatterns(patterns, in: window)
        }
    }

    func cancelPendingInteraction() {
        finish(.cancelled)
    }

    // MARK: - Presentation

    /// Alert with the given buttons plus "Omitir prueba". `map` turns the
    /// index of the pressed button into a response.
    private func showAlert(title: String, message: String, buttons: [String], in window: NSWindow,
                           map: @escaping (Int) -> InteractionResponse) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for title in buttons {
            alert.addButton(withTitle: title)
        }
        alert.addButton(withTitle: "Omitir prueba")
        activeAlert = alert

        alert.beginSheetModal(for: window) { [weak self] response in
            // The alert dismissed itself; don't end its sheet again in `finish`.
            self?.activeAlert = nil
            let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
            self?.finish(index < buttons.count ? map(index) : .skipped)
        }
    }

    private func present(_ sheet: SheetController, in window: NSWindow) {
        activeSheet = sheet
        sheet.onFinish = { [weak self] response in
            self?.finish(response)
        }
        if let sheetWindow = sheet.window {
            window.beginSheet(sheetWindow, completionHandler: nil)
        }
    }

    private func showPatterns(_ request: DisplayPatternRequest, in window: NSWindow) {
        let notice = NSAlert()
        notice.messageText = "Prueba de pantalla"
        notice.informativeText = request.instructions
        notice.addButton(withTitle: "Empezar")
        notice.addButton(withTitle: "Omitir prueba")
        activeAlert = notice

        notice.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, self.pendingCompletion != nil else { return }
            self.activeAlert = nil
            guard response == .alertFirstButtonReturn else {
                self.finish(.skipped)
                return
            }
            let controller = DisplayPatternController(request: request)
            self.displayController = controller
            controller.show { [weak self] completed in
                self?.finish(completed ? .acknowledged : .skipped)
            }
        }
    }

    // MARK: - Completion

    private func finish(_ response: InteractionResponse) {
        guard let completion = pendingCompletion else { return }
        pendingCompletion = nil

        if let alert = activeAlert {
            activeAlert = nil
            window?.endSheet(alert.window)
        }
        if let sheet = activeSheet {
            activeSheet = nil
            sheet.tearDown()
            if let sheetWindow = sheet.window {
                window?.endSheet(sheetWindow)
                sheetWindow.orderOut(nil)
            }
        }
        if let display = displayController {
            displayController = nil
            display.close()
        }
        completion(response)
    }
}
