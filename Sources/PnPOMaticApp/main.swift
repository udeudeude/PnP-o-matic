import AppKit
import PDFKit
import PnPCore
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    static let pnpCardSlot = NSPasteboard.PasteboardType("com.udeudeude.pnpomatic.card-slot")
    static let pnpCardFill = NSPasteboard.PasteboardType("com.udeudeude.pnpomatic.card-fill")
}

private func thumbnail(
    for asset: PnPCardAsset?,
    size: NSSize,
    bounds: PnPArtworkBounds = .automatic
) -> NSImage? {
    guard let asset else { return nil }

    switch asset {
    case .pdfPage(let url, let pageIndex):
        guard let document = PDFDocument(url: url),
              let page = document.page(at: pageIndex) else {
            return nil
        }
        return page.thumbnail(of: size, for: PnPImposer.resolvedPDFBox(page, choice: bounds))

    case .image(let url):
        return NSImage(contentsOf: url)
    }
}

final class ArtworkPreviewView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var fit: PnPArtworkFit = .fit { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let image, image.size.width > 0, image.size.height > 0 else { return }
        let target = PnPImposer.fittedRect(
            sourceSize: image.size,
            in: bounds,
            fit: fit
        )
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()
        image.draw(in: target, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }
}

final class CardSlotView: NSView, NSDraggingSource {
    var side: PnPCardSide = .front
    var globalIndex: Int = 0
    var onExternalDrop: ((PnPCardSide, Int, [URL]) -> Void)?
    var onMove: ((PnPCardSide, Int, Int) -> Void)?
    var onClear: ((PnPCardSide, Int) -> Void)?
    var onHover: ((Int?) -> Void)?
    var onSelect: ((PnPCardSide, Int) -> Void)?
    var onFillBegin: ((PnPCardSide, Int) -> Void)?
    var onFillVisit: ((PnPCardSide, Int) -> Void)?
    var onFillComplete: ((PnPCardSide, Int) -> Void)?
    var onFillEnd: (() -> Void)?

    private let imageView = ArtworkPreviewView()
    private let numberLabel = NSTextField(labelWithString: "")
    private let sourceLabel = NSTextField(labelWithString: "")
    private var asset: PnPCardAsset?
    private var dragStarted = false
    private var linkedHighlight = false
    private var dropHighlight = false
    private var isSelected = false
    private var isFillDragging = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.cornerRadius = 0
        layer?.borderWidth = 0.5
        layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.5).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        registerForDraggedTypes([.pnpCardSlot, .pnpCardFill, .fileURL])

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
        asset: PnPCardAsset?,
        fit: PnPArtworkFit,
        artworkBounds: PnPArtworkBounds
    ) {
        self.side = side
        self.globalIndex = globalIndex
        self.asset = asset

        numberLabel.stringValue = "#\(number)"
        imageView.image = thumbnail(for: asset, size: NSSize(width: 240, height: 320), bounds: artworkBounds)
        imageView.fit = fit
        sourceLabel.stringValue = asset?.sourceName ?? "Drop PDF / image"

        if asset == nil {
            layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.45).cgColor
        } else {
            layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        }
    }

    func setLinkedHighlight(_ value: Bool) {
        linkedHighlight = value
        updateBorder()
    }

    func setSelected(_ value: Bool) {
        isSelected = value
        updateBorder()
    }

    private func updateBorder() {
        layer?.borderWidth = isSelected || linkedHighlight || dropHighlight ? 2 : 0.5
        layer?.borderColor = (dropHighlight ? NSColor.systemGreen :
            isSelected ? NSColor.systemBlue :
            linkedHighlight ? NSColor.controlAccentColor :
            NSColor.separatorColor.withAlphaComponent(0.5)).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(globalIndex)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(nil)
    }

    @objc private func clearSlot() {
        onClear?(side, globalIndex)
    }

    // The artwork and number labels are decorative. Keep mouse selection and
    // drag initiation on the parent slot rather than on those child views.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override var acceptsFirstResponder: Bool { true }

    private func selectForKeyboardEditing() {
        onSelect?(side, globalIndex)
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        dragStarted = false
        isFillDragging = false
        selectForKeyboardEditing()
    }

    override func rightMouseDown(with event: NSEvent) {
        selectForKeyboardEditing()
        super.rightMouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        let blockedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        let isDeleteKey = event.keyCode == 51 || event.keyCode == 117
        if isSelected && isDeleteKey
            && event.modifierFlags.intersection(blockedModifiers).isEmpty {
            clearSlot()
            return
        }
        super.keyDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard asset != nil, !dragStarted else { return }
        dragStarted = true
        isFillDragging = event.modifierFlags.contains(.option)
        if isFillDragging { onFillBegin?(side, globalIndex) }

        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(
            "\(side.rawValue):\(globalIndex)",
            forType: isFillDragging ? .pnpCardFill : .pnpCardSlot
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
        isFillDragging ? .copy : .move
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        if isFillDragging { onFillEnd?() }
        isFillDragging = false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let fillPayload = sender.draggingPasteboard.string(forType: .pnpCardFill)
        let internalDrag = sender.draggingPasteboard.string(forType: .pnpCardSlot) != nil
        let externalDrag = !externalURLs(from: sender).isEmpty
        dropHighlight = fillPayload != nil || internalDrag || externalDrag
        updateBorder()
        if let fillPayload { recordFillVisit(fillPayload) }
        return fillPayload != nil || externalDrag ? .copy : internalDrag ? .move : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let payload = sender.draggingPasteboard.string(forType: .pnpCardFill) {
            recordFillVisit(payload)
            return .copy
        }
        return sender.draggingPasteboard.string(forType: .pnpCardSlot) == nil ? .copy : .move
    }

    private func recordFillVisit(_ payload: String) {
        let pieces = payload.split(separator: ":")
        guard pieces.count == 2,
              let draggingSide = PnPCardSide(rawValue: String(pieces[0])),
              draggingSide == side else { return }
        onFillVisit?(side, globalIndex)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropHighlight = false
        updateBorder()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropHighlight = false
        updateBorder()
        if let payload = sender.draggingPasteboard.string(forType: .pnpCardFill) {
            let parts = payload.split(separator: ":")
            guard parts.count == 2,
                  PnPCardSide(rawValue: String(parts[0])) == side,
                  Int(parts[1]) != nil else { return false }
            onFillComplete?(side, globalIndex)
            return true
        }

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

final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class SheetCanvasView: NSView {
    let slots: [CardSlotView]
    private var sheetLayout = PnPSheetLayout(
        cardSize: CGSize(width: 180, height: 252),
        sheetSize: PnPPaperSize.letter.size,
        cutStyle: .edgeMarks
    )

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
            heightAnchor.constraint(greaterThanOrEqualToConstant: 430)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(layout: PnPSheetLayout) {
        self.sheetLayout = layout
        needsLayout = true
        needsDisplay = true
    }

    private var pageRect: CGRect {
        let area = bounds.insetBy(dx: 8, dy: 8)
        let sheet = sheetLayout.sheetSize
        guard sheet.width > 0, sheet.height > 0 else { return area }
        let scale = min(area.width / sheet.width, area.height / sheet.height)
        return CGRect(
            x: area.midX - sheet.width * scale / 2,
            y: area.midY - sheet.height * scale / 2,
            width: sheet.width * scale,
            height: sheet.height * scale
        )
    }

    override func layout() {
        super.layout()
        let paper = pageRect
        let scale = paper.width / sheetLayout.sheetSize.width

        for slotIndex in 0..<min(9, slots.count) {
            let trim = sheetLayout.cardFrame(slotIndex)
            slots[slotIndex].frame = CGRect(
                x: paper.minX + trim.minX * scale,
                y: paper.minY + (sheetLayout.sheetSize.height - trim.maxY) * scale,
                width: trim.width * scale,
                height: trim.height * scale
            )
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let paper = pageRect
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 5
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(rect: paper).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        let border = NSBezierPath(rect: paper)
        border.lineWidth = 0.5
        border.stroke()

        let scale = paper.width / sheetLayout.sheetSize.width
        let marks = NSBezierPath()
        marks.lineWidth = 0.4
        NSColor.black.withAlphaComponent(0.72).setStroke()

        for segment in sheetLayout.cutSegments {
            let p1 = CGPoint(
                x: paper.minX + segment.start.x * scale,
                y: paper.minY + (sheetLayout.sheetSize.height - segment.start.y) * scale
            )
            let p2 = CGPoint(
                x: paper.minX + segment.end.x * scale,
                y: paper.minY + (sheetLayout.sheetSize.height - segment.end.y) * scale
            )
            marks.move(to: p1)
            marks.line(to: p2)
        }
        marks.stroke()
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

    func configureSheet(layout: PnPSheetLayout) {
        canvas.configure(layout: layout)
    }
}
final class MainWindowController: NSWindowController {
    private var deck = PnPDeck()
    private var pairs: [PnPCardPair] {
        get { deck.cards }
        set { deck.cards = newValue }
    }
    private var highlightedPairIndex: Int?
    private var selectedSlot: (side: PnPCardSide, index: Int)?
    private var fillDrag: (side: PnPCardSide, source: Int, visited: Set<Int>)?
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
    private let orientationPopup = NSPopUpButton()
    private let cutPopup = NSPopUpButton()
    private let duplexPopup = NSPopUpButton()
    private let fitPopup = NSPopUpButton()
    private let artworkBoundsPopup = NSPopUpButton()
    private let bleedPopup = NSPopUpButton()
    private let lockSwitch = NSSwitch()
    private let undoButton = NSButton(title: "Undo", target: nil, action: nil)
    private let redoButton = NSButton(title: "Redo", target: nil, action: nil)
    private let warningsLabel = NSTextField(wrappingLabelWithString: "")
    private let fillMissingButton = NSButton(
        title: "Fill Missing Backs from Previous",
        target: nil,
        action: nil
    )
    private let exactPreviewButton = NSButton(
        title: "Preview Exact PDF…",
        target: nil,
        action: nil
    )
    private var pdfPreviewController: NSWindowController?
    private var lastExactPreviewURL: URL?

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

    func cleanupOldTemporaryOutputs() {
        // Avoid deleting PDFs that Preview may still be opening after app exit.
        // Expire stale outputs when the app starts again.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PnP-o-matic", isDirectory: true)
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            if let date = values?.contentModificationDate, date < cutoff {
                try? fm.removeItem(at: url)
            }
        }
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let scroller = NSScrollView()
        scroller.translatesAutoresizingMaskIntoConstraints = false
        scroller.hasVerticalScroller = true
        scroller.autohidesScrollers = true
        scroller.drawsBackground = false
        scroller.borderType = .noBorder

        let document = FlippedDocumentView()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroller.documentView = document
        content.addSubview(scroller)

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        root.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(root)

        NSLayoutConstraint.activate([
            scroller.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroller.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroller.topAnchor.constraint(equalTo: content.topAnchor),
            scroller.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            document.widthAnchor.constraint(equalTo: scroller.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroller.contentView.heightAnchor),

            root.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            root.topAnchor.constraint(equalTo: document.topAnchor),
            root.bottomAnchor.constraint(equalTo: document.bottomAnchor),
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
        importRow.addArrangedSubview(
            NSButton(title: "Import First Half / Second Half…",
                     target: self, action: #selector(importHalves))
        )
        importRow.addArrangedSubview(
            NSButton(title: "Repeat One Back…",
                     target: self, action: #selector(importCommonBack))
        )
        let importHelp = NSTextField(
            labelWithString: "For separate PDFs, use Add Fronts and Add Backs. Pages pair by card number."
        )
        importHelp.textColor = .secondaryLabelColor
        importHelp.font = NSFont.systemFont(ofSize: 11)
        // The explanation sits below the actions so the row works on smaller Mac screens.
        root.addArrangedSubview(importRow)
        root.addArrangedSubview(importHelp)

        let previews = NSStackView()
        previews.orientation = .horizontal
        previews.alignment = .centerY
        previews.distribution = .fill
        previews.spacing = 8
        previews.addArrangedSubview(frontPreview.container)

        let pairLockControls = NSStackView()
        pairLockControls.orientation = .vertical
        pairLockControls.alignment = .centerX
        pairLockControls.spacing = 8
        pairLockControls.translatesAutoresizingMaskIntoConstraints = false

        let lockTitle = NSTextField(wrappingLabelWithString: "Lock corresponding\nfronts / backs")
        lockTitle.alignment = .center
        lockTitle.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        pairLockControls.addArrangedSubview(lockTitle)
        lockSwitch.state = .on
        lockSwitch.toolTip = "On: dragging either side moves its matching card. Off: rearrange each side independently."
        pairLockControls.addArrangedSubview(lockSwitch)
        let lockDetail = NSTextField(wrappingLabelWithString: "Move together")
        lockDetail.alignment = .center
        lockDetail.textColor = .secondaryLabelColor
        lockDetail.font = NSFont.systemFont(ofSize: 10)
        pairLockControls.addArrangedSubview(lockDetail)

        previews.addArrangedSubview(pairLockControls)
        previews.addArrangedSubview(backPreview.container)
        NSLayoutConstraint.activate([
            pairLockControls.widthAnchor.constraint(equalToConstant: 106),
            frontPreview.container.widthAnchor.constraint(equalTo: backPreview.container.widthAnchor)
        ])
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
            labelWithString: "Drop PDF/images; Option-drag an occupied card through blanks to copy-fill; Delete clears selected."
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

        options1.addArrangedSubview(NSTextField(labelWithString: "Orientation:"))
        orientationPopup.addItems(withTitles: PnPPaperOrientation.allCases.map(\.displayName))
        orientationPopup.target = self
        orientationPopup.action = #selector(previewOptionsChanged)
        options1.addArrangedSubview(orientationPopup)

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
        duplexPopup.addItems(withTitles: ["Long edge", "Short edge"])
        duplexPopup.target = self
        duplexPopup.action = #selector(duplexChanged)
        options2.addArrangedSubview(duplexPopup)

        root.addArrangedSubview(options2)

        let options3 = NSStackView()
        options3.orientation = .horizontal
        options3.alignment = .centerY
        options3.spacing = 9

        options3.addArrangedSubview(NSTextField(labelWithString: "Artwork:"))
        fitPopup.addItems(withTitles: PnPArtworkFit.allCases.map(\.displayName))
        fitPopup.target = self
        fitPopup.action = #selector(previewOptionsChanged)
        options3.addArrangedSubview(fitPopup)

        options3.addArrangedSubview(NSTextField(labelWithString: "PDF bounds:"))
        artworkBoundsPopup.addItems(withTitles: PnPArtworkBounds.allCases.map(\.displayName))
        artworkBoundsPopup.target = self
        artworkBoundsPopup.action = #selector(previewOptionsChanged)
        options3.addArrangedSubview(artworkBoundsPopup)

        options3.addArrangedSubview(NSTextField(labelWithString: "Bleed:"))
        bleedPopup.addItems(withTitles: PnPBleed.allCases.map(\.displayName))
        bleedPopup.target = self
        bleedPopup.action = #selector(previewOptionsChanged)
        options3.addArrangedSubview(bleedPopup)
        root.addArrangedSubview(options3)

        undoButton.target = self
        undoButton.action = #selector(undoEdit)
        undoButton.keyEquivalent = "z"
        undoButton.keyEquivalentModifierMask = [.command]
        redoButton.target = self
        redoButton.action = #selector(redoEdit)
        redoButton.keyEquivalent = "z"
        redoButton.keyEquivalentModifierMask = [.command, .shift]
        let editRow = NSStackView()
        editRow.orientation = .horizontal
        editRow.spacing = 8
        editRow.addArrangedSubview(undoButton)
        editRow.addArrangedSubview(redoButton)
        warningsLabel.textColor = .systemOrange
        warningsLabel.font = NSFont.systemFont(ofSize: 11)
        editRow.addArrangedSubview(warningsLabel)
        root.addArrangedSubview(editRow)

        fillMissingButton.target = self
        fillMissingButton.action = #selector(fillMissingBacks)
        fillMissingButton.toolTip = "For each gap, copy the closest earlier nonempty card back forward. Leading gaps are left blank."
        root.addArrangedSubview(fillMissingButton)

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

        exactPreviewButton.target = self
        exactPreviewButton.action = #selector(previewExactPDF)
        exactPreviewButton.isEnabled = false

        footer.addArrangedSubview(statusLabel)
        footer.addArrangedSubview(exactPreviewButton)
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
                slot.onSelect = { [weak self] side, index in
                    self?.selectedSlot = (side: side, index: index)
                    self?.updateLinkedHighlight()
                }
                slot.onExternalDrop = { [weak self] side, index, urls in
                    self?.drop(urls: urls, on: side, at: index)
                }
                slot.onMove = { [weak self] side, source, destination in
                    self?.move(side: side, from: source, to: destination)
                }
                slot.onFillBegin = { [weak self] side, index in
                    self?.fillDrag = (side: side, source: index, visited: [])
                }
                slot.onFillVisit = { [weak self] side, index in
                    guard let self, var drag = self.fillDrag,
                          drag.side == side else { return }
                    drag.visited.insert(index)
                    self.fillDrag = drag
                }
                slot.onFillComplete = { [weak self] side, index in
                    self?.completeFill(side: side, endingAt: index)
                }
                slot.onFillEnd = { [weak self] in
                    self?.fillDrag = nil
                }
                slot.onClear = { [weak self] side, index in
                    self?.clear(side: side, at: index)
                }
                slot.onHover = { [weak self] index in
                    self?.highlightedPairIndex = index
                    self?.updateLinkedHighlight()
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
        let before = deck
        let start = nextInsertionIndex(for: side)
        ensurePairCount(start + assets.count)

        for (offset, asset) in assets.enumerated() {
            set(asset: asset, side: side, at: start + offset)
        }

        currentSheet = start / 9
        trimTrailingEmptyPairs()
        registerEdit(before, title: "Add Cards")
        refresh()
    }

    private func appendAlternatingPDF(_ url: URL) {
        let assets = PnPImposer.assets(from: url)
        guard !assets.isEmpty else { return }
        let before = deck
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
        registerEdit(before, title: "Import Alternating Cards")
        refresh()
        if !assets.count.isMultiple(of: 2) {
            showAlert(message: "Odd page count",
                      detail: "The final front has no corresponding back.")
        }
    }

    private func drop(urls: [URL], on side: PnPCardSide, at index: Int) {
        let assets = urls.flatMap(PnPImposer.assets(from:))
        guard !assets.isEmpty else { return }
        let before = deck
        ensurePairCount(index + assets.count)
        for (offset, asset) in assets.enumerated() {
            set(asset: asset, side: side, at: index + offset)
        }

        trimTrailingEmptyPairs()
        registerEdit(before, title: "Replace Cards")
        refresh()
    }

    private func move(side: PnPCardSide, from source: Int, to destination: Int) {
        guard source != destination,
              pairs.indices.contains(source) else {
            return
        }

        let before = deck
        deck.move(side: side, from: source, to: destination, paired: lockSwitch.state == .on)
        registerEdit(before, title: "Rearrange Cards")
        refresh()
    }

    private func completeFill(side: PnPCardSide, endingAt index: Int) {
        guard let drag = fillDrag, drag.side == side else { return }
        var destinations = drag.visited
        destinations.insert(index)
        let before = deck
        let count = deck.copyFill(
            side: side,
            from: drag.source,
            to: destinations,
            replaceExisting: false
        )
        fillDrag = nil
        guard count > 0 else { return }
        registerEdit(before, title: "Fill \(count) Card Slots")
        refresh()
    }

    @objc private func fillMissingBacks() {
        let before = deck
        let changed = deck.fillMissingBacksFromPrevious()
        guard !changed.isEmpty else { return }
        registerEdit(before, title: "Fill \(changed.count) Missing Backs")
        refresh()
    }

    private func clear(side: PnPCardSide, at index: Int) {
        guard pairs.indices.contains(index) else { return }
        let before = deck
        if side == .front {
            pairs[index].front = nil
        } else {
            pairs[index].back = nil
        }

        trimTrailingEmptyPairs()
        registerEdit(before, title: "Clear Card")
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
            pairs.append(PnPCardPair())
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

    private var selectedOrientation: PnPPaperOrientation {
        PnPPaperOrientation.allCases[orientationPopup.indexOfSelectedItem]
    }

    private var selectedBleed: PnPBleed {
        PnPBleed.allCases[bleedPopup.indexOfSelectedItem]
    }

    private var selectedFit: PnPArtworkFit {
        PnPArtworkFit.allCases[fitPopup.indexOfSelectedItem]
    }

    private var selectedArtworkBounds: PnPArtworkBounds {
        PnPArtworkBounds.allCases[artworkBoundsPopup.indexOfSelectedItem]
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

        if let firstAsset,
           let size = PnPImposer.sourceSize(for: firstAsset, bounds: selectedArtworkBounds),
           size.width > 0, size.height > 0 {
            return size
        }

        return PnPCardSizePreset.poker.fixedSize ?? CGSize(width: 180, height: 252)
    }

    private func updateLinkedHighlight() {
        let selectedPairIndex = selectedSlot?.index
        for visualIndex in 0..<9 {
            for preview in [frontPreview, backPreview] {
                let slot = preview.slot(at: visualIndex)
                slot.setSelected(
                    selectedSlot?.side == slot.side
                    && selectedSlot?.index == slot.globalIndex
                )
                slot.setLinkedHighlight(
                    (highlightedPairIndex != nil && slot.globalIndex == highlightedPairIndex)
                    || (selectedPairIndex != nil && slot.globalIndex == selectedPairIndex)
                )
            }
        }
    }

    private func refresh() {
        let start = currentSheet * 9
        if let selectedSlot, !(start..<(start + 9)).contains(selectedSlot.index) {
            self.selectedSlot = nil
        }
        let flip = selectedDuplexFlip

        for visualSlot in 0..<9 {
            let frontLogicalSlot = visualSlot
            let frontIndex = start + frontLogicalSlot
            let frontAsset = pairs.indices.contains(frontIndex) ? pairs[frontIndex].front : nil
            frontPreview.slot(at: visualSlot).configure(
                side: .front,
                globalIndex: frontIndex,
                number: frontIndex + 1,
                asset: frontAsset,
                fit: selectedFit,
                artworkBounds: selectedArtworkBounds
            )

            let backLogicalSlot = PnPImposer.mirroredSlot(
                visualSlot, flip: flip, orientation: selectedOrientation
            )
            let backIndex = start + backLogicalSlot
            let backAsset = pairs.indices.contains(backIndex) ? pairs[backIndex].back : nil
            backPreview.slot(at: visualSlot).configure(
                side: .back,
                globalIndex: backIndex,
                number: backIndex + 1,
                asset: backAsset,
                fit: selectedFit,
                artworkBounds: selectedArtworkBounds
            )
        }

        let arrangement: String
        let mirrorsColumns = (flip == .longEdge) == (selectedOrientation == .portrait)
        if mirrorsColumns {
            arrangement = "Back sheet: 3–2–1 / 6–5–4 / 9–8–7"
        } else {
            arrangement = "Back sheet: 7–8–9 / 4–5–6 / 1–2–3"
        }
        backPreview.detailLabel.stringValue = arrangement

        let paper = PnPPaperSize.allCases[paperPopup.indexOfSelectedItem]
        let cutStyle: PnPCutStyle = cutPopup.indexOfSelectedItem == 0 ? .edgeMarks : .fullLines
        let previewCardSize = currentPreviewCardSize()
        let sheetLayout = PnPSheetLayout(
            cardSize: previewCardSize,
            sheetSize: paper.size(for: selectedOrientation),
            cutStyle: cutStyle,
            bleed: selectedBleed.points
        )
        frontPreview.configureSheet(layout: sheetLayout)
        backPreview.configureSheet(layout: sheetLayout)
        updateLinkedHighlight()

        sheetLabel.stringValue = "Sheet \(currentSheet + 1) of \(sheetCount)"
        let unmatched = !deck.cards.compactMap(\.back).isEmpty
            && !deck.cards.compactMap(\.front).isEmpty
        let missingBacks = unmatched ? deck.missingBacks : []
        let missingFronts = unmatched ? deck.missingFronts : []
        var notices: [String] = []
        if !missingBacks.isEmpty { notices.append("Missing backs: \(missingBacks.prefix(8).map(String.init).joined(separator: ", "))") }
        if !missingFronts.isEmpty { notices.append("Missing fronts: \(missingFronts.prefix(8).map(String.init).joined(separator: ", "))") }
        if sheetLayout.geometry.scale < 0.999 {
            notices.append("Scaled to \(Int(sheetLayout.geometry.scale * 100))% to fit sheet")
        } else {
            let grid = sheetLayout.geometry.gridRect
            let sheet = sheetLayout.sheetSize
            let narrowestMargin = min(
                grid.minX, grid.minY, sheet.width - grid.maxX, sheet.height - grid.maxY
            )
            if narrowestMargin < 18 {
                notices.append("Narrow print margins: consider larger paper")
            }
        }
        warningsLabel.stringValue = notices.joined(separator: "   •   ")
        // Only offer fill when at least one gap has an earlier actual back.
        var previousBack: PnPCardAsset?
        var fillable = false
        for card in deck.cards {
            if let back = card.back {
                previousBack = back
            } else if card.front != nil && previousBack != nil {
                fillable = true
            }
        }
        fillMissingButton.isEnabled = fillable
        fillMissingButton.isHidden = !fillable
        undoButton.isEnabled = window?.undoManager?.canUndo ?? false
        redoButton.isEnabled = window?.undoManager?.canRedo ?? false
        previousButton.isEnabled = currentSheet > 0
        nextButton.isEnabled = currentSheet + 1 < sheetCount

        let fronts = pairs.compactMap(\.front).count
        let backs = pairs.compactMap(\.back).count
        statusLabel.stringValue = "\(fronts) fronts • \(backs) backs • \(pairs.count) paired positions"
        makeButton.isEnabled = fronts > 0 || backs > 0
        exactPreviewButton.isEnabled = makeButton.isEnabled
    }

    /// This is the single export path for both exact preview and final output.
    /// The preview displays this PDF itself, not a reconstructed approximation.
    private func renderPDF() throws -> (url: URL, result: PnPResult) {
        let paper = PnPPaperSize.allCases[paperPopup.indexOfSelectedItem]
        let cutStyle: PnPCutStyle = cutPopup.indexOfSelectedItem == 0 ? .edgeMarks : .fullLines
        let cardSizePreset = PnPCardSizePreset.allCases[cardSizePopup.indexOfSelectedItem]

        var customCardSize: CGSize?
        if cardSizePreset == .custom {
            guard let width = Double(customWidthField.stringValue),
                  let height = Double(customHeightField.stringValue),
                  width.isFinite, height.isFinite,
                  width > 0, height > 0 else {
                throw PnPError.invalidCardSize
            }
            let pointsPerUnit: Double = customUnitPopup.indexOfSelectedItem == 0
                ? 72 : 72 / 25.4
            customCardSize = CGSize(
                width: CGFloat(width * pointsPerUnit),
                height: CGFloat(height * pointsPerUnit)
            )
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PnP-o-matic", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )

        let outputURL = directory.appendingPathComponent(
            "PnP-o-matic-\(UUID().uuidString).pdf"
        )
        do {
            let result = try PnPImposer.impose(
                fronts: pairs.map(\.front),
                backs: pairs.map(\.back),
                outputURL: outputURL,
                paperSize: paper,
                orientation: selectedOrientation,
                cutStyle: cutStyle,
                cardSizePreset: cardSizePreset,
                customCardSize: customCardSize,
                duplexFlip: selectedDuplexFlip,
                fit: selectedFit,
                artworkBounds: selectedArtworkBounds,
                bleed: selectedBleed
            )
            temporaryOutputs.append(outputURL)
            return (outputURL, result)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    @objc private func previewExactPDF() {
        do {
            let output = try renderPDF()
            guard let document = PDFDocument(url: output.url), document.pageCount > 0 else {
                throw PnPError.unreadablePDF(output.url)
            }

            let previewWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 740, height: 850),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered, defer: false
            )
            previewWindow.title = "Exact Print Preview — PnP-o-matic"
            previewWindow.minSize = NSSize(width: 450, height: 450)
            previewWindow.center()

            let pdfView = PDFView(frame: .zero)
            pdfView.translatesAutoresizingMaskIntoConstraints = false
            pdfView.document = document
            pdfView.displayMode = .singlePageContinuous
            pdfView.autoScales = true
            pdfView.displaysPageBreaks = true
            pdfView.backgroundColor = .windowBackgroundColor

            let hint = NSTextField(
                labelWithString: "Actual generated PDF • \(document.pageCount) pages • front/back sheets alternate. Print at 100%."
            )
            hint.textColor = .secondaryLabelColor
            hint.font = NSFont.systemFont(ofSize: 11)

            let openButton = NSButton(
                title: "Open in Preview",
                target: self,
                action: #selector(openExactPreviewInPreview)
            )
            let toolbar = NSStackView(views: [hint, openButton])
            toolbar.orientation = .horizontal
            toolbar.spacing = 12
            toolbar.edgeInsets = NSEdgeInsets(top: 9, left: 12, bottom: 9, right: 12)
            toolbar.translatesAutoresizingMaskIntoConstraints = false

            guard let content = previewWindow.contentView else { return }
            content.addSubview(pdfView)
            content.addSubview(toolbar)
            NSLayoutConstraint.activate([
                toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                toolbar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                toolbar.topAnchor.constraint(equalTo: content.topAnchor),
                pdfView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                pdfView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                pdfView.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
                pdfView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
            ])
            lastExactPreviewURL = output.url
            pdfPreviewController = NSWindowController(window: previewWindow)
            pdfPreviewController?.showWindow(self)
            previewWindow.makeKeyAndOrderFront(self)
        } catch {
            showAlert(message: "Could not preview PDF", detail: error.localizedDescription)
        }
    }

    @objc private func openExactPreviewInPreview() {
        guard let lastExactPreviewURL else { return }
        openInPreview(lastExactPreviewURL)
    }

    @objc private func makePDF() {
        let hasFronts = deck.cards.contains { $0.front != nil }
        let hasBacks = deck.cards.contains { $0.back != nil }
        if hasFronts && hasBacks && (!deck.missingBacks.isEmpty || !deck.missingFronts.isEmpty) {
            let alert = NSAlert()
            alert.messageText = "Unmatched card fronts and backs"
            alert.informativeText = "\(deck.missingBacks.count) missing backs and \(deck.missingFronts.count) missing fronts. Blank positions will be printed. Continue?"
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        do {
            let output = try renderPDF()
            let percent = Int((output.result.scale * 100).rounded())
            statusLabel.stringValue = "Created \(output.result.sheetCount) card sheet pair(s) • \(percent)% • opening Preview"
            openInPreview(output.url)
        } catch {
            showAlert(message: "Could not make 9-Up PDF", detail: error.localizedDescription)
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

    @objc private func undoEdit() {
        window?.undoManager?.undo()
        refresh()
    }

    @objc private func redoEdit() {
        window?.undoManager?.redo()
        refresh()
    }

    private func registerEdit(_ prior: PnPDeck, title: String) {
        guard prior != deck else { return }
        window?.undoManager?.registerUndo(withTarget: self) { target in
            target.restoreDeck(prior, title: title)
        }
        window?.undoManager?.setActionName(title)
    }

    private func restoreDeck(_ snapshot: PnPDeck, title: String) {
        let prior = deck
        deck = snapshot
        registerEdit(prior, title: title)
        currentSheet = min(currentSheet, sheetCount - 1)
        refresh()
    }

    @objc private func importHalves() {
        chooseOnePDF(message: "First half fronts, second half matching backs") { [weak self] url in
            guard let self else { return }
            let assets = PnPImposer.assets(from: url)
            let before = self.deck
            self.deck.addHalves(assets)
            self.registerEdit(before, title: "Import Halves")
            self.currentSheet = max(0, (self.deck.cards.count - 1) / 9)
            self.refresh()
            if !assets.count.isMultiple(of: 2) {
                self.showAlert(message: "Odd page count",
                               detail: "This file has an extra front without a matching back.")
            }
        }
    }

    @objc private func importCommonBack() {
        chooseAssets(message: "Choose one back image or one-page PDF") { [weak self] urls in
            guard let self, let first = urls.first,
                  let asset = PnPImposer.assets(from: first).first else { return }
            let before = self.deck
            self.deck.repeatBack(asset)
            self.registerEdit(before, title: "Repeat Common Back")
            self.refresh()
        }
    }

    private func chooseOnePDF(message: String, completion: @escaping (URL) -> Void) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.message = message
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.beginSheetModal(for: window) { result in
            if result == .OK, let url = panel.url { completion(url) }
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
        controller.cleanupOldTemporaryOutputs()
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
