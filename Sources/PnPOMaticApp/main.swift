import AppKit
import PDFKit
import PnPCore
import UniformTypeIdentifiers

final class DropTargetView: NSView {
    var onPDFsDropped: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func pdfURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let objects = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] else {
            return []
        }

        return objects
            .map { $0 as URL }
            .filter { $0.pathExtension.lowercased() == "pdf" }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        pdfURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = pdfURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onPDFsDropped?(urls)
        return true
    }
}

final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private struct InputPDF {
        let url: URL
        let pageCount: Int
    }

    private var inputs: [InputPDF] = []
    private var temporaryOutputs: [URL] = []

    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "No PDFs yet")
    private let makeButton = NSButton(title: "Make 9-Up PDF", target: nil, action: nil)
    private let paperPopup = NSPopUpButton()
    private let cutPopup = NSPopUpButton()

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PnP-o-matic"
        window.minSize = NSSize(width: 560, height: 470)
        super.init(window: window)
        buildUI()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addPDFURLs(_ urls: [URL]) {
        var failures: [String] = []

        for url in urls where url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), document.pageCount > 0 else {
                failures.append(url.lastPathComponent)
                continue
            }
            inputs.append(InputPDF(url: url, pageCount: document.pageCount))
        }

        tableView.reloadData()
        updateStatus()

        if !failures.isEmpty {
            showAlert(
                message: "Could not add some PDFs",
                detail: failures.joined(separator: "\n")
            )
        }
    }

    func cleanupTemporaryOutputs() {
        for output in temporaryOutputs {
            try? FileManager.default.removeItem(at: output)
        }
        temporaryOutputs.removeAll()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            root.topAnchor.constraint(equalTo: content.topAnchor),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])

        let title = NSTextField(labelWithString: "PnP-o-matic")
        title.font = NSFont.systemFont(ofSize: 26, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "Turn one-card-per-page PDFs into print-ready 3×3 sheets.")
        subtitle.textColor = .secondaryLabelColor

        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)

        let dropTarget = DropTargetView()
        dropTarget.translatesAutoresizingMaskIntoConstraints = false
        dropTarget.onPDFsDropped = { [weak self] urls in
            self?.addPDFURLs(urls)
        }

        let dropStack = NSStackView()
        dropStack.orientation = .vertical
        dropStack.alignment = .centerX
        dropStack.spacing = 5
        dropStack.translatesAutoresizingMaskIntoConstraints = false

        let dropTitle = NSTextField(labelWithString: "Drop card PDFs here")
        dropTitle.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        let dropDetail = NSTextField(labelWithString: "Each PDF page is one card. Later drops append to the list.")
        dropDetail.textColor = .secondaryLabelColor

        dropStack.addArrangedSubview(dropTitle)
        dropStack.addArrangedSubview(dropDetail)
        dropTarget.addSubview(dropStack)

        NSLayoutConstraint.activate([
            dropTarget.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
            dropTarget.heightAnchor.constraint(equalToConstant: 90),
            dropStack.centerXAnchor.constraint(equalTo: dropTarget.centerXAnchor),
            dropStack.centerYAnchor.constraint(equalTo: dropTarget.centerYAnchor),
        ])
        root.addArrangedSubview(dropTarget)

        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("files"))
        tableColumn.title = "PDFs, imposed in this order"
        tableColumn.resizingMask = .autoresizingMask
        tableView.addTableColumn(tableColumn)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = true
        tableView.usesAlternatingRowBackgroundColors = true

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
            scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 150),
        ])
        root.addArrangedSubview(scroll)

        let listButtons = NSStackView()
        listButtons.orientation = .horizontal
        listButtons.spacing = 8

        let addButton = NSButton(title: "Add PDFs…", target: self, action: #selector(addFiles))
        let removeButton = NSButton(title: "Remove Selected", target: self, action: #selector(removeSelected))
        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearFiles))
        listButtons.addArrangedSubview(addButton)
        listButtons.addArrangedSubview(removeButton)
        listButtons.addArrangedSubview(clearButton)
        root.addArrangedSubview(listButtons)

        let options = NSStackView()
        options.orientation = .horizontal
        options.alignment = .centerY
        options.spacing = 10

        options.addArrangedSubview(NSTextField(labelWithString: "Paper:"))
        paperPopup.addItems(withTitles: PnPPaperSize.allCases.map(\.displayName))
        options.addArrangedSubview(paperPopup)

        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 16).isActive = true
        options.addArrangedSubview(spacer)

        options.addArrangedSubview(NSTextField(labelWithString: "Cut lines:"))
        cutPopup.addItems(withTitles: ["Edge marks only", "Full-page cut lines"])
        options.addArrangedSubview(cutPopup)
        root.addArrangedSubview(options)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        makeButton.target = self
        makeButton.action = #selector(makePDF)
        makeButton.keyEquivalent = "\r"
        makeButton.isEnabled = false

        footer.addArrangedSubview(statusLabel)
        footer.addArrangedSubview(makeButton)
        root.addArrangedSubview(footer)
        NSLayoutConstraint.activate([
            footer.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -40),
        ])
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        inputs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let field = NSTextField(labelWithString: "")
        let input = inputs[row]
        let noun = input.pageCount == 1 ? "card" : "cards"
        field.stringValue = "\(row + 1).  \(input.url.lastPathComponent)  —  \(input.pageCount) \(noun)"
        field.lineBreakMode = .byTruncatingMiddle
        return field
    }

    @objc private func addFiles() {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose one or more PDFs. Each page will be treated as one card."

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            self?.addPDFURLs(panel.urls)
        }
    }

    @objc private func removeSelected() {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }

        for index in indexes.sorted(by: >) {
            guard inputs.indices.contains(index) else { continue }
            inputs.remove(at: index)
        }
        tableView.reloadData()
        updateStatus()
    }

    @objc private func clearFiles() {
        inputs.removeAll()
        tableView.reloadData()
        updateStatus()
    }

    @objc private func makePDF() {
        let paper = PnPPaperSize.allCases[paperPopup.indexOfSelectedItem]
        let cutStyle: PnPCutStyle = cutPopup.indexOfSelectedItem == 0 ? .edgeMarks : .fullLines

        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PnP-o-matic", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: outputDirectory,
                withIntermediateDirectories: true
            )

            let outputURL = outputDirectory.appendingPathComponent(
                "PnP-o-matic-\(UUID().uuidString).pdf"
            )
            let result = try PnPImposer.impose(
                inputURLs: inputs.map(\.url),
                outputURL: outputURL,
                paperSize: paper,
                cutStyle: cutStyle
            )
            temporaryOutputs.append(outputURL)

            let percent = Int((result.scale * 100).rounded())
            let sheetWord = result.sheetCount == 1 ? "sheet" : "sheets"
            statusLabel.stringValue = "Created \(result.sheetCount) \(sheetWord) • cards at \(percent)% • opening Preview"
            openInPreview(outputURL)
        } catch {
            showAlert(message: "Could not make 9-Up PDF", detail: error.localizedDescription)
        }
    }

    private func openInPreview(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()

        if let preview = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Preview") {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: preview,
                configuration: configuration
            ) { [weak self] _, error in
                if let error {
                    DispatchQueue.main.async {
                        self?.showAlert(message: "Could not open Preview", detail: error.localizedDescription)
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    private func updateStatus() {
        let cards = inputs.reduce(0) { $0 + $1.pageCount }
        let sheets = (cards + 8) / 9

        if cards == 0 {
            statusLabel.stringValue = "No PDFs yet"
            makeButton.isEnabled = false
        } else {
            let cardWord = cards == 1 ? "card" : "cards"
            let sheetWord = sheets == 1 ? "sheet" : "sheets"
            statusLabel.stringValue = "\(cards) \(cardWord) • \(sheets) \(sheetWord)"
            makeButton.isEnabled = true
        }
    }

    private func showAlert(message: String, detail: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var pendingOpenURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        let controller = MainWindowController()
        mainWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)

        if !pendingOpenURLs.isEmpty {
            controller.addPDFURLs(pendingOpenURLs)
            pendingOpenURLs.removeAll()
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames
            .map(URL.init(fileURLWithPath:))
            .filter { $0.pathExtension.lowercased() == "pdf" }

        if let controller = mainWindowController {
            controller.addPDFURLs(urls)
        } else {
            pendingOpenURLs.append(contentsOf: urls)
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.cleanupTemporaryOutputs()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
