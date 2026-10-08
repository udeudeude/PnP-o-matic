import CoreGraphics
import Foundation

public struct PnPLineSegment: Equatable {
    public let start: CGPoint
    public let end: CGPoint

    public init(_ start: CGPoint, _ end: CGPoint) {
        self.start = start
        self.end = end
    }
}

/// The physical, PDF-point layout used by both the exporter and the on-screen previews.
/// Slots are always indexed top-to-bottom, left-to-right; mirror only the assignment,
/// never the actual card artwork.
public struct PnPSheetLayout {
    public let sheetSize: CGSize
    public let geometry: PnPGridGeometry
    public let cutStyle: PnPCutStyle
    public let bleed: CGFloat

    public init(cardSize: CGSize, sheetSize: CGSize, cutStyle: PnPCutStyle, bleed: CGFloat = 0) {
        self.sheetSize = sheetSize
        self.cutStyle = cutStyle
        let requestedBleed = max(0, bleed)
        let width = 3 * cardSize.width + 6 * requestedBleed
        let height = 3 * cardSize.height + 6 * requestedBleed
        // Reserve a minimum 0.25-inch outer margin for printer tolerance and
        // external cut marks. Poker 3x3 still fits Letter at 100%.
        let margin: CGFloat = 18
        let printableWidth = max(0, sheetSize.width - margin * 2)
        let printableHeight = max(0, sheetSize.height - margin * 2)
        let scale = cardSize.width > 0 && cardSize.height > 0 && width > 0 && height > 0
            ? min(1, printableWidth / width, printableHeight / height) : 0
        self.bleed = requestedBleed * scale

        let scaledCard = CGSize(width: cardSize.width * scale, height: cardSize.height * scale)
        let gridSize = CGSize(width: width * scale, height: height * scale)
        let origin = CGPoint(
            x: (sheetSize.width - gridSize.width) / 2,
            y: (sheetSize.height - gridSize.height) / 2
        )
        self.geometry = PnPGridGeometry(
            cardSize: scaledCard,
            gridRect: CGRect(origin: origin, size: gridSize),
            scale: scale
        )
    }

    public func cardFrame(_ slot: Int) -> CGRect {
        precondition((0..<9).contains(slot))
        let column = slot % 3
        let row = slot / 3
        let strideX = geometry.cardSize.width + bleed * 2
        let strideY = geometry.cardSize.height + bleed * 2
        return CGRect(
            x: geometry.gridRect.minX + bleed + CGFloat(column) * strideX,
            y: geometry.gridRect.minY + bleed + CGFloat(2 - row) * strideY,
            width: geometry.cardSize.width,
            height: geometry.cardSize.height
        )
    }

    public func artworkFrame(_ slot: Int) -> CGRect {
        cardFrame(slot).insetBy(dx: -bleed, dy: -bleed)
    }

    /// Segments use PDF coordinates (origin bottom-left) and are also consumed by
    /// the preview. We do not print borders around each card.
    public var cutSegments: [PnPLineSegment] {
        let frames = (0..<9).map(cardFrame)

        if bleed > 0 {
            if cutStyle == .edgeMarks {
                let gap = min(1.5, bleed * 0.5)
                var result: [PnPLineSegment] = []
                for frame in frames {
                    for x in [frame.minX, frame.maxX] {
                        result.append(.init(
                            CGPoint(x: x, y: frame.minY - bleed),
                            CGPoint(x: x, y: frame.minY - gap)
                        ))
                        result.append(.init(
                            CGPoint(x: x, y: frame.maxY + gap),
                            CGPoint(x: x, y: frame.maxY + bleed)
                        ))
                    }
                    for y in [frame.minY, frame.maxY] {
                        result.append(.init(
                            CGPoint(x: frame.minX - bleed, y: y),
                            CGPoint(x: frame.minX - gap, y: y)
                        ))
                        result.append(.init(
                            CGPoint(x: frame.maxX + gap, y: y),
                            CGPoint(x: frame.maxX + bleed, y: y)
                        ))
                    }
                }
                return result
            }

            let xs = Set(frames.flatMap { [$0.minX, $0.maxX] })
            let ys = Set(frames.flatMap { [$0.minY, $0.maxY] })
            return xs.sorted().map {
                .init(CGPoint(x: $0, y: 0), CGPoint(x: $0, y: sheetSize.height))
            } + ys.sorted().map {
                .init(CGPoint(x: 0, y: $0), CGPoint(x: sheetSize.width, y: $0))
            }
        }

        let grid = geometry.gridRect
        let xs = (0...3).map { grid.minX + CGFloat($0) * geometry.cardSize.width }
        let ys = (0...3).map { grid.minY + CGFloat($0) * geometry.cardSize.height }

        if cutStyle == .fullLines {
            return xs.map {
                .init(CGPoint(x: $0, y: 0), CGPoint(x: $0, y: sheetSize.height))
            } + ys.map {
                .init(CGPoint(x: 0, y: $0), CGPoint(x: sheetSize.width, y: $0))
            }
        }

        let gap: CGFloat = 1.5
        var result: [PnPLineSegment] = []
        for x in xs {
            let bottom = max(0, grid.minY - gap)
            let top = min(sheetSize.height, grid.maxY + gap)
            if bottom > 0 {
                result.append(.init(CGPoint(x: x, y: 0), CGPoint(x: x, y: bottom)))
            }
            if top < sheetSize.height {
                result.append(.init(CGPoint(x: x, y: top), CGPoint(x: x, y: sheetSize.height)))
            }
        }
        for y in ys {
            let left = max(0, grid.minX - gap)
            let right = min(sheetSize.width, grid.maxX + gap)
            if left > 0 {
                result.append(.init(CGPoint(x: 0, y: y), CGPoint(x: left, y: y)))
            }
            if right < sheetSize.width {
                result.append(.init(CGPoint(x: right, y: y), CGPoint(x: sheetSize.width, y: y)))
            }
        }
        return result
    }
}
