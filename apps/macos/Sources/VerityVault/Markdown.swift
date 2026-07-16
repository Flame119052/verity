import Foundation

public struct MarkdownSection: Equatable, Sendable {
    public var title: String
    public var content: String

    public init(title: String, content: String) {
        self.title = title
        self.content = content
    }
}

public enum Markdown {
    public static func sanitizeCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "❘")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    public static func parseTable(_ content: String) -> [[String: String]] {
        var headers: [String]?
        var rows: [[String: String]] = []

        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("|") else { continue }
            let pieces = trimmed.split(separator: "|", omittingEmptySubsequences: false)
            guard pieces.count >= 3 else { continue }
            let cells = pieces.dropFirst().dropLast().map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            let isSeparator = cells.allSatisfy { cell in
                let core = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
                return !core.isEmpty && core.allSatisfy { $0 == "-" }
            }
            if isSeparator { continue }
            if headers == nil {
                headers = cells
                continue
            }
            guard let headers else { continue }
            var row: [String: String] = [:]
            for (index, cell) in cells.enumerated() {
                row[index < headers.count ? headers[index] : "col_\(index)"] = cell
            }
            rows.append(row)
        }
        return rows
    }

    public static func tableHeaders(_ content: String) -> [String] {
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("|") else { continue }
            let pieces = line.split(separator: "|", omittingEmptySubsequences: false)
            guard pieces.count >= 3 else { continue }
            return pieces.dropFirst().dropLast().map { String($0).trimmingCharacters(in: .whitespaces) }
        }
        return []
    }

    public static func extractSections(_ content: String) -> [MarkdownSection] {
        var sections: [MarkdownSection] = []
        var currentTitle: String?
        var currentLines: [String] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if line.hasPrefix("## ") {
                if let currentTitle {
                    sections.append(MarkdownSection(title: currentTitle, content: currentLines.joined(separator: "\n")))
                }
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                currentLines = []
            } else {
                currentLines.append(line)
            }
        }
        if let currentTitle {
            sections.append(MarkdownSection(title: currentTitle, content: currentLines.joined(separator: "\n")))
        }
        return sections
    }

    public static func parseEmbeddedFields(_ text: String) -> (source: String, action: String, output: String, benchmark: String) {
        let labels = ["Source", "Action", "Output", "Benchmark"]
        var values: [String: String] = [:]
        let ns = text as NSString
        var matches: [(label: String, range: NSRange)] = []
        for label in labels {
            let pattern = "(?i)\\b\(label):\\s*"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    matches.append((label, match.range))
                }
            }
        }
        matches.sort { $0.range.location < $1.range.location }
        for (index, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : ns.length
            let value = ns.substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            values[match.label] = value
        }
        let leadingAction: String
        if let first = matches.first {
            leadingAction = ns.substring(to: first.range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            leadingAction = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (
            values["Source"] ?? "",
            values["Action"] ?? leadingAction,
            values["Output"] ?? "",
            values["Benchmark"] ?? ""
        )
    }
}
