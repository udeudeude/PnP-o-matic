import CoreGraphics
import Foundation
import PDFKit
import ImageIO


public enum PnPCardSide: String, Equatable {
    case front
    case back
}

public enum PnPDuplexFlip: String, CaseIterable {
    case longEdge
    case shortEdge

    public var displayName: String {
        switch self {
        case .longEdge: return "Long edge"
        case .shortEdge: return "Short edge"
        }
    }
}

public enum PnPCardAsset: Equatable {
    case pdfPage(url: URL, pageIndex: Int)
    case image(url: URL)

    public var sourceName: String {
        switch self {
        case .pdfPage(let url, let pageIndex):
            return "\(url.lastPathComponent) • p. \(pageIndex + 1)"
        case .image(let url):
            return url.lastPathComponent
        }
    }
}

public enum PnPArtworkFit: String, CaseIterable {
    case fit
    case fill

    public var displayName: String {
        self == .fit ? "Fit whole artwork" : "Fill card (crop excess)"
    }
}

public enum PnPArtworkBounds: String, CaseIterable {
    case automatic
    case trim
    case crop
    case bleed
    case media

    public var displayName: String {
        switch self {
        case .automatic: return "Automatic (TrimBox if present)"
        case .trim: return "TrimBox"
        case .crop: return "CropBox"
        case .bleed: return "BleedBox"
        case .media: return "MediaBox"
        }
    }

    public var pdfBox: PDFDisplayBox {
        switch self {
        case .automatic, .trim: return .trimBox
        case .crop: return .cropBox
        case .bleed: return .bleedBox
        case .media: return .mediaBox
        }
    }
}

public enum PnPBleed: String, CaseIterable {
    case none
    case threeMillimeters

    public var points: CGFloat {
        switch self {
        case .none: return 0
        case .threeMillimeters: return 3 * 72 / 25.4
        }
    }

    public var displayName: String {
        switch self {
        case .none: return "None"
        case .threeMillimeters: return "3 mm (with gutters)"
        }
    }
}

public enum PnPCardSizePreset: String, CaseIterable {
    case pdfPage
    case poker
    case bridge
    case euro
    case tarot
    case square
    case custom

    public var displayName: String {
        switch self {
        case .pdfPage: return "Use PDF page size"
        case .poker: return "Poker — 2.5 × 3.5 in"
        case .bridge: return "Bridge — 2.25 × 3.5 in"
        case .euro: return "Euro — 59 × 92 mm"
        case .tarot: return "Tarot — 2.75 × 4.75 in"
        case .square: return "Square — 2.5 × 2.5 in"
        case .custom: return "Custom…"
        }
    }

    public var fixedSize: CGSize? {
        switch self {
        case .pdfPage, .custom:
            return nil
        case .poker:
            return CGSize(width: 2.5 * 72, height: 3.5 * 72)
        case .bridge:
            return CGSize(width: 2.25 * 72, height: 3.5 * 72)
        case .euro:
            return CGSize(width: 59 * 72 / 25.4, height: 92 * 72 / 25.4)
        case .tarot:
            return CGSize(width: 2.75 * 72, height: 4.75 * 72)
        case .square:
            return CGSize(width: 2.5 * 72, height: 2.5 * 72)
        }
    }
}

public enum PnPCutStyle: String, CaseIterable {
    case edgeMarks
    case fullLines
}

public enum PnPPaperSize: String, CaseIterable {
    case letter
    case a4

    public var displayName: String {
        switch self {
        case .letter: return "US Letter"
        case .a4: return "A4"
        }
    }

    public var size: CGSize {
        switch self {
        case .letter:
            return CGSize(width: 612, height: 792)
        case .a4:
            return CGSize(width: 595.2756, height: 841.8898)
        }
    }
}

public struct PnPResult: Equatable {
    public let cardCount: Int
    public let sheetCount: Int
    public let scale: CGFloat
}

public struct PnPGridGeometry: Equatable {
    public let cardSize: CGSize
    public let gridRect: CGRect
    public let scale: CGFloat

    public func frame(forSlot slot: Int) -> CGRect {
        precondition((0..<9).contains(slot))
        let column = slot % 3
        let rowFromTop = slot / 3
        return CGRect(
            x: gridRect.minX + CGFloat(column) * cardSize.width,
            y: gridRect.minY + CGFloat(2 - rowFromTop) * cardSize.height,
            width: cardSize.width,
            height: cardSize.height
        )
    }

    public var verticalCutPositions: [CGFloat] {
        (0...3).map { gridRect.minX + CGFloat($0) * cardSize.width }
    }

    public var horizontalCutPositions: [CGFloat] {
        (0...3).map { gridRect.minY + CGFloat($0) * cardSize.height }
    }
}

public enum PnPError: LocalizedError {
    case noInput
    case unreadablePDF(URL)
    case emptyPDF(URL)
    case invalidCardSize
    case cannotCreateOutput(URL)

    public var errorDescription: String? {
        switch self {
        case .noInput:
            return "Add at least one PDF first."
        case .unreadablePDF(let url):
            return "Could not open PDF: \(url.lastPathComponent)"
        case .emptyPDF(let url):
            return "The PDF has no pages: \(url.lastPathComponent)"
        case .invalidCardSize:
            return "The first PDF page has an invalid card size."
        case .cannotCreateOutput(let url):
            return "Could not create output PDF: \(url.path)"
        }
    }
}

public enum PnPImposer {
    public static func mirroredSlot(_ slot: Int, flip: PnPDuplexFlip) -> Int {
        precondition((0..<9).contains(slot))
        let row = slot / 3
        let column = slot % 3

        switch flip {
        case .longEdge:
            return row * 3 + (2 - column)
        case .shortEdge:
            return (2 - row) * 3 + column
        }
    }

    public static func assets(from url: URL) -> [PnPCardAsset] {
        if url.pathExtension.lowercased() == "pdf",
           let document = PDFDocument(url: url) {
            return (0..<document.pageCount).map {
                .pdfPage(url: url, pageIndex: $0)
            }
        }

        guard CGImageSourceCreateWithURL(url as CFURL, nil) != nil else {
            return []
        }
        return [.image(url: url)]
    }

    public static func sourceOrder(pageCounts: [Int]) -> [(document: Int, page: Int)] {
        var result: [(document: Int, page: Int)] = []
        for (documentIndex, count) in pageCounts.enumerated() where count > 0 {
            for pageIndex in 0..<count {
                result.append((document: documentIndex, page: pageIndex))
            }
        }
        return result
    }

    public static func gridGeometry(cardSize: CGSize, sheetSize: CGSize) -> PnPGridGeometry {
        guard cardSize.width > 0, cardSize.height > 0 else {
            return PnPGridGeometry(cardSize: .zero, gridRect: .zero, scale: 0)
        }

        let naturalGrid = CGSize(width: cardSize.width * 3, height: cardSize.height * 3)
        let scale = min(
            1,
            sheetSize.width / naturalGrid.width,
            sheetSize.height / naturalGrid.height
        )
        let imposedCard = CGSize(width: cardSize.width * scale, height: cardSize.height * scale)
        let imposedGrid = CGSize(width: imposedCard.width * 3, height: imposedCard.height * 3)
        let origin = CGPoint(
            x: (sheetSize.width - imposedGrid.width) / 2,
            y: (sheetSize.height - imposedGrid.height) / 2
        )

        return PnPGridGeometry(
            cardSize: imposedCard,
            gridRect: CGRect(origin: origin, size: imposedGrid),
            scale: scale
        )
    }

    public static func impose(
        inputURLs: [URL],
        outputURL: URL,
        paperSize: PnPPaperSize,
        cutStyle: PnPCutStyle,
        cardSizePreset: PnPCardSizePreset = .pdfPage,
        customCardSize: CGSize? = nil,
        fit: PnPArtworkFit = .fit,
        artworkBounds: PnPArtworkBounds = .automatic,
        bleed: PnPBleed = .none
    ) throws -> PnPResult {
        guard !inputURLs.isEmpty else {
            throw PnPError.noInput
        }

        let fronts = inputURLs.flatMap { assets(from: $0) }.map(Optional.some)
        return try impose(
            fronts: fronts,
            backs: [],
            outputURL: outputURL,
            paperSize: paperSize,
            cutStyle: cutStyle,
            cardSizePreset: cardSizePreset,
            customCardSize: customCardSize,
            duplexFlip: .longEdge,
            fit: fit,
            artworkBounds: artworkBounds,
            bleed: bleed
        )
    }

    public static func impose(
        fronts: [PnPCardAsset?],
        backs: [PnPCardAsset?],
        outputURL: URL,
        paperSize: PnPPaperSize,
        cutStyle: PnPCutStyle,
        cardSizePreset: PnPCardSizePreset = .poker,
        customCardSize: CGSize? = nil,
        duplexFlip: PnPDuplexFlip = .longEdge,
        fit: PnPArtworkFit = .fit,
        artworkBounds: PnPArtworkBounds = .automatic,
        bleed: PnPBleed = .none
    ) throws -> PnPResult {
        let cardCount = max(fronts.count, backs.count)
        guard cardCount > 0 else {
            throw PnPError.noInput
        }

        let firstAsset = fronts.compactMap { $0 }.first ?? backs.compactMap { $0 }.first
        guard let firstAsset,
              let sourceSize = sourceSize(for: firstAsset, bounds: artworkBounds),
              sourceSize.width > 0,
              sourceSize.height > 0 else {
            throw PnPError.invalidCardSize
        }

        let requestedCardSize: CGSize
        switch cardSizePreset {
        case .pdfPage:
            requestedCardSize = sourceSize
        case .custom:
            guard let customCardSize,
                  customCardSize.width > 0,
                  customCardSize.height > 0 else {
                throw PnPError.invalidCardSize
            }
            requestedCardSize = customCardSize
        case .poker, .bridge, .euro, .tarot, .square:
            guard let fixedSize = cardSizePreset.fixedSize else {
                throw PnPError.invalidCardSize
            }
            requestedCardSize = fixedSize
        }

        let sheetSize = paperSize.size
        let layout = PnPSheetLayout(
            cardSize: requestedCardSize,
            sheetSize: sheetSize,
            cutStyle: cutStyle,
            bleed: bleed.points
        )
        guard layout.geometry.scale > 0 else {
            throw PnPError.invalidCardSize
        }

        var mediaBox = CGRect(origin: .zero, size: sheetSize)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PnPError.cannotCreateOutput(outputURL)
        }

        let sheetCount = (cardCount + 8) / 9
        let hasFronts = fronts.contains { $0 != nil }
        let hasBacks = backs.contains { $0 != nil }

        for sheet in 0..<sheetCount {
            let sheetStart = sheet * 9

            if hasFronts {
                context.beginPDFPage(nil)
                for logicalSlot in 0..<9 {
                    let cardIndex = sheetStart + logicalSlot
                    guard fronts.indices.contains(cardIndex),
                          let asset = fronts[cardIndex] else {
                        continue
                    }
                    draw(
                        asset: asset,
                        in: layout.cardFrame(logicalSlot),
                        bleed: layout.bleed,
                        fit: fit,
                        bounds: artworkBounds,
                        context: context
                    )
                }
                drawCutLines(layout: layout, context: context)
                context.endPDFPage()
            }

            if hasBacks {
                context.beginPDFPage(nil)
                for logicalSlot in 0..<9 {
                    let cardIndex = sheetStart + logicalSlot
                    guard backs.indices.contains(cardIndex),
                          let asset = backs[cardIndex] else {
                        continue
                    }
                    let visualSlot = mirroredSlot(logicalSlot, flip: duplexFlip)
                    draw(
                        asset: asset,
                        in: layout.cardFrame(visualSlot),
                        bleed: layout.bleed,
                        fit: fit,
                        bounds: artworkBounds,
                        context: context
                    )
                }
                drawCutLines(layout: layout, context: context)
                context.endPDFPage()
            }
        }

        context.closePDF()

        return PnPResult(
            cardCount: cardCount,
            sheetCount: sheetCount,
            scale: layout.geometry.scale
        )
    }

    public static func resolvedPDFBox(_ page: PDFPage, choice: PnPArtworkBounds) -> PDFDisplayBox {
        guard choice == .automatic else { return choice.pdfBox }
        let trim = page.bounds(for: .trimBox)
        let crop = page.bounds(for: .cropBox)
        // PDFKit may synthesize a TrimBox when the source does not contain one.
        let distinct = trim.width > 0 && trim.height > 0
            && trim.width <= crop.width && trim.height <= crop.height
            && (abs(trim.width - crop.width) > 0.5 || abs(trim.height - crop.height) > 0.5)
        return distinct ? .trimBox : .cropBox
    }

    public static func sourceSize(
        for asset: PnPCardAsset,
        bounds: PnPArtworkBounds = .automatic
    ) -> CGSize? {
        switch asset {
        case .pdfPage(let url, let pageIndex):
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: pageIndex) else { return nil }
            return page.bounds(for: resolvedPDFBox(page, choice: bounds)).size
        case .image(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let dpiX = (props?[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 300
            let dpiY = (props?[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 300
            guard dpiX > 0 && dpiY > 0 else { return nil }
            return CGSize(
                width: CGFloat(Double(image.width) * 72 / dpiX),
                height: CGFloat(Double(image.height) * 72 / dpiY)
            )
        }
    }

    /// The same aspect-ratio transform is used for both PDF and bitmap sources.
    public static func fittedRect(
        sourceSize: CGSize, in frame: CGRect, fit: PnPArtworkFit
    ) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return .zero }
        let sx = frame.width / sourceSize.width
        let sy = frame.height / sourceSize.height
        let scale = fit == .fit ? min(sx, sy) : max(sx, sy)
        let size = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    private static func draw(
        asset: PnPCardAsset,
        in frame: CGRect,
        bleed: CGFloat,
        fit: PnPArtworkFit,
        bounds: PnPArtworkBounds,
        context: CGContext
    ) {
        let imageFrame = frame.insetBy(dx: -bleed, dy: -bleed)

        switch asset {
        case .pdfPage(let url, let pageIndex):
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: pageIndex) else { return }
            let sourceBox = resolvedPDFBox(page, choice: bounds)
            let trim = page.bounds(for: sourceBox)
            let drawingBox: PDFDisplayBox = bleed > 0 ? .bleedBox : sourceBox
            let source = page.bounds(for: drawingBox)
            guard trim.width > 0, trim.height > 0 else { return }

            let target = fittedRect(sourceSize: trim.size, in: frame, fit: fit)
            let scale = target.width / trim.width
            context.saveGState()
            context.clip(to: imageFrame)
            context.translateBy(x: target.minX - trim.minX * scale, y: target.minY - trim.minY * scale)
            context.scaleBy(x: scale, y: scale)
            // The selected drawing box retains real bleed beyond the trim rectangle.
            page.draw(with: source.width > 0 && source.height > 0 ? drawingBox : sourceBox, to: context)
            context.restoreGState()

        case .image(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
            let size = CGSize(width: image.width, height: image.height)
            let target = fittedRect(sourceSize: size, in: imageFrame, fit: fit)
            context.saveGState()
            context.clip(to: imageFrame)
            context.draw(image, in: target)
            context.restoreGState()
        }
    }

    private static func drawCutLines(layout: PnPSheetLayout, context: CGContext) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.25, alpha: 0.8))
        context.setLineWidth(0.35)
        for segment in layout.cutSegments {
            context.move(to: segment.start)
            context.addLine(to: segment.end)
        }
        context.strokePath()
        context.restoreGState()
    }
}
