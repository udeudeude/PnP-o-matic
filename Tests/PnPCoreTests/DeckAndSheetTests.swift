import CoreGraphics
import Foundation
import XCTest
@testable import PnPCore

final class DeckAndSheetTests: XCTestCase {
    private func asset(_ page: Int) -> PnPCardAsset {
        .pdfPage(url: URL(fileURLWithPath: "/tmp/cards.pdf"), pageIndex: page)
    }

    func testTarotAndSquarePresets() throws {
        let tarot = try XCTUnwrap(PnPCardSizePreset.tarot.fixedSize)
        let square = try XCTUnwrap(PnPCardSizePreset.square.fixedSize)
        XCTAssertEqual(tarot.width, 198, accuracy: 0.0001)
        XCTAssertEqual(tarot.height, 342, accuracy: 0.0001)
        XCTAssertEqual(square.width, 180, accuracy: 0.0001)
        XCTAssertEqual(square.height, 180, accuracy: 0.0001)
    }

    func testTarotNineUpWarnsByScaling() throws {
        let tarot = try XCTUnwrap(PnPCardSizePreset.tarot.fixedSize)
        for paper in PnPPaperSize.allCases {
            let layout = PnPSheetLayout(cardSize: tarot, sheetSize: paper.size, cutStyle: .edgeMarks)
            XCTAssertLessThan(layout.geometry.scale, 1)
        }
    }

    func testSquareFitsAtHundredPercent() throws {
        let square = try XCTUnwrap(PnPCardSizePreset.square.fixedSize)
        for paper in PnPPaperSize.allCases {
            let layout = PnPSheetLayout(cardSize: square, sheetSize: paper.size, cutStyle: .edgeMarks)
            XCTAssertEqual(layout.geometry.scale, 1, accuracy: 0.0001)
        }
    }

    func testPreviewAndExportUseSameTrimSegments() {
        let card = CGSize(width: 180, height: 252)
        for cut in PnPCutStyle.allCases {
            let layout = PnPSheetLayout(cardSize: card, sheetSize: PnPPaperSize.letter.size, cutStyle: cut)
            XCTAssertEqual(layout.cutSegments.count, cut == .edgeMarks ? 16 : 8)
            XCTAssertEqual(layout.cardFrame(0).origin.x, 36, accuracy: 0.001)
        }
    }

    func testBleedReservesGuttersWithoutOverlap() {
        let layout = PnPSheetLayout(
            cardSize: CGSize(width: 180, height: 252),
            sheetSize: PnPPaperSize.letter.size,
            cutStyle: .edgeMarks,
            bleed: PnPBleed.threeMillimeters.points
        )
        XCTAssertGreaterThan(layout.bleed, 0)
        XCTAssertLessThan(layout.geometry.scale, 1)
        for a in 0..<9 {
            for b in (a + 1)..<9 {
                XCTAssertFalse(layout.artworkFrame(a).intersects(layout.artworkFrame(b)),
                               "Bleed artworks overlap: \(a) \(b)")
            }
        }
        XCTAssertTrue(layout.cutSegments.count > 16)
    }

    func testFitAndFillPreserveAspectWithoutStretching() {
        let source = CGSize(width: 100, height: 100)
        let target = CGRect(x: 0, y: 0, width: 180, height: 252)
        let fitted = PnPImposer.fittedRect(sourceSize: source, in: target, fit: .fit)
        let filled = PnPImposer.fittedRect(sourceSize: source, in: target, fit: .fill)
        XCTAssertEqual(fitted.width, 180, accuracy: 0.001)
        XCTAssertEqual(filled.height, 252, accuracy: 0.001)
        XCTAssertEqual(fitted.width, fitted.height, accuracy: 0.001)
        XCTAssertEqual(filled.width, filled.height, accuracy: 0.001)
    }

    func testSeparateImportsPairByIndex() {
        var deck = PnPDeck()
        deck.append([asset(0), asset(1), asset(2)], side: .front)
        deck.append([asset(10), asset(11)], side: .back)
        XCTAssertEqual(deck.cards.count, 3)
        XCTAssertEqual(deck.cards[0].back, asset(10))
        XCTAssertEqual(deck.cards[1].back, asset(11))
        XCTAssertEqual(deck.missingBacks, [3])
        XCTAssertTrue(deck.missingFronts.isEmpty)
    }

    func testAlternatingImportAndOddLastPage() {
        var deck = PnPDeck()
        deck.addAlternating([asset(0), asset(1), asset(2), asset(3), asset(4)])
        XCTAssertEqual(deck.cards.count, 3)
        XCTAssertEqual(deck.cards[0].front, asset(0))
        XCTAssertEqual(deck.cards[0].back, asset(1))
        XCTAssertEqual(deck.cards[1].front, asset(2))
        XCTAssertEqual(deck.cards[1].back, asset(3))
        XCTAssertEqual(deck.missingBacks, [3])
    }

    func testHalvesImport() {
        var deck = PnPDeck()
        deck.addHalves((0..<6).map(asset))
        XCTAssertEqual(deck.cards.count, 3)
        XCTAssertEqual(deck.cards[0].front, asset(0))
        XCTAssertEqual(deck.cards[0].back, asset(3))
        XCTAssertEqual(deck.cards[2].back, asset(5))
    }

    func testCommonBackAndProtectedExistingBack() {
        var deck = PnPDeck()
        deck.addAlternating([asset(0), asset(1), asset(2)])
        deck.repeatBack(asset(99))
        XCTAssertEqual(deck.cards[0].back, asset(1))
        XCTAssertEqual(deck.cards[1].back, asset(99))
    }

    func testLockedAndUnlockedRearranging() {
        let original = PnPDeck(cards: [
            PnPCardPair(front: asset(0), back: asset(10)),
            PnPCardPair(front: asset(1), back: asset(11)),
            PnPCardPair(front: asset(2), back: asset(12))
        ])
        var locked = original
        locked.move(side: .front, from: 0, to: 2, paired: true)
        XCTAssertEqual(locked.cards[2].front, asset(0))
        XCTAssertEqual(locked.cards[2].back, asset(10))

        var unlocked = original
        unlocked.move(side: .front, from: 0, to: 2, paired: false)
        XCTAssertEqual(unlocked.cards[2].front, asset(0))
        XCTAssertEqual(unlocked.cards[2].back, asset(12))
    }

    func testSnapshotRestoreForUndo() {
        var deck = PnPDeck(cards: [PnPCardPair(front: asset(0), back: asset(1))])
        let before = deck
        deck.put(asset(10), side: .back, at: 0)
        XCTAssertNotEqual(deck, before)
        deck = before
        XCTAssertEqual(deck.cards[0].back, asset(1))
    }
}
