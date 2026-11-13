import Foundation

/// Pure helpers for the user's custom lamp order.
enum LampOrder {
    /// The saved order brought in line with the lamps that exist now: unknown ids and duplicates
    /// are dropped, lamps that are not in the order yet (added after it was saved) are appended
    /// in `knownIds` order. An empty saved order simply yields `knownIds`.
    static func normalized(_ order: [String], knownIds: [String]) -> [String] {
        let known = Set(knownIds)
        var seen = Set<String>()
        var result: [String] = []
        for id in order where known.contains(id) && seen.insert(id).inserted {
            result.append(id)
        }
        for id in knownIds where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }

    /// The order after dragging `dragged` onto `target`, or nil when nothing moves (same lamp,
    /// or either id is not a known lamp).
    static func moving(_ dragged: String, onto target: String, in order: [String], knownIds: [String]) -> [String]? {
        guard dragged != target else { return nil }
        var updated = normalized(order, knownIds: knownIds)
        guard let movingIndex = updated.firstIndex(of: dragged),
              let dropIndex = updated.firstIndex(of: target) else { return nil }
        let item = updated.remove(at: movingIndex)
        let destination = movingIndex < dropIndex ? dropIndex - 1 : dropIndex
        updated.insert(item, at: max(0, destination))
        return updated
    }
}
