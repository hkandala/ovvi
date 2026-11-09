import XCTest

/// XCTest's own waits (waitForExistence, wait(for:toEqual:), predicate expectations) check about once a second
/// and take over a second even when the condition already holds; these check every 100 ms
/// (playbook/ci.md, Writing fast tests).
extension XCUIElement {
    func exists(within timeout: TimeInterval) -> Bool {
        until(timeout) { exists }
    }

    func vanishes(within timeout: TimeInterval) -> Bool {
        until(timeout) { !exists }
    }

    /// Reading a property of a missing element fails the test, so it waits for the element first.
    func has<Value: Equatable>(_ property: KeyPath<XCUIElement, Value>, _ value: Value,
                               within timeout: TimeInterval) -> Bool
    {
        until(timeout) { exists && self[keyPath: property] == value }
    }

    var stringValue: String {
        value as? String ?? ""
    }
}

/// Checks every 100 ms until `check` passes; false when `timeout` runs out first.
func until(_ timeout: TimeInterval, _ check: () -> Bool) -> Bool {
    let end = Date.now + timeout
    while !check() {
        guard Date.now < end else { return false }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return true
}
