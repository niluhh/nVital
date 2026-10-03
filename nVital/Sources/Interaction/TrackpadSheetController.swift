import AppKit
import NVitalCore

/// A grid the user sweeps with the pointer, plus a checklist of gestures.
final class TrackpadSheetController: SheetController {
    private let trackpadView: TrackpadView

    init(request: TrackpadCaptureRequest) {
        let trackpadView = TrackpadView(columns: request.columns, rows: request.rows)
        trackpadView.translatesAutoresizingMaskIntoConstraints = false
        trackpadView.heightAnchor.constraint(equalToConstant: 320).isActive = true
        self.trackpadView = trackpadView

        let doneButton = NSButton(title: "Terminar", target: nil, action: nil)
        doneButton.keyEquivalent = "\r"
        super.init(title: "Prueba de trackpad", instructions: request.instructions,
                   content: trackpadView, size: NSSize(width: 640, height: 480), buttons: [doneButton])
        doneButton.target = self
        doneButton.action = #selector(done(_:))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func done(_ sender: Any?) {
        finish(.trackpad(trackpadView.result))
    }
}

final class TrackpadView: NSView {
    private let columns: Int
    private let rows: Int
    private var visited = Set<Int>()
    private var primaryClick = false
    private var secondaryClick = false
    private var scrolled = false
    private var pinched = false

    init(columns: Int, rows: Int) {
        self.columns = max(columns, 1)
        self.rows = max(rows, 1)
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    var result: TrackpadCaptureResult {
        return TrackpadCaptureResult(visitedCells: visited.count, totalCells: columns * rows,
                                     primaryClick: primaryClick, secondaryClick: secondaryClick,
                                     scrolled: scrolled, pinched: pinched)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    // MARK: - Events

    override func mouseMoved(with event: NSEvent) { visit(event) }
    override func mouseDragged(with event: NSEvent) { visit(event) }

    override func mouseDown(with event: NSEvent) {
        // A control-click is a secondary click.
        if event.modifierFlags.contains(.control) {
            secondaryClick = true
        } else {
            primaryClick = true
        }
        visit(event)
    }

    override func rightMouseDown(with event: NSEvent) {
        secondaryClick = true
        visit(event)
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 0 {
            scrolled = true
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        pinched = true
        needsDisplay = true
    }

    private var gridRect: NSRect {
        return NSRect(x: 0, y: 28, width: bounds.width, height: bounds.height - 28)
    }

    private func visit(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let grid = gridRect
        guard grid.contains(point) else { return }
        let column = min(Int((point.x - grid.minX) / grid.width * CGFloat(columns)), columns - 1)
        let row = min(Int((point.y - grid.minY) / grid.height * CGFloat(rows)), rows - 1)
        visited.insert(row * columns + column)
        needsDisplay = true
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        let grid = gridRect
        let cellWidth = grid.width / CGFloat(columns)
        let cellHeight = grid.height / CGFloat(rows)

        for row in 0..<rows {
            for column in 0..<columns {
                let rect = NSRect(x: grid.minX + CGFloat(column) * cellWidth, y: grid.minY + CGFloat(row) * cellHeight,
                                  width: cellWidth, height: cellHeight).insetBy(dx: 1.5, dy: 1.5)
                (visited.contains(row * columns + column) ? NSColor.systemGreen : NSColor.controlColor).setFill()
                NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            }
        }

        let checks = [("Clic", primaryClick), ("Clic secundario", secondaryClick),
                      ("Desplazar con dos dedos", scrolled), ("Pellizcar", pinched)]
        let text = checks.map { ($0.1 ? "✓ " : "○ ") + $0.0 }.joined(separator: "     ")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.labelColor,
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 2, y: 4))
    }
}
