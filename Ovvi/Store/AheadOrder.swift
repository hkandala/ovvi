import Foundation

extension Ahead {
    /// A snapshot may be read ahead of herdr's answer: the first with the order, else the second, ends it.
    struct NewOrder {
        let workspaceID: String?, ids: [String]
        var after: Int?
    }

    /// ponytail: an item that comes ahead of herdr's answer (a ⌘T's tab) ends it early, and a redraw counts as a
    /// snapshot (`after`): herdr's prior order can show until its answer. Keep the asked order for its items if that
    /// shows.
    static func ordered<T>(_ items: [T], by order: inout NewOrder?, id: (T) -> String, mine: (T) -> Bool) -> [T] {
        guard let asked = order else { return items }
        let indices = items.indices.filter { mine(items[$0]) }
        let ids = indices.map { id(items[$0]) }
        guard ids != asked.ids, Set(ids) == Set(asked.ids), asked.after.map({ $0 < 1 }) ?? true else {
            order = nil
            return items
        }
        order?.after = asked.after.map { $0 + 1 }
        var items = items
        let byID = Dictionary(indices.map { (id(items[$0]), items[$0]) }, uniquingKeysWith: { first, _ in first })
        for (index, id) in zip(indices, asked.ids) {
            items[index] = byID[id] ?? items[index]
        }
        return items
    }
}
