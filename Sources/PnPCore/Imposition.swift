import CoreGraphics
import Foundation
import PDFKit

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
        cutStyle: PnPCutStyle
    ) throws -> PnPResult {
        guard !inputURLs.isEmpty else {
            throw PnPError.noInput
        }

        let documents: [PDFDocument] = try inputURLs.map { url in
            guard let document = PDFDocument(url: url) else {
                throw PnPError.unreadablePDF(url)
            }
            guard document.pageCount > 0 else {
                throw PnPError.emptyPDF(url)
            }
            return document
        }

        let order = sourceOrder(pageCounts: documents.map(\.pageCount))
        guard let firstRef = order.first,
              let firstPage = documents[firstRef.document].page(at: firstRef.page) else {
            throw PnPError.noInput
        }

        let firstBounds = firstPage.bounds(for: .cropBox)
        guard firstBounds.width > 0, firstBounds.height > 0 else {
            throw PnPError.invalidCardSize
        }

        let sheetSize = paperSize.size
        let geometry = gridGeometry(cardSize: firstBounds.size, sheetSize: sheetSize)
        guard geometry.scale > 0 else {
            throw PnPError.invalidCardSize
        }

        var mediaBox = CGRect(origin: .zero, size: sheetSize)
        guard let consumer = CGDataConsumer(url: outputURL as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PnPError.cannotCreateOutput(outputURL)
        }

        for sheetStart in stride(from: 0, to: order.count, by: 9) {
            context.beginPDFPage(nil)

            for slot in 0..<9 {
                let sourceIndex = sheetStart + slot
                guard sourceIndex < order.count else { continue }

                let source = order[sourceIndex]
                guard let page = documents[source.document].page(at: source.page) else {
                    continue
                }

                draw(page: page, in: geometry.frame(forSlot: slot), context: context)
            }

            switch cutStyle {
            case .edgeMarks:
                drawEdgeMarks(geometry: geometry, sheetSize: sheetSize, context: context)
            case .fullLines:
                drawFullLines(geometry: geometry, sheetSize: sheetSize, context: context)
            }

            context.endPDFPage()
        }

        context.closePDF()

        return PnPResult(
            cardCount: order.count,
            sheetCount: (order.count + 8) / 9,
            scale: geometry.scale
        )
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
