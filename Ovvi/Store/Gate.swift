import Foundation

@MainActor
final class Gate {
    private var free: Int
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) {
        free = count
    }

    var busy: Bool {
        free == 0
    }

    func enter(first: Bool = false) async {
        if free > 0 {
            free -= 1
        } else {
            await withCheckedContinuation { waiting.insert($0, at: first ? 0 : waiting.endIndex) }
        }
    }

    func leave() {
        if waiting.isEmpty {
            free += 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}
