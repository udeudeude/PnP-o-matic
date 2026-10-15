import Foundation
import XCTest
@testable import PnPCore

final class ProjectFileTests: XCTestCase {
    private func fixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pnp-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        return directory
    }

    private func touch(_ url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data([1, 2, 3]).write(to: url)
    }

    func testRoundTripPreservesOrderingRepeatedArtworkAndPrintSettings() throws {
        let folder = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let projectURL = folder.appendingPathComponent("Cards.pnpomatic")
        let fronts = folder.appendingPathComponent("art/fronts.pdf")
        let back = folder.appendingPathComponent("art/shared.png")
        try touch(fronts)
        try touch(back)

        let deck = PnPDeck(cards: [
            PnPCardPair(front: .pdfPage(url: fronts, pageIndex: 7), back: .image(url: back)),
            PnPCardPair(front: nil, back: .image(url: back)),
            PnPCardPair(front: .pdfPage(url: fronts, pageIndex: 2), back: nil)
        ])
        let options = PnPProjectSettings(
            cardSize: .custom,
            customWidth: "63.5",
            customHeight: "88.9",
            customUnit: "mm",
            paper: .a4,
            orientation: .landscape,
            cutStyle: .fullLines,
            duplexFlip: .shortEdge,
            artworkFit: .fill,
            artworkBounds: .bleed,
            bleed: .threeMillimeters,
            lockPairs: false
        )
        let saved = PnPProjectFile(deck: deck, settings: options, relativeTo: projectURL)
        try saved.write(to: projectURL)
        let reopened = try PnPProjectFile.read(from: projectURL)
        XCTAssertEqual(reopened, saved)
        XCTAssertEqual(reopened.settings, options)
        XCTAssertEqual(reopened.restoredDeck(relativeTo: projectURL), deck)
        XCTAssertEqual(reopened.cards[0].front?.path, "art/fronts.pdf")
        XCTAssertEqual(reopened.cards[0].back?.path, "art/shared.png")
        XCTAssertEqual(reopened.cards[1].back?.path, "art/shared.png")
        XCTAssertTrue(reopened.missingSources(relativeTo: projectURL).isEmpty)
    }

    func testFolderRelocationAndParentDirectoryRelativePaths() throws {
        let folder = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = folder.appendingPathComponent("original")
        let relocated = folder.appendingPathComponent("relocated")
        let source = original.appendingPathComponent("art/front.pdf")
        try touch(source)
        let projectURL = original.appendingPathComponent("Cards.pnpomatic")
        let deck = PnPDeck(cards: [
            PnPCardPair(front: .pdfPage(url: source, pageIndex: 0))
        ])
        try PnPProjectFile(
            deck: deck, settings: PnPProjectSettings(), relativeTo: projectURL
        ).write(to: projectURL)

        try FileManager.default.moveItem(at: original, to: relocated)
        let newProjectURL = relocated.appendingPathComponent("Cards.pnpomatic")
        let loaded = try PnPProjectFile.read(from: newProjectURL)
        XCTAssertTrue(loaded.missingSources(relativeTo: newProjectURL).isEmpty)
        XCTAssertEqual(
            loaded.restoredDeck(relativeTo: newProjectURL).cards[0].front,
            .pdfPage(url: relocated.appendingPathComponent("art/front.pdf"), pageIndex: 0)
        )

        let nestedProject = relocated.appendingPathComponent("projects/Nested.pnpomatic")
        let nested = PnPProjectFile(
            deck: PnPDeck(cards: [
                PnPCardPair(back: .image(url: relocated.appendingPathComponent("art/front.pdf")))
            ]),
            settings: PnPProjectSettings(),
            relativeTo: nestedProject
        )
        XCTAssertEqual(nested.cards[0].back?.path, "../art/front.pdf")
        XCTAssertTrue(nested.missingSources(relativeTo: nestedProject).isEmpty)
    }

    func testMissingArtworkIsReportedOnceAndCanBeRelinked() throws {
        let folder = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let projectURL = folder.appendingPathComponent("Cards.pnpomatic")
        let lost = folder.appendingPathComponent("lost/cards.pdf")
        let replacement = folder.appendingPathComponent("new/cards.pdf")
        try touch(replacement)

        let deck = PnPDeck(cards: [
            PnPCardPair(front: .pdfPage(url: lost, pageIndex: 0),
                        back: .pdfPage(url: lost, pageIndex: 9)),
            PnPCardPair(front: .pdfPage(url: lost, pageIndex: 1))
        ])
        let project = PnPProjectFile(
            deck: deck, settings: PnPProjectSettings(), relativeTo: projectURL
        )
        XCTAssertEqual(project.missingSources(relativeTo: projectURL), [lost])
        let restored = project.restoredDeck(
            relativeTo: projectURL, replacements: [lost: replacement]
        )
        XCTAssertEqual(restored.cards[0].front,
                       .pdfPage(url: replacement, pageIndex: 0))
        XCTAssertEqual(restored.cards[0].back,
                       .pdfPage(url: replacement, pageIndex: 9))
        XCTAssertEqual(restored.cards[1].front,
                       .pdfPage(url: replacement, pageIndex: 1))
        XCTAssertEqual(
            PnPProjectFile(
                deck: restored, settings: project.settings, relativeTo: projectURL
            ).cards[0].front?.path,
            "new/cards.pdf"
        )
    }

    func testUnsupportedVersionAndInvalidPageIndexAreRejected() throws {
        let folder = try fixtureDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let projectURL = folder.appendingPathComponent("Bad.pnpomatic")
        let pdf = folder.appendingPathComponent("unused.pdf")
        let valid = PnPProjectFile(
            deck: PnPDeck(cards: [
                PnPCardPair(front: .pdfPage(url: pdf, pageIndex: 1))
            ]),
            settings: PnPProjectSettings(),
            relativeTo: projectURL
        )
        let data = try valid.data()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object["formatVersion"] = 999
        try JSONSerialization.data(withJSONObject: object).write(to: projectURL)
        XCTAssertThrowsError(try PnPProjectFile.read(from: projectURL)) { error in
            guard case PnPProjectError.unsupportedVersion(999) = error else {
                return XCTFail("Expected unsupported project format: \(error)")
            }
        }

        var cards = try XCTUnwrap(object["cards"] as? [[String: Any]])
        var card = cards[0]
        var asset = try XCTUnwrap(card["front"] as? [String: Any])
        asset["pageIndex"] = -1
        card["front"] = asset
        cards[0] = card
        object["cards"] = cards
        object["formatVersion"] = 1
        try JSONSerialization.data(withJSONObject: object).write(to: projectURL)
        XCTAssertThrowsError(try PnPProjectFile.read(from: projectURL)) { error in
            guard case PnPProjectError.invalidAsset = error else {
                return XCTFail("Expected invalid project asset: \(error)")
            }
        }
    }
}
