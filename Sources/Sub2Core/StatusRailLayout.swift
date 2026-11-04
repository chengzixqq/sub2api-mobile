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

/// 00 §8.1 how far a row's capsule stays from the row's top and bottom edges. Only an end that caps the rail is inset, by
/// `endInset`; a short row gives up some of it so the capsule drawn in the row is still `minimumLength`, and a row shorter
/// than that is filled.
extension RailPosition {
    public struct Insets: Sendable, Equatable {
        public let top: Double
        public let bottom: Double
        public init(top: Double, bottom: Double) { self.top = top; self.bottom = bottom }
    }

    /// 2026-11-03 the user moved the ends from 10 to 22.
    public static let endInset: Double = 22
    /// The floor the user set on 2026-11-03, so short rows (the user list's single row, a batch failure) keep their mark.
    public static let minimumLength: Double = 16

    public func insets(height: Double) -> Insets {
        let spare = max(0, height - Self.minimumLength)
        let end = min(Self.endInset, capsTop && capsBottom ? spare / 2 : spare)
        return Insets(top: capsTop ? end : 0, bottom: capsBottom ? end : 0)
    }
}
