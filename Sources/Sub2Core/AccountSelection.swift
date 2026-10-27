import Foundation

/// The account list's selection mode (20 §1.1, §1.3, §8.1): picked ids, a section's 全选 / 取消全选 over its loaded rows, and
/// pruning to the rows a full refresh still shows.
public struct AccountSelection: Sendable, Equatable {
    public private(set) var ids: Set<Int>
    public init(_ ids: Set<Int> = []) { self.ids = ids }

    public var count: Int { ids.count }
    public var isEmpty: Bool { ids.isEmpty }
    public func contains(_ id: Int) -> Bool { ids.contains(id) }
    public func toggling(_ id: Int) -> AccountSelection { AccountSelection(ids.symmetricDifference([id])) }
    /// A section with every row picked is cleared; otherwise its missing rows are added. Other sections stay as they are.
    public func togglingAll(_ sectionIDs: [Int]) -> AccountSelection {
        guard !sectionIDs.isEmpty else { return self }
        return allSelected(sectionIDs) ? AccountSelection(ids.subtracting(sectionIDs)) : AccountSelection(ids.union(sectionIDs))
    }
    public func pickedCount(in sectionIDs: [Int]) -> Int { sectionIDs.filter(ids.contains).count }
    /// False for an empty section.
    public func allSelected(_ sectionIDs: [Int]) -> Bool { !sectionIDs.isEmpty && sectionIDs.allSatisfy(ids.contains) }
    public func keeping(_ loaded: Set<Int>) -> AccountSelection { AccountSelection(ids.intersection(loaded)) }
    /// The picked ids in the order of `rowIDs`.
    public func ordered(by rowIDs: [Int]) -> [Int] { rowIDs.filter(ids.contains) }
}
