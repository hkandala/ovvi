import HerdrKit
import Testing

@Test func `typed letters match in order, spaces ignored`() {
    #expect("Split Right".fuzzyScore("split r") == 1)
    #expect("Split Right".fuzzyScore("sr") == 1)
    #expect("Split Right".fuzzyScore("rs") == nil)
    #expect("Split Right".fuzzyScore("") == 0)
}

@Test func `case and accents do not count`() {
    #expect("Café".fuzzyScore("CAFE") == 0)
}

@Test func `word starts beat letters inside words`() {
    #expect("Split Down".fuzzyScore("sd") == 1)
    #expect("Inside".fuzzyScore("sd") == 3)
    #expect("light dark".fuzzyScore("dark") == 0)
    #expect("Bigger".fuzzyScore("igg") == 1)
}

@Test func `the best start wins`() {
    #expect("a xab".fuzzyScore("ab") == 1)
}
