import AppKit
import NVitalCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // If nVital quit unexpectedly during the keyboard test, put the
        // function keys back the way the user had them.
        FunctionKeyMode.endTemporaryOverride()

        NSApp.mainMenu = MainMenu.make()
        let controller = MainWindowController(runner: DiagnosticRunner())
        controller.showWindow(nil)
        mainWindowController = controller
        NSApp.activate(ignoringOtherApps: true)
        requestPermissions()
    }

    /// Asks for every permission up front, so no prompt interrupts the tests.
    private func requestPermissions() {
        var permissions: [Permission] = [.camera, .microphone, .bluetooth]
        // macOS does not remember a refusal of Accessibility, so asking at
        // every launch would repeat its prompt: ask the first time on each
        // Mac only. It stays available in nVital › Permisos… and the keyboard test.
        let accessibilityAskedKey = "AccessibilityRequestedAtLaunch"
        if SystemPermissions.status(of: .accessibility) != .granted,
           !UserDefaults.standard.bool(forKey: accessibilityAskedKey) {
            UserDefaults.standard.set(true, forKey: accessibilityAskedKey)
            permissions.append(.accessibility)
        }
        SystemPermissions.requestAll(permissions) { _ in }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Cancelling lets the running test release what it changed or opened.
        mainWindowController?.stop(nil)
        FunctionKeyMode.endTemporaryOverride()
    }

    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
