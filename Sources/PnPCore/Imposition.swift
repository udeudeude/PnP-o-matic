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

public enum PnPCardSizePreset: String, CaseIterable {
    case pdfPage
    case poker
    case bridge
    case euro
    case custom

    public var displayName: String {
        switch self {
        case .pdfPage: return "Use PDF page size"
        case .poker: return "Poker — 2.5 × 3.5 in"
        case .bridge: return "Bridge — 2.25 × 3.5 in"
        case .euro: return "Euro — 59 × 92 mm"
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
            return CGSize(
                width: 59 * 72 / 25.4,
                height: 92 * 72 / 25.4
            )
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
        customCardSize: CGSize? = nil
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
            duplexFlip: .longEdge
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
        duplexFlip: PnPDuplexFlip = .longEdge
    ) throws -> PnPResult {
        let cardCount = max(fronts.count, backs.count)
        guard cardCount > 0 else {
            throw PnPError.noInput
        }

        let firstAsset = fronts.compactMap { $0 }.first ?? backs.compactMap { $0 }.first
        guard let firstAsset,
              let sourceSize = sourceSize(for: firstAsset),
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
        case .poker, .bridge, .euro:
            guard let fixedSize = cardSizePreset.fixedSize else {
                throw PnPError.invalidCardSize
            }
            requestedCardSize = fixedSize
        }

        let sheetSize = paperSize.size
        let geometry = gridGeometry(cardSize: requestedCardSize, sheetSize: sheetSize)
        guard geometry.scale > 0 else {
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
                        in: geometry.frame(forSlot: logicalSlot),
                        context: context
                    )
                }
                drawCutLines(
                    cutStyle: cutStyle,
                    geometry: geometry,
                    sheetSize: sheetSize,
                    context: context
                )
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
                        in: geometry.frame(forSlot: visualSlot),
                        context: context
                    )
                }
                drawCutLines(
                    cutStyle: cutStyle,
                    geometry: geometry,
                    sheetSize: sheetSize,
                    context: context
                )
                context.endPDFPage()
            }
        }

        context.closePDF()

        return PnPResult(
            cardCount: cardCount,
            sheetCount: sheetCount,
            scale: geometry.scale
        )
    }

    private static func sourceSize(for asset: PnPCardAsset) -> CGSize? {
        switch asset {
        case .pdfPage(let url, let pageIndex):
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: pageIndex) else {
                return nil
            }
            return page.bounds(for: .cropBox).size

        case .image(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return CGSize(width: image.width, height: image.height)
        }
    }

    private static func draw(asset: PnPCardAsset, in frame: CGRect, context: CGContext) {
        switch asset {
        case .pdfPage(let url, let pageIndex):
            guard let document = PDFDocument(url: url),
                  let page = document.page(at: pageIndex) else {
                return
            }
            draw(page: page, in: frame, context: context)

        case .image(let url):
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return
            }
            draw(image: image, in: frame, context: context)
        }
    }

    private static func draw(image: CGImage, in frame: CGRect, context: CGContext) {
        let sourceSize = CGSize(width: image.width, height: image.height)
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }

        let scale = min(frame.width / sourceSize.width, frame.height / sourceSize.height)
        let drawnSize = CGSize(
            width: sourceSize.width * scale,
            height: sourceSize.height * scale
        )
        let target = CGRect(
            x: frame.midX - drawnSize.width / 2,
            y: frame.midY - drawnSize.height / 2,
            width: drawnSize.width,
            height: drawnSize.height
        )

        context.saveGState()
        context.clip(to: frame)
        context.draw(image, in: target)
        context.restoreGState()
    }

    private static func draw(page: PDFPage, in frame: CGRect, context: CGContext) {
        let source = page.bounds(for: .cropBox)
        guard source.width > 0, source.height > 0 else { return }

        let scale = min(frame.width / source.width, frame.height / source.height)
        let drawnSize = CGSize(width: source.width * scale, height: source.height * scale)
        let origin = CGPoint(
            x: frame.midX - drawnSize.width / 2,
            y: frame.midY - drawnSize.height / 2
        )

        context.saveGState()
        context.clip(to: frame)
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -source.minX, y: -source.minY)
        page.draw(with: .cropBox, to: context)
        context.restoreGState()
    }

    private static func drawCutLines(
        cutStyle: PnPCutStyle,
        geometry: PnPGridGeometry,
        sheetSize: CGSize,
        context: CGContext
    ) {
        switch cutStyle {
        case .edgeMarks:
            drawEdgeMarks(geometry: geometry, sheetSize: sheetSize, context: context)
        case .fullLines:
            drawFullLines(geometry: geometry, sheetSize: sheetSize, context: context)
        }
    }

    private static func prepareCutLines(_ context: CGContext) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0.25, alpha: 0.8))
        context.setLineWidth(0.35)
    }

    private static func drawEdgeMarks(
        geometry: PnPGridGeometry,
        sheetSize: CGSize,
        context: CGContext
    ) {
        prepareCutLines(context)

        let gap: CGFloat = 1.5
        let bottomEnd = max(0, geometry.gridRect.minY - gap)
        let topStart = min(sheetSize.height, geometry.gridRect.maxY + gap)
        let leftEnd = max(0, geometry.gridRect.minX - gap)
        let rightStart = min(sheetSize.width, geometry.gridRect.maxX + gap)

        for x in geometry.verticalCutPositions {
            if bottomEnd > 0 {
                context.move(to: CGPoint(x: x, y: 0))
                context.addLine(to: CGPoint(x: x, y: bottomEnd))
            }
            if topStart < sheetSize.height {
                context.move(to: CGPoint(x: x, y: topStart))
                context.addLine(to: CGPoint(x: x, y: sheetSize.height))
            }
        }

        for y in geometry.horizontalCutPositions {
            if leftEnd > 0 {
                context.move(to: CGPoint(x: 0, y: y))
                context.addLine(to: CGPoint(x: leftEnd, y: y))
            }
            if rightStart < sheetSize.width {
                context.move(to: CGPoint(x: rightStart, y: y))
                context.addLine(to: CGPoint(x: sheetSize.width, y: y))
            }
        }

        context.strokePath()
        context.restoreGState()
    }

    private static func drawFullLines(
        geometry: PnPGridGeometry,
        sheetSize: CGSize,
        context: CGContext
    ) {
        prepareCutLines(context)

        for x in geometry.verticalCutPositions {
            context.move(to: CGPoint(x: x, y: 0))
            context.addLine(to: CGPoint(x: x, y: sheetSize.height))
        }

        for y in geometry.horizontalCutPositions {
            context.move(to: CGPoint(x: 0, y: y))
            context.addLine(to: CGPoint(x: sheetSize.width, y: y))
        }

        context.strokePath()
        context.restoreGState()
    }
}
