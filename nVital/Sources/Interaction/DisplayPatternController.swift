import AppKit
import NVitalCore

/// Covers a screen with each pattern in turn. Click or any key advances;
/// Escape aborts.
final class DisplayPatternController: NSObject {
    private let request: DisplayPatternRequest
    private var window: NSWindow?
    private var completion: ((Bool) -> Void)?

    init(request: DisplayPatternRequest) {
        self.request = request
        super.init()
    }

    /// `completion(true)` when every pattern was shown, `false` if aborted.
    func show(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        let screen = targetScreen()
        let window = PatternWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PatternView(patterns: request.patterns)
        view.onFinish = { [weak self] completed in
            self?.end(completed)
        }
        window.contentView = view
        window.setFrame(screen.frame, display: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        NSCursor.hide()
        self.window = window
    }

    func close() {
        guard let window = window else { return }
        self.window = nil
        NSCursor.unhide()
        window.orderOut(nil)
    }

    private func end(_ completed: Bool) {
        close()
        let handler = completion
        completion = nil
        handler?(completed)
    }

    private func targetScreen() -> NSScreen {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let id = request.displayID,
           let screen = NSScreen.screens.first(where: { ($0.deviceDescription[key] as? NSNumber)?.uint32Value == id }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }
}

/// Borderless windows cannot become key unless they say so.
private final class PatternWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
}

private final class PatternView: NSView {
    var onFinish: ((Bool) -> Void)?
    private let patterns: [DisplayPattern]
    private var index = 0

    init(patterns: [DisplayPattern]) {
        self.patterns = patterns
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override var acceptsFirstResponder: Bool { return true }

    override func mouseDown(with event: NSEvent) { advance() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 0x35 { // Escape
            onFinish?(false)
        } else {
            advance()
        }
    }

    private func advance() {
        index += 1
        if index >= patterns.count {
            onFinish?(true)
        } else {
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard index < patterns.count else { return }
        switch patterns[index].kind {
        case let .solid(red, green, blue):
            NSColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: 1).setFill()
            bounds.fill()
        case .horizontalGradient:
            NSGradient(starting: .black, ending: .white)?.draw(in: bounds, angle: 0)
        case .checkerboard(let size):
            NSColor.black.setFill()
            bounds.fill()
            NSColor.white.setFill()
            let step = CGFloat(max(size, 1))
            var y: CGFloat = 0
            var rowIndex = 0
            while y < bounds.height {
                var x: CGFloat = rowIndex % 2 == 0 ? 0 : step
                while x < bounds.width {
                    NSRect(x: x, y: y, width: step, height: step).fill()
                    x += step * 2
                }
                y += step
                rowIndex += 1
            }
        }
    }
}
