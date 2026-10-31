import Foundation

/// 00 §8.1 status rail: a row's capsule within the rail its neighbours form. Rows that draw a capsule join into one rail
/// whatever their tones; a row without one breaks it. Only the rail's two ends are inset and rounded.
public enum RailPosition: Sendable, Equatable, CaseIterable {
    case single, top, middle, bottom

    public var capsTop: Bool { self == .single || self == .top }
    public var capsBottom: Bool { self == .single || self == .bottom }

    /// nil for rows without a capsule.
    public static func positions(drawsRail flags: [Bool]) -> [RailPosition?] {
        flags.indices.map { index in
            guard flags[index] else { return nil }
            let joinsAbove = index > flags.startIndex && flags[index - 1]
            let joinsBelow = index + 1 < flags.endIndex && flags[index + 1]
            switch (joinsAbove, joinsBelow) {
            case (false, false): return .single
            case (false, true): return .top
            case (true, true): return .middle
            case (true, false): return .bottom
            }
        }
    }

    public static func positions<Item>(of items: [Item], drawsRail: (Item) -> Bool) -> [RailPosition?] {
        positions(drawsRail: items.map(drawsRail))
    }
}
