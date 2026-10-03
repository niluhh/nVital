import AppKit

/// Main menu built in code. Actions travel through the responder chain to
/// `MainWindowController`.
enum MainMenu {
    static func make() -> NSMenu {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Acerca de nVital", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Ocultar nVital", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Salir de nVital", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, titled: "nVital", to: mainMenu)

        let fileMenu = NSMenu(title: "Archivo")
        fileMenu.addItem(withTitle: "Exportar informe…", action: #selector(MainWindowController.exportReport(_:)), keyEquivalent: "e")
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(fileMenu, titled: "Archivo", to: mainMenu)

        let editMenu = NSMenu(title: "Edición")
        editMenu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        add(editMenu, titled: "Edición", to: mainMenu)

        let testsMenu = NSMenu(title: "Pruebas")
        testsMenu.addItem(withTitle: "Ejecutar todas", action: #selector(MainWindowController.runAll(_:)), keyEquivalent: "r")
        testsMenu.addItem(withTitle: "Ejecutar seleccionadas", action: #selector(MainWindowController.runSelected(_:)), keyEquivalent: "R")
        testsMenu.addItem(withTitle: "Detener", action: #selector(MainWindowController.stop(_:)), keyEquivalent: ".")
        add(testsMenu, titled: "Pruebas", to: mainMenu)

        let windowMenu = NSMenu(title: "Ventana")
        windowMenu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(windowMenu, titled: "Ventana", to: mainMenu)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }

    private static func add(_ menu: NSMenu, titled title: String, to mainMenu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        mainMenu.addItem(item)
    }
}
