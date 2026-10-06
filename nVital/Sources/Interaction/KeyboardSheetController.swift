import AppKit
import ApplicationServices
import Carbon.HIToolbox
import NVitalCore

/// Draws the keyboard and lights up each key as it is pressed.
///
/// While the sheet is open, macOS shortcuts (F11 Show Desktop, ⌘Tab,
/// Spotlight…) are disabled so every key press reaches the view. macOS only
/// lets apps with Accessibility permission do that.
final class KeyboardSheetController: SheetController {
    private let keyboardView: KeyboardView
    private let shortcutsLabel: NSTextField
    private let permissionButton: NSButton
    private var hotKeyModeToken: UnsafeMutableRawPointer?
    private var trustTimer: Timer?

    init(request: KeyboardCaptureRequest) {
        let keyboardView = KeyboardView(keys: request.keys)
        keyboardView.translatesAutoresizingMaskIntoConstraints = false
        keyboardView.heightAnchor.constraint(equalToConstant: 300).isActive = true
        self.keyboardView = keyboardView

        let shortcutsLabel = NSTextField(labelWithString: "")
        shortcutsLabel.font = NSFont.systemFont(ofSize: 11)
        shortcutsLabel.lineBreakMode = .byTruncatingTail
        shortcutsLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let permissionButton = NSButton(title: "Dar permiso…", target: nil, action: nil)
        permissionButton.controlSize = .small
        self.shortcutsLabel = shortcutsLabel
        self.permissionButton = permissionButton

        let shortcutsRow = NSStackView(views: [shortcutsLabel, permissionButton])
        shortcutsRow.orientation = .horizontal
        let content = NSStackView(views: [keyboardView, shortcutsRow])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 8
        keyboardView.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true

        // No key equivalent: Return must reach the keyboard view, not the button.
        let doneButton = NSButton(title: "Terminar", target: nil, action: nil)
        super.init(title: "Prueba de teclado", instructions: request.instructions,
                   content: content, size: NSSize(width: 820, height: 500), buttons: [doneButton])
        doneButton.target = self
        doneButton.action = #selector(done(_:))
        permissionButton.target = self
        permissionButton.action = #selector(requestAccessibility(_:))
        window?.initialFirstResponder = keyboardView
        updateShortcutBlocking()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func tearDown() {
        trustTimer?.invalidate()
        trustTimer = nil
        if let token = hotKeyModeToken {
            PopSymbolicHotKeyMode(token)
            hotKeyModeToken = nil
        }
    }

    @objc private func done(_ sender: Any?) {
        finish(.keyboard(KeyboardCaptureResult(pressedKeyCodes: keyboardView.pressedKeyCodes,
                                               systemShortcutsBlocked: hotKeyModeToken != nil)))
    }

    // MARK: - System shortcuts

    /// Disables system shortcuts while this app is frontmost, once permitted.
    private func updateShortcutBlocking() {
        if hotKeyModeToken == nil && AXIsProcessTrusted() {
            hotKeyModeToken = PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabled))
        }
        let blocked = hotKeyModeToken != nil
        shortcutsLabel.stringValue = blocked
            ? "Atajos del sistema bloqueados mientras dura la prueba."
            : "Para bloquear también los atajos del sistema (F11, ⌘Tab, Spotlight…), nVital necesita permiso de Accesibilidad."
        shortcutsLabel.textColor = blocked ? .systemGreen : .secondaryLabelColor
        permissionButton.isHidden = blocked
        if blocked {
            trustTimer?.invalidate()
            trustTimer = nil
        }
    }

    @objc private func requestAccessibility(_ sender: Any?) {
        // Shows macOS' own prompt, which leads to Privacy & Security > Accessibility.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        window?.makeFirstResponder(keyboardView)
        trustTimer?.invalidate()
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.updateShortcutBlocking()
        }
    }
}

final class KeyboardView: NSView {
    private let keys: [KeyDescriptor]
    private(set) var pressedKeyCodes = Set<UInt16>()
    private var heldKeyCodes = Set<UInt16>()

    init(keys: [KeyDescriptor]) {
        self.keys = keys
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { return true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    // MARK: - Events

    override func keyDown(with event: NSEvent) {
        // Swallow everything (no beep, no Tab navigation, no Escape closing the sheet).
        register(event.keyCode, down: true)
    }

    override func keyUp(with event: NSEvent) {
        register(event.keyCode, down: false)
    }

    override func flagsChanged(with event: NSEvent) {
        // Modifiers and caps lock only send flagsChanged; toggle the held state.
        let code = event.keyCode
        register(code, down: !heldKeyCodes.contains(code))
    }

    /// Catches combinations such as ⌘Q or ⌘W before the menu does.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.isKeyWindow == true else { return false }
        register(event.keyCode, down: true)
        register(event.keyCode, down: false)
        return true
    }

    private func register(_ code: UInt16, down: Bool) {
        if down {
            pressedKeyCodes.insert(code)
            heldKeyCodes.insert(code)
        } else {
            heldKeyCodes.remove(code)
        }
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let rows = Dictionary(grouping: keys, by: { $0.row })
        let rowCount = (rows.keys.max() ?? 0) + 1
        let gap: CGFloat = 4
        let rowHeight = (bounds.height - gap * CGFloat(rowCount - 1)) / CGFloat(rowCount)
        let widestRow = rows.values.map { row in row.reduce(0) { $0 + $1.width } }.max() ?? 1
        let maxKeysInRow = rows.values.map { $0.count }.max() ?? 1
        let unit = (bounds.width - gap * CGFloat(maxKeysInRow - 1)) / CGFloat(widestRow)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        for rowIndex in 0..<rowCount {
            guard let rowKeys = rows[rowIndex] else { continue }
            // Row 0 is at the top; AppKit's origin is bottom-left.
            let y = bounds.height - CGFloat(rowIndex + 1) * rowHeight - CGFloat(rowIndex) * gap
            var x: CGFloat = 0
            for key in rowKeys {
                let width = unit * CGFloat(key.width)
                let rect = NSRect(x: x, y: y, width: width, height: rowHeight)
                x += width + gap

                let pressed = pressedKeyCodes.contains(key.keyCode)
                let held = heldKeyCodes.contains(key.keyCode)
                let fill: NSColor = held ? .systemBlue : pressed ? .systemGreen : (key.isRequired ? .controlColor : .windowBackgroundColor)
                fill.setFill()
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
                path.fill()
                NSColor.gridColor.setStroke()
                path.stroke()

                let attributes: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: key.label.count > 2 ? 10 : 13),
                    .foregroundColor: pressed || held ? NSColor.white : NSColor.labelColor,
                    .paragraphStyle: paragraph,
                ]
                let text = NSAttributedString(string: key.label, attributes: attributes)
                let textHeight = text.size().height
                text.draw(in: NSRect(x: rect.minX, y: rect.midY - textHeight / 2, width: rect.width, height: textHeight))
            }
        }
    }
}
