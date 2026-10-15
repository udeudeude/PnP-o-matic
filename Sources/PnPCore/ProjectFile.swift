import Foundation

/// The editable project is a JSON document, not a PDF. Artwork remains in its
/// original files so it can be edited and re-exported without quality loss.
public struct PnPProjectSettings: Codable, Equatable {
    public var cardSize: PnPCardSizePreset
    public var customWidth: String
    public var customHeight: String
    public var customUnit: String
    public var paper: PnPPaperSize
    public var orientation: PnPPaperOrientation
    public var cutStyle: PnPCutStyle
    public var duplexFlip: PnPDuplexFlip
    public var artworkFit: PnPArtworkFit
    public var artworkBounds: PnPArtworkBounds
    public var bleed: PnPBleed
    public var lockPairs: Bool

    public init(
        cardSize: PnPCardSizePreset = .poker,
        customWidth: String = "2.5",
        customHeight: String = "3.5",
        customUnit: String = "in",
        paper: PnPPaperSize = .letter,
        orientation: PnPPaperOrientation = .portrait,
        cutStyle: PnPCutStyle = .edgeMarks,
        duplexFlip: PnPDuplexFlip = .longEdge,
        artworkFit: PnPArtworkFit = .fit,
        artworkBounds: PnPArtworkBounds = .automatic,
        bleed: PnPBleed = .none,
        lockPairs: Bool = true
    ) {
        self.cardSize = cardSize
        self.customWidth = customWidth
        self.customHeight = customHeight
        self.customUnit = customUnit
        self.paper = paper
        self.orientation = orientation
        self.cutStyle = cutStyle
        self.duplexFlip = duplexFlip
        self.artworkFit = artworkFit
        self.artworkBounds = artworkBounds
        self.bleed = bleed
        self.lockPairs = lockPairs
    }
}

public enum PnPProjectError: LocalizedError {
    case unsupportedVersion(Int)
    case invalidAsset(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This project uses unsupported format version \(version)."
        case .invalidAsset(let description):
            return "Invalid project artwork reference: \(description)"
        }
    }
}

public struct PnPProjectFile: Codable, Equatable {
    public static let currentVersion = 1

    public struct StoredAsset: Codable, Equatable {
        public enum Kind: String, Codable {
            case pdfPage
            case image
        }

        public var kind: Kind
        public var path: String
        public var pageIndex: Int?

        fileprivate init(_ asset: PnPCardAsset, relativeTo projectURL: URL) {
            switch asset {
            case .pdfPage(let url, let index):
                kind = .pdfPage
                path = PnPProjectFile.relativePath(for: url, from: projectURL)
                pageIndex = index
            case .image(let url):
                kind = .image
                path = PnPProjectFile.relativePath(for: url, from: projectURL)
                pageIndex = nil
            }
        }

        fileprivate func resolvedURL(relativeTo projectURL: URL) -> URL {
            let folder = projectURL.standardizedFileURL.deletingLastPathComponent()
            if (path as NSString).isAbsolutePath {
                return URL(fileURLWithPath: path).standardizedFileURL
            }
            return URL(fileURLWithPath: path, relativeTo: folder).standardizedFileURL
        }

        fileprivate func asset(
            relativeTo projectURL: URL,
            replacements: [URL: URL]
        ) -> PnPCardAsset {
            let original = resolvedURL(relativeTo: projectURL)
            let resolved = replacements[original]?.standardizedFileURL ?? original
            switch kind {
            case .pdfPage:
                return .pdfPage(url: resolved, pageIndex: pageIndex!)
            case .image:
                return .image(url: resolved)
            }
        }
    }

    public struct StoredCard: Codable, Equatable {
        public var front: StoredAsset?
        public var back: StoredAsset?
    }

    public var formatVersion: Int
    public var settings: PnPProjectSettings
    public var cards: [StoredCard]

    public init(deck: PnPDeck, settings: PnPProjectSettings, relativeTo url: URL) {
        formatVersion = Self.currentVersion
        self.settings = settings
        cards = deck.cards.map { pair in
            StoredCard(
                front: pair.front.map { StoredAsset($0, relativeTo: url) },
                back: pair.back.map { StoredAsset($0, relativeTo: url) }
            )
        }
    }

    public func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public func write(to url: URL) throws {
        try data().write(to: url, options: .atomic)
    }

    public static func read(from url: URL) throws -> PnPProjectFile {
        let project = try JSONDecoder().decode(PnPProjectFile.self, from: Data(contentsOf: url))
        try project.validate()
        return project
    }

    private func validate() throws {
        guard formatVersion == Self.currentVersion else {
            throw PnPProjectError.unsupportedVersion(formatVersion)
        }
        for stored in cards.flatMap({ [$0.front, $0.back] }).compactMap({ $0 }) {
            guard !stored.path.isEmpty else {
                throw PnPProjectError.invalidAsset("empty path")
            }
            if stored.kind == .pdfPage {
                guard let index = stored.pageIndex, index >= 0 else {
                    throw PnPProjectError.invalidAsset(stored.path)
                }
            } else if stored.pageIndex != nil {
                throw PnPProjectError.invalidAsset(stored.path)
            }
        }
    }

    /// Unique missing URLs, in card order. A caller can ask for substitutes
    /// before applying the project; opening must never silently discard cards.
    public func missingSources(relativeTo url: URL) -> [URL] {
        var seen = Set<URL>()
        return cards.flatMap { [$0.front, $0.back] }
            .compactMap { $0?.resolvedURL(relativeTo: url) }
            .filter { source in
                guard seen.insert(source).inserted else { return false }
                return !FileManager.default.fileExists(atPath: source.path)
            }
    }

    public func restoredDeck(
        relativeTo url: URL,
        replacements: [URL: URL] = [:]
    ) -> PnPDeck {
        PnPDeck(cards: cards.map { stored in
            PnPCardPair(
                front: stored.front?.asset(relativeTo: url, replacements: replacements),
                back: stored.back?.asset(relativeTo: url, replacements: replacements)
            )
        })
    }

    /// Paths are relative to the project *directory*, not the process cwd.
    /// This lets a folder containing a project and its artwork move together.
    private static func relativePath(for sourceURL: URL, from projectURL: URL) -> String {
        let source = sourceURL.standardizedFileURL.pathComponents
        let folder = projectURL.standardizedFileURL.deletingLastPathComponent().pathComponents
        var common = 0
        while common < min(source.count, folder.count)
                && source[common] == folder[common] {
            common += 1
        }
        guard common > 0 else { return sourceURL.standardizedFileURL.path }
        let up = Array(repeating: "..", count: folder.count - common)
        let down = Array(source.dropFirst(common))
        return (up + down).joined(separator: "/")
    }
}
