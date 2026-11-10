import XCTest

/// XCTest's own waits (waitForExistence, wait(for:toEqual:), predicate expectations) check about once a second and take
/// over a second even when the condition already holds; these check every 100 ms.
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

func steady<Value: Equatable>(_ timeout: TimeInterval, _ value: () -> Value?) -> Value? {
    var last: Value?, settled: Value?
    _ = until(timeout) {
        let now = value()
        defer { last = now }
        settled = now == last ? now : nil
        return settled != nil
    }
    return settled
}

func until(_ timeout: TimeInterval, _ check: () -> Bool) -> Bool {
    let end = Date.now + timeout
    while !check() {
        guard Date.now < end else { return false }
        Thread.sleep(forTimeInterval: 0.1)
    }
    return true
}

extension OvviUITests {
    /// Every 100 ms: a predicate expectation checks only about once a second.
    @discardableResult
    func poll<Value>(_ what: String, times: Int = 50,
                     _ probe: () async throws -> Value?) async throws -> Value
    {
        for _ in 0 ..< times {
            if let value = try await probe() {
                return value
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        // A throw, not XCTFail: XCTFail in async code stops the test inside the main actor's job, where its async
        // teardown blocks wait for the main actor until the 2-minute allowance runs out.
        throw Waited(description: "waited for \(what)")
    }

    func expect(_ what: String, times: Int = 50, _ check: () async throws -> Bool) async throws {
        try await poll(what, times: times) { try await check() ? true : nil }
    }

    struct Waited: Error, CustomStringConvertible {
        let description: String
    }
}
