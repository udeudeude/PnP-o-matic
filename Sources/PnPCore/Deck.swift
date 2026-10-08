import Foundation

public struct PnPCardPair: Equatable {
    public var front: PnPCardAsset?
    public var back: PnPCardAsset?

    public init(front: PnPCardAsset? = nil, back: PnPCardAsset? = nil) {
        self.front = front
        self.back = back
    }

    public var isEmpty: Bool { front == nil && back == nil }
}

/// Editing model independent of AppKit. Any edit can be undone by restoring a snapshot.
public struct PnPDeck: Equatable {
    public var cards: [PnPCardPair] = []

    public init(cards: [PnPCardPair] = []) { self.cards = cards }

    public mutating func ensureCount(_ count: Int) {
        while cards.count < count { cards.append(PnPCardPair()) }
    }

    public mutating func put(_ asset: PnPCardAsset?, side: PnPCardSide, at index: Int) {
        guard index >= 0 else { return }
        ensureCount(index + 1)
        if side == .front { cards[index].front = asset }
        else { cards[index].back = asset }
    }

    public mutating func append(_ assets: [PnPCardAsset], side: PnPCardSide) {
        guard !assets.isEmpty else { return }
        let lastOccupied = cards.indices.reversed().first { index in
            side == .front ? cards[index].front != nil : cards[index].back != nil
        }
        let start = (lastOccupied ?? -1) + 1
        ensureCount(start + assets.count)
        for (offset, asset) in assets.enumerated() {
            put(asset, side: side, at: start + offset)
        }
    }

    public mutating func addAlternating(_ assets: [PnPCardAsset]) {
        let start = cards.count
        ensureCount(start + (assets.count + 1) / 2)
        for (offset, asset) in assets.enumerated() {
            put(asset, side: offset.isMultiple(of: 2) ? .front : .back, at: start + offset / 2)
        }
    }

    public mutating func addHalves(_ assets: [PnPCardAsset]) {
        let frontCount = (assets.count + 1) / 2
        let start = cards.count
        ensureCount(start + frontCount)
        for (offset, asset) in assets.enumerated() {
            if offset < frontCount {
                put(asset, side: .front, at: start + offset)
            } else {
                put(asset, side: .back, at: start + offset - frontCount)
            }
        }
    }

    public mutating func repeatBack(_ asset: PnPCardAsset, emptyOnly: Bool = true) {
        for index in cards.indices where cards[index].front != nil {
            if !emptyOnly || cards[index].back == nil { cards[index].back = asset }
        }
    }

    public mutating func move(side: PnPCardSide, from: Int, to: Int, paired: Bool) {
        guard cards.indices.contains(from), to >= 0, from != to else { return }
        ensureCount(to + 1)
        if paired {
            let pair = cards.remove(at: from)
            cards.insert(pair, at: min(to, cards.count))
        } else {
            var values = cards.map { side == .front ? $0.front : $0.back }
            let value = values.remove(at: from)
            values.insert(value, at: min(to, values.count))
            for index in values.indices {
                if side == .front { cards[index].front = values[index] }
                else { cards[index].back = values[index] }
            }
        }
        trim()
    }

    public mutating func trim() {
        while cards.last?.isEmpty == true { cards.removeLast() }
    }

    public var missingBacks: [Int] {
        cards.indices.filter { cards[$0].front != nil && cards[$0].back == nil }.map { $0 + 1 }
    }

    public var missingFronts: [Int] {
        cards.indices.filter { cards[$0].back != nil && cards[$0].front == nil }.map { $0 + 1 }
    }
}
