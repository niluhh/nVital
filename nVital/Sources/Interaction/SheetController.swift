import AppKit
import NVitalCore

/// Base class for the sheets of interactive tests: a title, instructions,
/// a custom content view and a row of buttons at the bottom.
class SheetController: NSWindowController {
    var onFinish: ((InteractionResponse) -> Void)?

    init(title: String, instructions: String, content: NSView, size: NSSize, buttons: [NSButton]) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        super.init(window: window)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.boldSystemFont(ofSize: 15)
        let instructionsLabel = NSTextField(wrappingLabelWithString: instructions)
        instructionsLabel.textColor = .secondaryLabelColor

        let skipButton = NSButton(title: "Omitir prueba", target: self, action: #selector(skip(_:)))
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttonRow = NSStackView(views: [skipButton, spacer] + buttons)
        buttonRow.orientation = .horizontal

        let stack = NSStackView(views: [titleLabel, instructionsLabel, content, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        window.contentView = container
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            instructionsLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            content.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Release resources (preview layers, event monitors) before the sheet closes.
    func tearDown() {}

    func finish(_ response: InteractionResponse) {
        let handler = onFinish
        onFinish = nil
        handler?(response)
    }

    @objc private func skip(_ sender: Any?) {
        finish(.skipped)
    }
}
