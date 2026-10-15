import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import PnPCore

final class PDFOutputTests: XCTestCase {
    private func makeSourcePDF(at url: URL, count: Int) throws {
        var media = CGRect(x: 0, y: 0, width: 180, height: 252)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let context = CGContext(consumer: consumer, mediaBox: &media, nil) else {
            XCTFail("Could not create source PDF")
            return
        }

        for number in 0..<count {
            context.beginPDFPage(nil)
            let fraction = CGFloat(number) / CGFloat(max(1, count - 1))
            context.setFillColor(CGColor(red: fraction,
                                         green: 1 - fraction,
                                         blue: 0,
                                         alpha: 1))
            context.fill(media)
            context.endPDFPage()
        }
        context.closePDF()
    }

    func testIncompleteSheetCountsAndOutputPaperBounds() throws {
        for count in [1, 4, 8, 9, 10, 17] {
            let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
            defer {
                try? FileManager.default.removeItem(at: sourceURL)
                try? FileManager.default.removeItem(at: outputURL)
            }
            try makeSourcePDF(at: sourceURL, count: count)
            let cards: [PnPCardAsset?] = (0..<count).map {
                .pdfPage(url: sourceURL, pageIndex: $0)
            }
            let result = try PnPImposer.impose(
                fronts: cards,
                backs: cards,
                outputURL: outputURL,
                paperSize: .letter,
                cutStyle: .edgeMarks,
                cardSizePreset: .poker
            )
            let output = try XCTUnwrap(PDFDocument(url: outputURL))
            XCTAssertEqual(result.cardCount, count)
            XCTAssertEqual(result.sheetCount, (count + 8) / 9)
            XCTAssertEqual(output.pageCount, result.sheetCount * 2)
            for index in 0..<output.pageCount {
                let page = try XCTUnwrap(output.page(at: index))
                XCTAssertEqual(page.bounds(for: .mediaBox).width, 612, accuracy: 0.01)
                XCTAssertEqual(page.bounds(for: .mediaBox).height, 792, accuracy: 0.01)
            }
        }
    }

    private func samplePixel(from page: CGPDFPage, at point: CGPoint) throws -> (Int, Int, Int) {
        var pixels = [UInt8](repeating: 0, count: 4)
        let madeContext: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            context.translateBy(x: -point.x, y: -point.y)
            context.drawPDFPage(page)
            context.flush()
            return true
        }
        XCTAssertTrue(madeContext)
        return (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
    }

    func testGeneratedBackArtworkAppearsInMirroredSlots() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }

        var bounds = CGRect(x: 0, y: 0, width: 180, height: 252)
        let consumer = try XCTUnwrap(CGDataConsumer(url: source as CFURL))
        let drawing = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for cardIndex in 0..<9 {
            drawing.beginPDFPage(nil)
            drawing.setFillColor(CGColor(
                red: CGFloat(cardIndex) / 8,
                green: CGFloat(8 - cardIndex) / 8,
                blue: 0,
                alpha: 1
            ))
            drawing.fill(bounds)
            drawing.endPDFPage()
        }
        drawing.closePDF()

        let assets: [PnPCardAsset?] = (0..<9).map {
            .pdfPage(url: source, pageIndex: $0)
        }
        _ = try PnPImposer.impose(
            fronts: assets,
            backs: assets,
            outputURL: output,
            paperSize: .letter,
            cutStyle: .edgeMarks,
            cardSizePreset: .poker,
            duplexFlip: .longEdge
        )

        let pdf = try XCTUnwrap(CGPDFDocument(output as CFURL))
        XCTAssertEqual(pdf.numberOfPages, 2)
        let frontPage = try XCTUnwrap(pdf.page(at: 1))
        let backPage = try XCTUnwrap(pdf.page(at: 2))
        let sheet = PnPSheetLayout(cardSize: CGSize(width: 180, height: 252),
                                   sheetSize: PnPPaperSize.letter.size,
                                   cutStyle: .edgeMarks)
        let slot0 = sheet.cardFrame(0)
        let slot2 = sheet.cardFrame(2)

        let front0 = try samplePixel(from: frontPage, at: CGPoint(x: slot0.midX, y: slot0.midY))
        let back0 = try samplePixel(from: backPage, at: CGPoint(x: slot0.midX, y: slot0.midY))
        let back2 = try samplePixel(from: backPage, at: CGPoint(x: slot2.midX, y: slot2.midY))

        // Front physical slot 0 is logical card 1. Back physical slot 0 is card 3.
        // An image need not be text-extractable; sampling printed pixels checks actual placement.
        XCTAssertLessThan(front0.0, 35)
        XCTAssertGreaterThan(front0.1, 220)
        XCTAssertGreaterThan(back0.0, 35)
        XCTAssertLessThan(back0.0, 100)
        XCTAssertGreaterThan(back2.1, 220)
        XCTAssertLessThan(back2.0, 35)
    }

    func testLandscapePDFHasLandscapeMediaBoxAndMirroredBackPositions() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        try makeSourcePDF(at: sourceURL, count: 9)
        let assets: [PnPCardAsset?] = (0..<9).map {
            .pdfPage(url: sourceURL, pageIndex: $0)
        }

        for flip in PnPDuplexFlip.allCases {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".pdf")
            defer { try? FileManager.default.removeItem(at: outputURL) }

            let result = try PnPImposer.impose(
                fronts: assets,
                backs: assets,
                outputURL: outputURL,
                paperSize: .letter,
                orientation: .landscape,
                cutStyle: .edgeMarks,
                cardSizePreset: .poker,
                duplexFlip: flip
            )
            XCTAssertEqual(result.sheetCount, 1)
            let pdf = try XCTUnwrap(PDFDocument(url: outputURL))
            XCTAssertEqual(pdf.pageCount, 2)
            for index in 0..<pdf.pageCount {
                let page = try XCTUnwrap(pdf.page(at: index))
                XCTAssertEqual(page.bounds(for: .mediaBox).width, 792, accuracy: 0.01)
                XCTAssertEqual(page.bounds(for: .mediaBox).height, 612, accuracy: 0.01)
            }

            // Render actual PDF pixels to catch a mismatch between mirroredSlot
            // calculations and the artwork placed on the output back page.
            let raw = try XCTUnwrap(CGPDFDocument(outputURL as CFURL))
            let frontPage = try XCTUnwrap(raw.page(at: 1))
            let backPage = try XCTUnwrap(raw.page(at: 2))
            let sheet = PnPSheetLayout(
                cardSize: CGSize(width: 180, height: 252),
                sheetSize: PnPPaperSize.letter.size(for: .landscape),
                cutStyle: .edgeMarks
            )
            let firstSlot = sheet.cardFrame(0)
            let center = CGPoint(x: firstSlot.midX, y: firstSlot.midY)
            let frontColor = try samplePixel(from: frontPage, at: center)
            let backColor = try samplePixel(from: backPage, at: center)
            XCTAssertLessThan(frontColor.0, 35)
            XCTAssertGreaterThan(frontColor.1, 220)

            if flip == .longEdge {
                // Landscape long-edge flips rows: top-left back is card 7.
                XCTAssertGreaterThan(backColor.0, 150)
                XCTAssertLessThan(backColor.1, 115)
            } else {
                // Landscape short-edge flips columns: top-left back is card 3.
                XCTAssertGreaterThan(backColor.0, 30)
                XCTAssertLessThan(backColor.0, 105)
                XCTAssertGreaterThan(backColor.1, 150)
            }
        }
    }

    func testFrontOnlyPrintsNoBlankBackSheets() throws {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try makeSourcePDF(at: sourceURL, count: 11)
        let cards: [PnPCardAsset?] = (0..<11).map { .pdfPage(url: sourceURL, pageIndex: $0) }
        _ = try PnPImposer.impose(
            fronts: cards,
            backs: [],
            outputURL: outputURL,
            paperSize: .a4,
            cutStyle: .fullLines,
            cardSizePreset: .square
        )
        XCTAssertEqual(PDFDocument(url: outputURL)?.pageCount, 2)
    }
}
