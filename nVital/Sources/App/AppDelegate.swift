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
