import AppKit
import PDFKit
import PnPCore
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    static let pnpCardSlot = NSPasteboard.PasteboardType("com.udeudeude.pnpomatic.card-slot")
}

private struct CardPair {
    var front: PnPCardAsset?
    var back: PnPCardAsset?

    var isEmpty: Bool {
        front == nil && back == nil
    }
}

private func thumbnail(for asset: PnPCardAsset?, size: NSSize) -> NSImage? {
    guard let asset else { return nil }

    switch asset {
    case .pdfPage(let url, let pageIndex):
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return nil
        }
        return page.thumbnail(of: size, for: .cropBox)

    case .image(let url):
        return NSImage(contentsOf: url)
    }
}

final class CardSlotView: NSView, NSDraggingSource {
    var side: PnPCardSide = .front
    var globalIndex: Int = 0
    var onExternalDrop: ((PnPCardSide, Int, [URL]) -> Void)?
    var onMove: ((PnPCardSide, Int, Int) -> Void)?
    var onClear: ((PnPCardSide, Int) -> Void)?

    private let imageView = NSImageView()
    private let numberLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private var asset: PnPCardAsset?
    private var dragStarted = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        registerForDraggedTypes([.pnpCardSlot, .fileURL])

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)

        numberLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        numberLabel.textColor = .labelColor
        numberLabel.drawsBackground = true
        numberLabel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82)
        numberLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(numberLabel)

        sourceLabel.font = NSFont.systemFont(ofSize: 9)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.alignment = .center
        sourceLabel.lineBreakMode = .byTruncatingMiddle
        sourceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sourceLabel)

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            imageView.bottomAnchor.constraint(equalTo: sourceLabel.topAnchor, constant: -3),

            numberLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            numberLabel.topAnchor.constraint(equalTo: topAnchor, constant: 5),

            sourceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            sourceLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            sourceLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
            sourceLabel.heightAnchor.constraint(equalToConstant: 13),
        ])

        let menu = NSMenu()
        let clear = NSMenuItem(title: "Clear This Slot", action: #selector(clearSlot), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)
        self.menu = menu
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        side: PnPCardSide,
        globalIndex: Int,
        number: Int,
        asset: PnPCardAsset?
    ) {
        self.side = side
        self.globalIndex = globalIndex
        self.asset = asset

        numberLabel.stringValue = "#\(number)"
        imageView.image = thumbnail(for: asset, size: NSSize(width: 210, height: 290))
        sourceLabel.stringValue = asset?.sourceName ?? "Drop PDF / image"

        if asset == nil {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        } else {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
    }

    @objc private func clearSlot() {
        onClear?(side, globalIndex)
    }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard asset != nil, !dragStarted else { return }
        dragStarted = true

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            "\(side.rawValue):\(globalIndex)",
            forType: .pnpCardSlot
        )

        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        let dragImage = imageView.image ?? NSImage(size: bounds.size)
        draggingItem.setDraggingFrame(bounds, contents: dragImage)

        beginDraggingSession(
            with: [draggingItem],
            event: event,
            source: self
        )
    }

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        .move
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if sender.draggingPasteboard.string(forType: .pnpCardSlot) != nil {
            return .move
        }

        return externalURLs(from: sender).isEmpty ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let payload = sender.draggingPasteboard.string(forType: .pnpCardSlot) {
            let pieces = payload.split(separator: ":")
            guard pieces.count == 2,
                  let sourceSide = PnPCardSide(rawValue: String(pieces[0])),
                  sourceSide == side,
                  let sourceIndex = Int(pieces[1]) else {
                return false
            }

            onMove?(side, sourceIndex, globalIndex)
            return true
        }

        let urls = externalURLs(from: sender)
        guard !urls.isEmpty else { return false }
        onExternalDrop?(side, globalIndex, urls)
        return true
    }

    private func externalURLs(from sender: NSDraggingInfo) -> [URL] {
        guard let values = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [NSURL] else {
            return []
        }

        return values
            .map { $0 as URL }
            .filter { url in
                if url.pathExtension.lowercased() == "pdf" {
                    return true
                }
                return UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
            }
    }
}

final class SheetCanvasView: NSView {
    let slots: [CardSlotView]

    private var paperSize = PnPPaperSize.letter.size
    private var cardSize = PnPCardSizePreset.poker.fixedSize ?? CGSize(width: 180, height: 252)
    private var cutStyle: PnPCutStyle = .edgeMarks

    override var isFlipped: Bool { true }

    init(slots: [CardSlotView]) {
        self.slots = slots
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        for slot in slots {
            slot.translatesAutoresizingMaskIntoConstraints = true
            addSubview(slot)
        }

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(greaterThanOrEqualToConstant: 330),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 430),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        paperSize: CGSize,
        cardSize: CGSize,
        cutStyle: PnPCutStyle
    ) {
        self.paperSize = paperSize
        self.cardSize = cardSize
        self.cutStyle = cutStyle
        needsLayout = true
        needsDisplay = true
    }

    private var pageRect: CGRect {
        let available = bounds.insetBy(dx: 8, dy: 8)
        guard paperSize.width > 0, paperSize.height > 0 else { return available }

        let scale = min(
            available.width / paperSize.width,
            available.height / paperSize.height
        )
        let size = CGSize(width: paperSize.width * scale, height: paperSize.height * scale)
        return CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private func pageScale() -> CGFloat {
        guard paperSize.width > 0 else { return 1 }
        return pageRect.width / paperSize.width
    }

    override func layout() {
        super.layout()

        let geometry = PnPImposer.gridGeometry(cardSize: cardSize, sheetSize: paperSize)
        let page = pageRect
        let scale = pageScale()

        for visualSlot in 0..<min(9, slots.count) {
            let cardFrame = geometry.frame(forSlot: visualSlot)
            let frame = CGRect(
                x: page.minX + cardFrame.minX * scale,
                y: page.minY + (paperSize.height - cardFrame.maxY) * scale,
                width: cardFrame.width * scale,
                height: cardFrame.height * scale
            )
            slots[visualSlot].frame = frame.insetBy(dx: 0.5, dy: 0.5)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let page = pageRect
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(rect: page).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(0.5).setStroke()
        let outline = NSBezierPath(rect: page)
        outline.lineWidth = 0.5
        outline.stroke()

        drawTrimLines(in: page)
    }

    private func drawTrimLines(in page: CGRect) {
        let geometry = PnPImposer.gridGeometry(cardSize: cardSize, sheetSize: paperSize)
        let scale = pageScale()

        func x(_ value: CGFloat) -> CGFloat {
            page.minX + value * scale
        }

        func y(_ value: CGFloat) -> CGFloat {
            page.minY + (paperSize.height - value) * scale
        }

        let path = NSBezierPath()
        path.lineWidth = max(0.35, 0.5 * scale)
        NSColor.black.withAlphaComponent(0.5).setStroke()

        switch cutStyle {
        case .fullLines:
            for position in geometry.verticalCutPositions {
                path.move(to: CGPoint(x: x(position), y: page.minY))
                path.line(to: CGPoint(x: x(position), y: page.maxY))
            }
            for position in geometry.horizontalCutPositions {
                path.move(to: CGPoint(x: page.minX, y: y(position)))
                path.line(to: CGPoint(x: page.maxX, y: y(position)))
            }

        case .edgeMarks:
            let gap = 1.5 * scale
            let topGrid = y(geometry.gridRect.maxY)
            let bottomGrid = y(geometry.gridRect.minY)
            let leftGrid = x(geometry.gridRect.minX)
            let rightGrid = x(geometry.gridRect.maxX)

            for position in geometry.verticalCutPositions {
                let px = x(position)
                path.move(to: CGPoint(x: px, y: page.minY))
                path.line(to: CGPoint(x: px, y: max(page.minY, topGrid - gap)))
                path.move(to: CGPoint(x: px, y: min(page.maxY, bottomGrid + gap)))
                path.line(to: CGPoint(x: px, y: page.maxY))
            }

            for position in geometry.horizontalCutPositions {
                let py = y(position)
                path.move(to: CGPoint(x: page.minX, y: py))
                path.line(to: CGPoint(x: max(page.minX, leftGrid - gap), y: py))
                path.move(to: CGPoint(x: min(page.maxX, rightGrid + gap), y: py))
                path.line(to: CGPoint(x: page.maxX, y: py))
            }
        }

        path.stroke()
    }
}

final class PreviewGrid {
    let container = NSStackView()
    let titleLabel: NSTextField
    let detailLabel: NSTextField
    let addButton: NSButton
    private let canvas: SheetCanvasView
    private var slots: [CardSlotView] = []

    init(
        title: String,
        detail: String,
        buttonTitle: String,
        target: AnyObject?,
        action: Selector
    ) {
        titleLabel = NSTextField(labelWithString: title)
        detailLabel = NSTextField(wrappingLabelWithString: detail)
        addButton = NSButton(title: buttonTitle, target: target, action: action)

        var builtSlots: [CardSlotView] = []
        for _ in 0..<9 {
            builtSlots.append(CardSlotView())
        }
        slots = builtSlots
        canvas = SheetCanvasView(slots: builtSlots)

        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 8

        titleLabel.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.font = NSFont.systemFont(ofSize: 11)

        container.addArrangedSubview(titleLabel)
        container.addArrangedSubview(detailLabel)
        container.addArrangedSubview(addButton)
        container.addArrangedSubview(canvas)

        canvas.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true
    }

    func slot(at visualIndex: Int) -> CardSlotView {
        slots[visualIndex]
    }

    func configureSheet(
        paperSize: CGSize,
        cardSize: CGSize,
        cutStyle: PnPCutStyle
    ) {
        canvas.configure(
            paperSize: paperSize,
            cardSize: cardSize,
            cutStyle: cutStyle
        )
    }
}
final class MainWindowController: NSWindowController {
    private var pairs: [CardPair] = []
    private var temporaryOutputs: [URL] = []
    private var currentSheet = 0

    private let frontPreview: PreviewGrid
    private let backPreview: PreviewGrid

    private let statusLabel = NSTextField(labelWithString: "No cards yet")
    private let sheetLabel = NSTextField(labelWithString: "Sheet 1 of 1")
    private let previousButton = NSButton(title: "‹", target: nil, action: nil)
    private let nextButton = NSButton(title: "›", target: nil, action: nil)

    private let makeButton = NSButton(title: "Make Duplex 9-Up PDF", target: nil, action: nil)
    private let cardSizePopup = NSPopUpButton()
    private let customWidthField = NSTextField(string: "2.5")
    private let customHeightField = NSTextField(string: "3.5")
    private let customUnitPopup = NSPopUpButton()
    private let customSizeControls = NSStackView()
    private let paperPopup = NSPopUpButton()
    private let cutPopup = NSPopUpButton()
    private let duplexPopup = NSPopUpButton()
    private let lockSwitch = NSSwitch()

    init() {
        frontPreview = PreviewGrid(
            title: "Fronts",
            detail: "Front sheet: 1–2–3 / 4–5–6 / 7–8–9",
            buttonTitle: "Add Fronts…",
            target: nil,
            action: #selector(addFronts)
        )
        backPreview = PreviewGrid(
            title: "Backs",
            detail: "Back sheet mirrors positions for duplex alignment.",
            buttonTitle: "Add Backs…",
            target: nil,
            action: #selector(addBacks)
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PnP-o-matic"
        window.minSize = NSSize(width: 860, height: 740)

        super.init(window: window)

        frontPreview.addButton.target = self
        backPreview.addButton.target = self

        buildUI()
        configureSlots()
        refresh()
        window.center()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func addPDFURLs(_ urls: [URL]) {
        appendAssets(urls.flatMap(PnPImposer.assets(from:)), to: .front)
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
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
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
        root.addArrangedSubview(title)

        let subtitle = NSTextField(
            labelWithString: "Build numbered front/back card sheets, rearrange cards by dragging, and print duplex-ready 3×3 layouts."
        )
        subtitle.textColor = .secondaryLabelColor
        root.addArrangedSubview(subtitle)

        let importRow = NSStackView()
        importRow.orientation = .horizontal
        importRow.spacing = 8
        let alternating = NSButton(
            title: "Import Alternating Front / Back PDF…",
            target: self,
            action: #selector(importAlternating)
        )
        importRow.addArrangedSubview(alternating)
        let importHelp = NSTextField(
            labelWithString: "For separate PDFs, use Add Fronts and Add Backs. Pages pair by card number."
        )
        importHelp.textColor = .secondaryLabelColor
        importHelp.font = NSFont.systemFont(ofSize: 11)
        importRow.addArrangedSubview(importHelp)
        root.addArrangedSubview(importRow)

        let previews = NSStackView()
        previews.orientation = .horizontal
        previews.alignment = .top
        previews.distribution = .fillEqually
        previews.spacing = 24
        previews.addArrangedSubview(frontPreview.container)
        previews.addArrangedSubview(backPreview.container)
        root.addArrangedSubview(previews)

        let nav = NSStackView()
        nav.orientation = .horizontal
        nav.alignment = .centerY
        nav.spacing = 8

        previousButton.target = self
        previousButton.action = #selector(previousSheet)
        nextButton.target = self
        nextButton.action = #selector(nextSheet)

        nav.addArrangedSubview(previousButton)
        nav.addArrangedSubview(sheetLabel)
        nav.addArrangedSubview(nextButton)

        let navHelp = NSTextField(
            labelWithString: "Drop PDFs or image files directly onto any numbered slot. Multi-page PDFs continue from that slot."
        )
        navHelp.textColor = .secondaryLabelColor
        navHelp.font = NSFont.systemFont(ofSize: 11)

        nav.addArrangedSubview(navHelp)
        root.addArrangedSubview(nav)

        let options1 = NSStackView()
        options1.orientation = .horizontal
        options1.alignment = .centerY
        options1.spacing = 9

        options1.addArrangedSubview(NSTextField(labelWithString: "Card size:"))
        cardSizePopup.addItems(withTitles: PnPCardSizePreset.allCases.map(\.displayName))
        cardSizePopup.selectItem(at: 1)
        cardSizePopup.target = self
        cardSizePopup.action = #selector(cardSizeChanged)
        options1.addArrangedSubview(cardSizePopup)

        customSizeControls.orientation = .horizontal
        customSizeControls.alignment = .centerY
        customSizeControls.spacing = 5
        customWidthField.alignment = .right
        customHeightField.alignment = .right
        customWidthField.translatesAutoresizingMaskIntoConstraints = false
        customHeightField.translatesAutoresizingMaskIntoConstraints = false
        customWidthField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        customHeightField.widthAnchor.constraint(equalToConstant: 52).isActive = true
        customUnitPopup.addItems(withTitles: ["in", "mm"])
        customUnitPopup.target = self
        customUnitPopup.action = #selector(previewOptionsChanged)
        customWidthField.target = self
        customWidthField.action = #selector(previewOptionsChanged)
        customHeightField.target = self
        customHeightField.action = #selector(previewOptionsChanged)
        customSizeControls.addArrangedSubview(NSTextField(labelWithString: "W"))
        customSizeControls.addArrangedSubview(customWidthField)
        customSizeControls.addArrangedSubview(NSTextField(labelWithString: "× H"))
        customSizeControls.addArrangedSubview(customHeightField)
        customSizeControls.addArrangedSubview(customUnitPopup)
        customSizeControls.isHidden = true
        options1.addArrangedSubview(customSizeControls)

        options1.addArrangedSubview(NSTextField(labelWithString: "Paper:"))
        paperPopup.addItems(withTitles: PnPPaperSize.allCases.map(\.displayName))
        paperPopup.target = self
        paperPopup.action = #selector(previewOptionsChanged)
        options1.addArrangedSubview(paperPopup)

        options1.addArrangedSubview(NSTextField(labelWithString: "Cut lines:"))
        cutPopup.addItems(withTitles: ["Edge marks only", "Full-page cut lines"])
        cutPopup.target = self
        cutPopup.action = #selector(previewOptionsChanged)
        options1.addArrangedSubview(cutPopup)

        root.addArrangedSubview(options1)

        let options2 = NSStackView()
        options2.orientation = .horizontal
        options2.alignment = .centerY
        options2.spacing = 10

        options2.addArrangedSubview(NSTextField(labelWithString: "Duplex flip:"))
        duplexPopup.addItems(withTitles: [
            "Long edge - mirror columns",
            "Short edge - mirror rows",
        ])
        duplexPopup.target = self
        duplexPopup.action = #selector(duplexChanged)
        options2.addArrangedSubview(duplexPopup)

        lockSwitch.state = .on
        options2.addArrangedSubview(lockSwitch)
        options2.addArrangedSubview(
            NSTextField(labelWithString: "Lock corresponding fronts and backs while rearranging")
        )

        root.addArrangedSubview(options2)

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 12
        footer.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

        makeButton.target = self
        makeButton.action = #selector(makePDF)
        makeButton.keyEquivalent = "\r"
        makeButton.isEnabled = false

        footer.addArrangedSubview(statusLabel)
        footer.addArrangedSubview(makeButton)
        root.addArrangedSubview(footer)

        NSLayoutConstraint.activate([
            previews.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
            footer.widthAnchor.constraint(equalTo: root.widthAnchor, constant: -36),
        ])
    }

    private func configureSlots() {
        for visualIndex in 0..<9 {
            for preview in [frontPreview, backPreview] {
                let slot = preview.slot(at: visualIndex)
                slot.onExternalDrop = { [weak self] side, index, urls in
                    self?.drop(urls: urls, on: side, at: index)
                }
                slot.onMove = { [weak self] side, source, destination in
                    self?.move(side: side, from: source, to: destination)
                }
                slot.onClear = { [weak self] side, index in
                    self?.clear(side: side, at: index)
                }
            }
        }
    }

    @objc private func addFronts() {
        chooseAssets(message: "Choose front PDFs or images") { [weak self] urls in
            self?.appendAssets(urls.flatMap(PnPImposer.assets(from:)), to: .front)
        }
    }

    @objc private func addBacks() {
        chooseAssets(message: "Choose back PDFs or images") { [weak self] urls in
            self?.appendAssets(urls.flatMap(PnPImposer.assets(from:)), to: .back)
        }
    }

    @objc private func importAlternating() {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose a PDF ordered front, back, front, back…"

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.appendAlternatingPDF(url)
        }
    }

    private func chooseAssets(
        message: String,
        completion: @escaping ([URL]) -> Void
    ) {
        guard let window else { return }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf, .image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = message

        panel.beginSheetModal(for: window) { response in
            guard response == .OK else { return }
            completion(panel.urls)
        }
    }

    private func appendAssets(_ assets: [PnPCardAsset], to side: PnPCardSide) {
        guard !assets.isEmpty else { return }

        let start = nextInsertionIndex(for: side)
        ensurePairCount(start + assets.count)

        for (offset, asset) in assets.enumerated() {
            set(asset: asset, side: side, at: start + offset)
        }

        currentSheet = start / 9
        trimTrailingEmptyPairs()
        refresh()
    }

    private func appendAlternatingPDF(_ url: URL) {
        let assets = PnPImposer.assets(from: url)
        guard !assets.isEmpty else { return }

        let start = pairs.count
        let pairCount = (assets.count + 1) / 2
        ensurePairCount(start + pairCount)

        for pairOffset in 0..<pairCount {
            let frontIndex = pairOffset * 2
            let backIndex = frontIndex + 1
            pairs[start + pairOffset].front = assets[frontIndex]
            if assets.indices.contains(backIndex) {
                pairs[start + pairOffset].back = assets[backIndex]
            }
        }

        currentSheet = start / 9
        refresh()
    }

    private func drop(urls: [URL], on side: PnPCardSide, at index: Int) {
        let assets = urls.flatMap(PnPImposer.assets(from:))
        guard !assets.isEmpty else { return }

        ensurePairCount(index + assets.count)
        for (offset, asset) in assets.enumerated() {
            set(asset: asset, side: side, at: index + offset)
        }

        trimTrailingEmptyPairs()
        refresh()
    }

    private func move(side: PnPCardSide, from source: Int, to destination: Int) {
        guard source != destination,
              pairs.indices.contains(source) else {
            return
        }

        ensurePairCount(max(source, destination) + 1)

        if lockSwitch.state == .on {
            let pair = pairs.remove(at: source)
            pairs.insert(pair, at: min(destination, pairs.count))
        } else {
            var values = pairs.map { pair -> PnPCardAsset? in
                side == .front ? pair.front : pair.back
            }
            let value = values.remove(at: source)
            values.insert(value, at: min(destination, values.count))

            for index in values.indices {
                if side == .front {
                    pairs[index].front = values[index]
                } else {
                    pairs[index].back = values[index]
                }
            }
        }

        trimTrailingEmptyPairs()
        refresh()
    }

    private func clear(side: PnPCardSide, at index: Int) {
        guard pairs.indices.contains(index) else { return }

        if side == .front {
            pairs[index].front = nil
        } else {
            pairs[index].back = nil
        }

        trimTrailingEmptyPairs()
        refresh()
    }

    private func nextInsertionIndex(for side: PnPCardSide) -> Int {
        for index in pairs.indices.reversed() {
            let asset = side == .front ? pairs[index].front : pairs[index].back
            if asset != nil {
                return index + 1
            }
        }
        return 0
    }

    private func set(asset: PnPCardAsset?, side: PnPCardSide, at index: Int) {
        ensurePairCount(index + 1)
        if side == .front {
            pairs[index].front = asset
        } else {
            pairs[index].back = asset
        }
    }

    private func ensurePairCount(_ count: Int) {
        while pairs.count < count {
            pairs.append(CardPair())
        }
    }

    private func trimTrailingEmptyPairs() {
        while pairs.last?.isEmpty == true {
            pairs.removeLast()
        }

        let maximumSheet = max(0, sheetCount - 1)
        currentSheet = min(currentSheet, maximumSheet)
    }

    private var sheetCount: Int {
        max(1, (pairs.count + 8) / 9)
    }

    private var selectedDuplexFlip: PnPDuplexFlip {
        duplexPopup.indexOfSelectedItem == 0 ? .longEdge : .shortEdge
    }

    @objc private func previousSheet() {
        currentSheet = max(0, currentSheet - 1)
        refresh()
    }

    @objc private func nextSheet() {
        currentSheet = min(sheetCount - 1, currentSheet + 1)
        refresh()
    }

    @objc private func duplexChanged() {
        refresh()
    }

    @objc private func cardSizeChanged() {
        let preset = PnPCardSizePreset.allCases[cardSizePopup.indexOfSelectedItem]
        customSizeControls.isHidden = preset != .custom
        refresh()
    }

    @objc private func previewOptionsChanged() {
        refresh()
    }

    private func currentPreviewCardSize() -> CGSize {
        let preset = PnPCardSizePreset.allCases[cardSizePopup.indexOfSelectedItem]

        if let fixed = preset.fixedSize {
            return fixed
        }

        if preset == .custom,
           let width = Double(customWidthField.stringValue),
           let height = Double(customHeightField.stringValue),
           width > 0,
           height > 0 {
            let pointsPerUnit: Double = customUnitPopup.indexOfSelectedItem == 0
                ? 72
                : 72 / 25.4
            return CGSize(
                width: CGFloat(width * pointsPerUnit),
                height: CGFloat(height * pointsPerUnit)
            )
        }

        let firstAsset = pairs.compactMap(\.front).first
            ?? pairs.compactMap(\.back).first

        if let firstAsset {
            switch firstAsset {
            case .pdfPage(let url, let pageIndex):
                if let document = PDFDocument(url: url),
                   let page = document.page(at: pageIndex) {
                    let size = page.bounds(for: .cropBox).size
                    if size.width > 0 && size.height > 0 {
                        return size
                    }
                }
            case .image(let url):
                if let image = NSImage(contentsOf: url),
                   image.size.width > 0,
                   image.size.height > 0 {
                    return image.size
                }
            }
        }

        return PnPCardSizePreset.poker.fixedSize ?? CGSize(width: 180, height: 252)
    }

    private func refresh() {
        let start = currentSheet * 9
        let flip = selectedDuplexFlip

        for visualSlot in 0..<9 {
            let frontLogicalSlot = visualSlot
            let frontIndex = start + frontLogicalSlot
            let frontAsset = pairs.indices.contains(frontIndex) ? pairs[frontIndex].front : nil
            frontPreview.slot(at: visualSlot).configure(
                side: .front,
                globalIndex: frontIndex,
                number: frontIndex + 1,
                asset: frontAsset
            )

            let backLogicalSlot = PnPImposer.mirroredSlot(visualSlot, flip: flip)
            let backIndex = start + backLogicalSlot
            let backAsset = pairs.indices.contains(backIndex) ? pairs[backIndex].back : nil
            backPreview.slot(at: visualSlot).configure(
                side: .back,
                globalIndex: backIndex,
                number: backIndex + 1,
                asset: backAsset
            )
        }

        let arrangement: String
        switch flip {
        case .longEdge:
            arrangement = "Back sheet: 3–2–1 / 6–5–4 / 9–8–7"
        case .shortEdge:
            arrangement = "Back sheet: 7–8–9 / 4–5–6 / 1–2–3"
        }
        backPreview.detailLabel.stringValue = arrangement

        let paper = PnPPaperSize.allCases[paperPopup.indexOfSelectedItem]
        let cutStyle: PnPCutStyle = cutPopup.indexOfSelectedItem == 0 ? .edgeMarks : .fullLines
        let previewCardSize = currentPreviewCardSize()
        frontPreview.configureSheet(
            paperSize: paper.size,
            cardSize: previewCardSize,
            cutStyle: cutStyle
        )
        backPreview.configureSheet(
            paperSize: paper.size,
            cardSize: previewCardSize,
            cutStyle: cutStyle
        )

        sheetLabel.stringValue = "Sheet \(currentSheet + 1) of \(sheetCount)"
        previousButton.isEnabled = currentSheet > 0
        nextButton.isEnabled = currentSheet + 1 < sheetCount

        let fronts = pairs.compactMap(\.front).count
        let backs = pairs.compactMap(\.back).count
        statusLabel.stringValue = "\(fronts) fronts • \(backs) backs • \(pairs.count) paired positions"
        makeButton.isEnabled = fronts > 0 || backs > 0
    }

    @objc private func makePDF() {
        let paper = PnPPaperSize.allCases[paperPopup.indexOfSelectedItem]
        let cutStyle: PnPCutStyle = cutPopup.indexOfSelectedItem == 0 ? .edgeMarks : .fullLines
        let cardSizePreset = PnPCardSizePreset.allCases[cardSizePopup.indexOfSelectedItem]

        var customCardSize: CGSize?
        if cardSizePreset == .custom {
            guard let width = Double(customWidthField.stringValue),
                  let height = Double(customHeightField.stringValue),
                  width > 0,
                  height > 0 else {
                showAlert(
                    message: "Invalid custom card size",
                    detail: "Enter positive numbers for width and height."
                )
                return
            }

            let pointsPerUnit: Double = customUnitPopup.indexOfSelectedItem == 0
                ? 72
                : 72 / 25.4
            customCardSize = CGSize(
                width: CGFloat(width * pointsPerUnit),
                height: CGFloat(height * pointsPerUnit)
            )
        }

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
                fronts: pairs.map(\.front),
                backs: pairs.map(\.back),
                outputURL: outputURL,
                paperSize: paper,
                cutStyle: cutStyle,
                cardSizePreset: cardSizePreset,
                customCardSize: customCardSize,
                duplexFlip: selectedDuplexFlip
            )
            temporaryOutputs.append(outputURL)

            let percent = Int((result.scale * 100).rounded())
            statusLabel.stringValue = "Created \(result.sheetCount) card sheet pair(s) • \(percent)% • opening Preview"
            openInPreview(outputURL)
        } catch {
            showAlert(
                message: "Could not make 9-Up PDF",
                detail: error.localizedDescription
            )
        }
    }

    private func openInPreview(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()

        if let preview = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Preview"
        ) {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: preview,
                configuration: configuration
            ) { [weak self] _, error in
                if let error {
                    DispatchQueue.main.async {
                        self?.showAlert(
                            message: "Could not open Preview",
                            detail: error.localizedDescription
                        )
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(url)
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
            .filter { url in
                url.pathExtension.lowercased() == "pdf"
                    || UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
            }

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
