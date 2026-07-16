import Foundation
import VerityDomain

public struct BlockLibraryParser: Sendable {
    private let access: CoordinatedFileAccess

    public init(root: URL) {
        self.access = CoordinatedFileAccess(root: root)
    }

    public func parse() -> [Block] {
        var blocks: [Block] = []
        if let content = try? access.read("Courses/Boards-Daily-Block-Library.md").content {
            blocks += parseBoards(content)
        }
        if let content = try? access.read("Courses/Competition-Daily-Block-Library.md").content {
            blocks += parseCompetition(content)
            blocks += parseIOQM(content)
        }
        if let content = try? access.read("Courses/CPP-for-ZCO.md").content {
            blocks += parseZCO(content)
        }
        return blocks
    }

    private func parseBoards(_ content: String) -> [Block] {
        let durations = universalDurations(content)
        var blocks: [Block] = []
        for section in Markdown.extractSections(content) where section.title.contains("Block Bank") {
            let subject = section.title.components(separatedBy: "Block Bank")[0].trimmingCharacters(in: .whitespaces)
            let course = "Boards-" + subject.replacingOccurrences(of: " ", with: "-")
            let rows = Markdown.parseTable(section.content)
            guard !rows.isEmpty else { continue }
            let headers = Markdown.tableHeaders(section.content)
            guard !headers.isEmpty else { continue }
            let topicColumn = headers.contains("Chapter") ? "Chapter" : (headers.contains("Area") ? "Area" : headers[0])
            let singleBlock = headers.contains("Block")
            for row in rows {
                let topic = row[topicColumn]?.trimmingCharacters(in: .whitespaces) ?? ""
                guard !topic.isEmpty else { continue }
                if singleBlock {
                    let action = row["Block"]?.trimmingCharacters(in: .whitespaces) ?? ""
                    guard !action.isEmpty else { continue }
                    blocks.append(Block(course: course, topic: topic, blockType: "Practice Block", durationRange: "", source: "", action: action, output: row["Output"]?.trimmingCharacters(in: .whitespaces) ?? "", benchmark: row["Benchmark"]?.trimmingCharacters(in: .whitespaces) ?? ""))
                    continue
                }
                for column in headers where column != topicColumn {
                    let cell = row[column]?.trimmingCharacters(in: .whitespaces) ?? ""
                    guard !cell.isEmpty else { continue }
                    let type = normalizeBoardType(column)
                    if column == "Timed Benchmark" {
                        blocks.append(Block(course: course, topic: topic, blockType: type, durationRange: durations[type] ?? "", source: "", action: "", output: "", benchmark: cell))
                    } else if column.hasSuffix("Output") {
                        blocks.append(Block(course: course, topic: topic, blockType: type, durationRange: durations[type] ?? "", source: "", action: "", output: cell, benchmark: ""))
                    } else {
                        let fields = Markdown.parseEmbeddedFields(cell)
                        blocks.append(Block(course: course, topic: topic, blockType: type, durationRange: durations[type] ?? "", source: fields.source, action: fields.action, output: fields.output, benchmark: fields.benchmark))
                    }
                }
            }
        }
        return blocks
    }

    private func parseCompetition(_ content: String) -> [Block] {
        var blocks: [Block] = []
        for section in Markdown.extractSections(content) where section.title.contains("Block Bank") {
            let course = section.title.components(separatedBy: "Block Bank")[0].trimmingCharacters(in: .whitespaces)
            guard course != "IOQM", course != "ZCO/ZIO" else { continue }
            let rows = Markdown.parseTable(section.content)
            guard !rows.isEmpty else { continue }
            let headers = Markdown.tableHeaders(section.content)
            guard !headers.isEmpty else { continue }
            if headers.contains("Duration") {
                let typeColumn = headers.contains("Block Type") ? "Block Type" : (headers.contains("Block") ? "Block" : headers[0])
                for row in rows {
                    let type = row[typeColumn]?.trimmingCharacters(in: .whitespaces) ?? ""
                    guard !type.isEmpty else { continue }
                    blocks.append(Block(course: course, topic: nil, blockType: type, durationRange: trim(row["Duration"]), source: trim(row["Source"]), action: trim(row["Action"]), output: trim(row["Output"]), benchmark: trim(row["Benchmark"])))
                }
            } else {
                let topicColumn = headers[0]
                let actionColumn = headers.contains("Action") ? "Action" : (headers.contains("Daily Block") ? "Daily Block" : (headers.contains("Start State") ? "Start State" : nil))
                for row in rows {
                    let topic = trim(row[topicColumn])
                    guard !topic.isEmpty else { continue }
                    blocks.append(Block(course: course, topic: topic, blockType: "Practice Block", durationRange: "", source: trim(row["Source"]), action: actionColumn.map { trim(row[$0]) } ?? "", output: trim(row["Output"]), benchmark: trim(row["Benchmark"])))
                }
            }
        }
        return blocks
    }

    private func parseIOQM(_ content: String) -> [Block] {
        guard let section = Markdown.extractSections(content).first(where: { $0.title.trimmingCharacters(in: .whitespaces) == "IOQM Block Bank" }),
              let regex = try? NSRegularExpression(pattern: "Topic order:\\s*\\n((?:\\d+\\.\\s*.+\\n?)+)")
        else { return [] }
        let ns = section.content as NSString
        guard let match = regex.firstMatch(in: section.content, range: NSRange(location: 0, length: ns.length)), match.numberOfRanges > 1 else { return [] }
        let topics = ns.substring(with: match.range(at: 1)).components(separatedBy: "\n").compactMap { line -> String? in
            let cleaned = line.replacingOccurrences(of: "^\\d+\\.\\s*", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\.\\s*$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return cleaned.isEmpty ? nil : cleaned
        }
        return expand(course: "IOQM", topics: topics, definitions: [
            ("Concept Primer", "45-60m", "handout/NCERT/RD as named in weekly plan", "read only the needed section, then solve examples", "1-page method sheet", "can explain method without notes"),
            ("Warmup Set", "45-60m", "IOQM/AoPS/simple exercises", "solve 4-8 basic problems", "solved set + corrections", "75%+ without hints"),
            ("Target Problem", "60-90m", "IOQM past/archive/AoPS", "one medium problem, 45m before hint", "full solution", "corrected solution in own words"),
            ("Stretch Problem", "60-90m", "hard IOQM/AoPS", "one hard problem", "attempt log + final solution", "meaningful progress or clean correction"),
            ("Timed Mini-Set", "75-90m", "mixed IOQM problems", "3-5 problems under time", "score + error log", "60-70% now, 80% before exam"),
            ("Full Mock", "180m + review", "official past paper", "timed paper", "score table", "30+ by Week 9, 35+ final"),
        ])
    }

    private func parseZCO(_ content: String) -> [Block] {
        guard let regex = try? NSRegularExpression(pattern: "(?m)^### Week (\\d+): (.+)$") else { return [] }
        let ns = content as NSString
        var topics = Array<String?>(repeating: nil, count: 10)
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) where match.numberOfRanges == 3 {
            guard let week = Int(ns.substring(with: match.range(at: 1))), (1...10).contains(week) else { continue }
            topics[week - 1] = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        }
        return expand(course: "ZCO/ZIO", topics: topics.compactMap { $0 }, definitions: [
            ("C++ Syntax Drill", "30-45m", "CPH + local compiler", "write tiny program", ".cpp file", "compiles and output predicted"),
            ("CSES Beginner", "45-75m", "CSES Intro/Sorting/etc.", "solve the named task from [[Competitions/ZCO-Problem-Queue]]", "accepted/local-correct code", "passes samples and self-test"),
            ("Algorithm Concept", "45-60m", "CPH/cp-algorithms", "learn pattern, write template", "template + explanation", "explain invariant/complexity"),
            ("ZCO Archive Attempt", "90-180m", "IARCS archive/CodeDrills", "timed old problem", "attempt + editorial correction", "understands intended solution"),
            ("ZIO Written Reasoning", "45-60m", "IARCS/ZIO archive", "solve without code", "written reasoning", "no handwave; cases covered"),
            ("Contest Practice", "90-150m", "Codeforces Div 3/CSES", "timed set", "solved count + error log", "no repeated implementation error"),
        ])
    }

    private func expand(course: String, topics: [String], definitions: [(String, String, String, String, String, String)]) -> [Block] {
        topics.flatMap { topic in definitions.map { Block(course: course, topic: topic, blockType: $0.0, durationRange: $0.1, source: $0.2, action: $0.3, output: $0.4, benchmark: $0.5) } }
    }

    private func universalDurations(_ content: String) -> [String: String] {
        let lines = content.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains("Universal Block Types") }) else { return [:] }
        let tail = lines.dropFirst(start + 1).prefix { !$0.hasPrefix("## ") }.joined(separator: "\n")
        return Dictionary(uniqueKeysWithValues: Markdown.parseTable(tail).compactMap {
            guard let block = $0["Block"] ?? $0["block"], let duration = $0["Duration"] ?? $0["duration"] else { return nil }
            return (block.trimmingCharacters(in: .whitespaces), duration.trimmingCharacters(in: .whitespaces))
        })
    }

    private func normalizeBoardType(_ column: String) -> String {
        if column.localizedCaseInsensitiveContains("First Pass") { return "First Pass" }
        if column.localizedCaseInsensitiveContains("Drill") { return "Exercise Drill" }
        if column.localizedCaseInsensitiveContains("Timed") { return "Timed Mini-Test" }
        return column.trimmingCharacters(in: .whitespaces)
    }

    private func trim(_ value: String?) -> String { value?.trimmingCharacters(in: .whitespaces) ?? "" }
}
