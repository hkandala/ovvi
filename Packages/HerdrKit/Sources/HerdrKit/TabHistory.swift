/// A window's tabs shown, across spaces, oldest first, as a browser's history: Go Back and Go Forward move `place`.
/// Each tab has one entry, at its latest visit.
public struct TabHistory: Equatable, Sendable {
    public private(set) var ids: [String] = []
    public private(set) var place = -1

    public init() {}

    /// A step through the history lands on `place` and adds nothing; any other show drops the tabs ahead, as a
    /// browser does, and moves the tab to the newest place.
    public mutating func show(_ id: String) {
        guard place < 0 || ids[place] != id else { return }
        // ponytail: the last 100 tabs, enough to step back through by key.
        ids = Array(ids.prefix(place + 1).filter { $0 != id }.suffix(99)) + [id]
        place = ids.count - 1
    }

    public func renamed(_ arrived: [String: String]) -> Self {
        var renamed = self
        renamed.ids = ids.map { arrived[$0] ?? $0 }
        return renamed
    }

    /// The places that Go Back (-1) or Go Forward (1) lands on, press after press, nearest first: past the tabs no
    /// longer `open` and the tab each press leaves.
    public func trail(_ offset: Int, from shown: String?, max: Int, open: (String) -> Bool) -> [Int] {
        var steps: [Int] = [], shown = shown, index = place + offset
        while steps.count < max, ids.indices.contains(index) {
            let id = ids[index]
            if id != shown, open(id) {
                steps.append(index)
                shown = id
            }
            index += offset
        }
        return steps
    }

    public mutating func go(to index: Int) {
        place = index
    }
}
