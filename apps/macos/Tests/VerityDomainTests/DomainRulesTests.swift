import Foundation
import Testing
@testable import VerityDomain

struct DomainRulesTests {
    @Test func validatesDatesAndTimes() throws {
        try DomainRules.validateDate("2026-07-16")
        try DomainRules.validateTime("09:05")
        #expect(throws: (any Error).self) { try DomainRules.validateDate("2026-02-30") }
        #expect(throws: (any Error).self) { try DomainRules.validateTime("24:00") }
    }

    @Test func preservesTopiclessCursorBehavior() {
        let blocks = [
            Block(course: "IOQM", topic: nil, blockType: "Primer", durationRange: "30m", source: "", action: "", output: "", benchmark: ""),
            Block(course: "IOQM", topic: nil, blockType: "Drill", durationRange: "45m", source: "", action: "", output: "", benchmark: ""),
        ]
        let cursor = CourseCursor(course: "IOQM", lastTopic: nil, lastBlockType: "Primer", date: "2026-07-16")
        #expect(DomainRules.nextBlock(after: cursor, in: blocks, course: "IOQM")?.blockType == "Drill")
    }

    @Test func roundsLoggedTimeWithOneMinuteMinimum() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(DomainRules.logMinutes(start: start, stop: start.addingTimeInterval(10)) == 1)
        #expect(DomainRules.logMinutes(start: start, stop: start.addingTimeInterval(95)) == 2)
    }
}
