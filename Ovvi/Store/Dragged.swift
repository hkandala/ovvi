enum Dragged: Equatable {
    case pane(String)
    case tab(String)
    case workspace(String)

    var paneID: String? {
        if case let .pane(id) = self {
            id
        } else {
            nil
        }
    }
}
