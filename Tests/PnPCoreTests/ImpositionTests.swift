import CoreGraphics
import XCTest
@testable import PnPCore

final class ImpositionTests: XCTestCase {
    func testBuiltInCardSizesAreExact() throws {
        let poker = try XCTUnwrap(PnPCardSizePreset.poker.fixedSize)
        let bridge = try XCTUnwrap(PnPCardSizePreset.bridge.fixedSize)
        let euro = try XCTUnwrap(PnPCardSizePreset.euro.fixedSize)

        XCTAssertEqual(poker.width, 180, accuracy: 0.0001)
        XCTAssertEqual(poker.height, 252, accuracy: 0.0001)
        XCTAssertEqual(bridge.width, 162, accuracy: 0.0001)
        XCTAssertEqual(bridge.height, 252, accuracy: 0.0001)
        XCTAssertEqual(euro.width, CGFloat(59.0 * 72.0 / 25.4), accuracy: 0.0001)
        XCTAssertEqual(euro.height, CGFloat(92.0 * 72.0 / 25.4), accuracy: 0.0001)
    }

    func testAllBuiltInPresetsFitNineUpOnLetter() {
        for preset in [PnPCardSizePreset.poker, .bridge, .euro] {
            guard let cardSize = preset.fixedSize else {
                XCTFail("Missing fixed size for \(preset)")
                continue
            }
            let geometry = PnPImposer.gridGeometry(
                cardSize: cardSize,
                sheetSize: PnPPaperSize.letter.size
            )
            XCTAssertEqual(geometry.scale, 1, accuracy: 0.0001)
        }
    }

    func testSourceOrderAppendsDocuments() {
        let order = PnPImposer.sourceOrder(pageCounts: [2, 3, 1])

        XCTAssertEqual(order.map(\.document), [0, 0, 1, 1, 1, 2])
        XCTAssertEqual(order.map(\.page), [0, 1, 0, 1, 2, 0])
    }

    func testPokerCardsStayAtFullSizeOnLetter() {
        let card = CGSize(width: 180, height: 252)
        let geometry = PnPImposer.gridGeometry(cardSize: card, sheetSize: PnPPaperSize.letter.size)

        XCTAssertEqual(geometry.scale, 1, accuracy: 0.0001)
        XCTAssertEqual(geometry.gridRect.width, 540, accuracy: 0.0001)
        XCTAssertEqual(geometry.gridRect.height, 756, accuracy: 0.0001)
        XCTAssertEqual(geometry.gridRect.minX, 36, accuracy: 0.0001)
        XCTAssertEqual(geometry.gridRect.minY, 18, accuracy: 0.0001)
    }

    func testPokerCardsStayAtFullSizeOnA4() {
        let card = CGSize(width: 180, height: 252)
        let geometry = PnPImposer.gridGeometry(cardSize: card, sheetSize: PnPPaperSize.a4.size)

        XCTAssertEqual(geometry.scale, 1, accuracy: 0.0001)
    }

    func testOversizedCardsScaleUniformly() {
        let card = CGSize(width: 220, height: 300)
        let geometry = PnPImposer.gridGeometry(cardSize: card, sheetSize: PnPPaperSize.letter.size)

        XCTAssertLessThan(geometry.scale, 1)
        XCTAssertEqual(
            geometry.cardSize.width / card.width,
            geometry.cardSize.height / card.height,
            accuracy: 0.0001
        )
    }

    func testSlotsReadLeftToRightTopToBottom() {
        let geometry = PnPImposer.gridGeometry(
            cardSize: CGSize(width: 100, height: 150),
            sheetSize: CGSize(width: 400, height: 500)
        )

        let first = geometry.frame(forSlot: 0)
        let third = geometry.frame(forSlot: 2)
        let fourth = geometry.frame(forSlot: 3)

        XCTAssertEqual(first.minY, third.minY, accuracy: 0.0001)
        XCTAssertGreaterThan(first.minY, fourth.minY)
        XCTAssertLessThan(first.minX, third.minX)
    }

    func testCutPositionsOutlineThreeByThreeGrid() {
        let geometry = PnPImposer.gridGeometry(
            cardSize: CGSize(width: 100, height: 150),
            sheetSize: CGSize(width: 400, height: 500)
        )

        XCTAssertEqual(geometry.verticalCutPositions.count, 4)
        XCTAssertEqual(geometry.horizontalCutPositions.count, 4)
        XCTAssertEqual(geometry.verticalCutPositions.first, geometry.gridRect.minX)
        XCTAssertEqual(geometry.verticalCutPositions.last, geometry.gridRect.maxX)
        XCTAssertEqual(geometry.horizontalCutPositions.first, geometry.gridRect.minY)
        XCTAssertEqual(geometry.horizontalCutPositions.last, geometry.gridRect.maxY)
    }
}
