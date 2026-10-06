import AppKit
import NVitalCore

/// The main window: list of tests, details of the selection, and run/export controls.
final class MainWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    private let runner: DiagnosticRunner
    private let interaction: InteractionController

    private let tableView = NSTableView()
    private let detailTextView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let runAllButton = NSButton(title: "Ejecutar todas", target: nil, action: nil)
    private let runSelectedButton = NSButton(title: "Ejecutar seleccionadas", target: nil, action: nil)
    private let stopButton = NSButton(title: "Detener", target: nil, action: nil)
    private let exportButton = NSButton(title: "Exportar informe…", target: nil, action: nil)

    private enum Column {
        static let status = NSUserInterfaceItemIdentifier("status")
        static let name = NSUserInterfaceItemIdentifier("name")
        static let message = NSUserInterfaceItemIdentifier("message")
    }

    init(runner: DiagnosticRunner) {
        self.runner = runner
        self.interaction = InteractionController()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
        window.title = "nVital"
        window.minSize = NSSize(width: 680, height: 480)
        window.center()
        super.init(window: window)

        window.delegate = self
        interaction.window = window
        runner.delegate = self
        runner.interactionHandler = interaction
        buildInterface(in: window)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Actions

    @objc func runAll(_ sender: Any?) {
        runner.run()
        refresh()
    }

    @objc func runSelected(_ sender: Any?) {
        let selected = tableView.selectedRowIndexes.map { runner.tests[$0] }
        guard !selected.isEmpty else { return }
        runner.run(selected)
        refresh()
    }

    @objc func stop(_ sender: Any?) {
        runner.cancel()
        refresh()
    }

    @objc func exportReport(_ sender: Any?) {
        guard let window = window else { return }
        ReportExporter.export(runner.makeReport(appVersion: AppDelegate.appVersion), from: window)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(runAll(_:)): return !runner.isRunning
        case #selector(runSelected(_:)): return !runner.isRunning && tableView.selectedRow >= 0
        case #selector(stop(_:)): return runner.isRunning
        case #selector(exportReport(_:)): return !runner.isRunning && !runner.results.isEmpty
        default: return true
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        runner.cancel()
        return true
    }

    // MARK: - State

    private func refresh() {
        let selection = tableView.selectedRowIndexes
        tableView.reloadData()
        tableView.selectRowIndexes(selection, byExtendingSelection: false)
        updateControls()
        updateDetail()
    }

    private func updateControls() {
        let running = runner.isRunning
        runAllButton.isEnabled = !running
        runSelectedButton.isEnabled = !running && tableView.selectedRow >= 0
        stopButton.isEnabled = running
        exportButton.isEnabled = !running && !runner.results.isEmpty

        if running {
            progressIndicator.startAnimation(nil)
            statusLabel.stringValue = runner.currentTest.map { "Ejecutando: \($0.name)…" } ?? "Ejecutando…"
        } else {
            progressIndicator.stopAnimation(nil)
            if runner.results.isEmpty {
                statusLabel.stringValue = "Pulsa «Ejecutar todas» para empezar."
            } else {
                statusLabel.stringValue = runner.makeReport().verdict
            }
        }
    }

    private func updateDetail() {
        let rows = tableView.selectedRowIndexes
        guard let row = rows.first, rows.count == 1 else {
            detailTextView.string = rows.isEmpty ? "Selecciona una prueba para ver los detalles." : "\(rows.count) pruebas seleccionadas."
            return
        }
        let test = runner.tests[row]
        var lines = [test.name, test.summary, ""]
        if let result = runner.result(for: test) {
            lines.append("\(result.status.displayName): \(result.message)")
            for measurement in result.measurements {
                lines.append("  · \(measurement.label): \(measurement.value)")
            }
            lines.append(String(format: "  · Duración: %.1f s", result.duration))
        } else if runner.currentTest === test {
            lines.append("En curso…")
        } else {
            lines.append(test.requiresInteraction ? "Pendiente · necesita tu ayuda" : "Pendiente · automática")
        }
        detailTextView.string = lines.joined(separator: "\n")
    }

    // MARK: - Layout

    private func buildInterface(in window: NSWindow) {
        let machine = runner.machine
        let title = NSTextField(labelWithString: "Diagnóstico de hardware")
        title.font = NSFont.boldSystemFont(ofSize: 18)
        let memory = ByteCountFormatter.string(fromByteCount: Int64(machine.memoryBytes), countStyle: .memory)
        let subtitle = NSTextField(labelWithString: "\(machine.modelIdentifier) · \(machine.processor) · \(memory) · macOS \(machine.systemVersion) · Serie \(machine.serialNumber)")
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let titles = NSStackView(views: [title, subtitle])
        titles.orientation = .vertical
        titles.alignment = .leading
        titles.spacing = 2
        let logo = NSImageView(image: NSApp.applicationIconImage)
        logo.imageScaling = .scaleProportionallyUpOrDown
        logo.widthAnchor.constraint(equalToConstant: 44).isActive = true
        logo.heightAnchor.constraint(equalToConstant: 44).isActive = true
        let header = NSStackView(views: [logo, titles])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10

        let tableScroll = makeTable()
        let detailScroll = makeDetailView()

        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        for (button, action) in [(runAllButton, #selector(runAll(_:))), (runSelectedButton, #selector(runSelected(_:))),
                                 (stopButton, #selector(stop(_:))), (exportButton, #selector(exportReport(_:)))] {
            button.target = self
            button.action = action
            button.bezelStyle = .rounded
        }
        runAllButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let footer = NSStackView(views: [progressIndicator, statusLabel, spacer, stopButton, runSelectedButton, exportButton, runAllButton])
        footer.orientation = .horizontal
        footer.spacing = 8

        let content = NSStackView(views: [header, tableScroll, detailScroll, footer])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(content)
        window.contentView = container
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            header.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40),
            tableScroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40),
            detailScroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40),
            footer.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -40),
            detailScroll.heightAnchor.constraint(equalToConstant: 150),
            tableScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200),
        ])
    }

    private func makeTable() -> NSScrollView {
        let columns: [(NSUserInterfaceItemIdentifier, String, CGFloat)] = [
            (Column.status, "Estado", 100),
            (Column.name, "Prueba", 160),
            (Column.message, "Resultado", 420),
        ]
        for (identifier, title, width) in columns {
            let column = NSTableColumn(identifier: identifier)
            column.title = title
            column.width = width
            column.minWidth = 60
            tableView.addTableColumn(column)
        }
        tableView.rowHeight = 24
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(runClickedRow(_:))

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return scroll
    }

    private func makeDetailView() -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        detailTextView.frame = NSRect(x: 0, y: 0, width: 600, height: 150)
        detailTextView.isEditable = false
        detailTextView.font = NSFont.systemFont(ofSize: 12)
        detailTextView.textContainerInset = NSSize(width: 6, height: 6)
        detailTextView.minSize = .zero
        detailTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        detailTextView.isVerticallyResizable = true
        detailTextView.isHorizontallyResizable = false
        detailTextView.autoresizingMask = [.width]
        detailTextView.textContainer?.widthTracksTextView = true
        scroll.documentView = detailTextView
        return scroll
    }

    @objc private func runClickedRow(_ sender: Any?) {
        let row = tableView.clickedRow
        guard row >= 0, !runner.isRunning else { return }
        runner.run([runner.tests[row]])
        refresh()
    }
}

// MARK: - Table

extension MainWindowController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int {
        return runner.tests.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let identifier = tableColumn?.identifier else { return nil }
        let test = runner.tests[row]
        let result = runner.result(for: test)
        let isRunning = runner.currentTest === test

        let field = (tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField) ?? {
            let field = NSTextField(labelWithString: "")
            field.identifier = identifier
            field.lineBreakMode = .byTruncatingTail
            return field
        }()
        field.textColor = .labelColor
        field.font = NSFont.systemFont(ofSize: 13)

        switch identifier {
        case Column.status:
            if isRunning {
                field.stringValue = "● En curso"
                field.textColor = .systemBlue
            } else if let result = result {
                field.stringValue = "● " + result.status.displayName
                field.textColor = StatusPresentation.color(for: result.status)
            } else {
                field.stringValue = "○ Pendiente"
                field.textColor = .secondaryLabelColor
            }
        case Column.name:
            field.stringValue = test.name
            field.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        default:
            if let result = result, !isRunning {
                field.stringValue = result.message
            } else {
                field.stringValue = test.summary
                field.textColor = .secondaryLabelColor
            }
        }
        field.toolTip = field.stringValue
        return field
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        updateControls()
        updateDetail()
    }
}

// MARK: - Runner

extension MainWindowController: DiagnosticRunnerDelegate {
    func runner(_ runner: DiagnosticRunner, didStart test: DiagnosticTest) {
        refresh()
        if let row = runner.tests.firstIndex(where: { $0 === test }) {
            tableView.scrollRowToVisible(row)
        }
    }

    func runner(_ runner: DiagnosticRunner, didFinish test: DiagnosticTest, with result: DiagnosticResult) {
        refresh()
    }

    func runnerDidFinish(_ runner: DiagnosticRunner, cancelled: Bool) {
        refresh()
        if !cancelled {
            NSApp.requestUserAttention(.informationalRequest)
        }
    }
}
