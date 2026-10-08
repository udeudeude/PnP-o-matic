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
            context.setFillColor(CGColor(red: number.isMultiple(of: 2) ? 1 : 0,
                                         green: number.isMultiple(of: 2) ? 0 : 1,
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
