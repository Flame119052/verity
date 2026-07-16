import Foundation
import VerityDomain

public actor SyllabusRepository {
    public static let relativePath = "Boards/Syllabus-Checklist.md"
    private let access: CoordinatedFileAccess
    private var fingerprint: FileFingerprint?

    public init(root: URL) {
        self.access = CoordinatedFileAccess(root: root)
    }

    public func load() throws -> [SyllabusItem] {
        let result = try access.read(Self.relativePath)
        fingerprint = result.fingerprint
        return Self.parse(result.content)
    }

    public func update(subject: String, chapter: String, status: SyllabusStatus) throws -> SyllabusItem {
        let result = try access.read(Self.relativePath)
        fingerprint = result.fingerprint
        var lines = result.content.components(separatedBy: "\n")
        var section = ""
        var headers: [String] = []
        var exact: [(line: Int, status: Int, item: SyllabusItem)] = []
        var fuzzy: [(line: Int, status: Int, item: SyllabusItem)] = []

        for index in lines.indices {
            let line = lines[index]
            if line.hasPrefix("## ") {
                section = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                headers = []
                continue
            }
            guard section == subject, line.trimmingCharacters(in: .whitespaces).hasPrefix("|") else { continue }
            let cells = Self.cells(line)
            guard !cells.isEmpty else { continue }
            if headers.isEmpty {
                headers = cells
                continue
            }
            if cells.allSatisfy({ !$0.isEmpty && $0.trimmingCharacters(in: CharacterSet(charactersIn: ":")).allSatisfy { $0 == "-" } }) {
                continue
            }
            guard let statusIndex = headers.firstIndex(of: "Status") else { continue }
            let row = Dictionary(uniqueKeysWithValues: zip(headers, cells))
            let rowChapter = row["Chapter"] ?? row["Chapter / Topic"] ?? row["Item"] ?? ""
            let item = Self.item(subject: subject, row: row)
            if rowChapter.trimmingCharacters(in: .whitespaces).localizedCaseInsensitiveCompare(chapter.trimmingCharacters(in: .whitespaces)) == .orderedSame {
                exact.append((index, statusIndex, item))
            } else if Self.chapterMatches(rowChapter, chapter) {
                fuzzy.append((index, statusIndex, item))
            }
        }

        let target = exact.last ?? (fuzzy.count == 1 ? fuzzy[0] : nil)
        guard let target else { throw SyllabusError.topicNotFoundOrAmbiguous(subject: subject, chapter: chapter) }
        var targetCells = Self.cells(lines[target.line])
        guard target.status < targetCells.count else { throw SyllabusError.malformedTable }
        targetCells[target.status] = status.rawValue
        lines[target.line] = "| " + targetCells.map(Markdown.sanitizeCell).joined(separator: " | ") + " |"
        fingerprint = try access.write(lines.joined(separator: "\n"), to: Self.relativePath, expectedFingerprint: fingerprint)
        var updated = target.item
        updated.status = status
        return updated
    }

    public static func parse(_ content: String) -> [SyllabusItem] {
        Markdown.extractSections(content).flatMap { section -> [SyllabusItem] in
            let subject = section.title.trimmingCharacters(in: .whitespaces)
            guard subject != "Planning Rule", subject != "How To Use" else { return [] }
            return Markdown.parseTable(section.content).compactMap { row in
                let item = item(subject: subject, row: row)
                return item.chapter.isEmpty && item.unit.isEmpty ? nil : item
            }
        }
    }

    public static func subject(for course: String) -> String? {
        let segment = course.replacingOccurrences(of: "Boards-", with: "").split(separator: "-").first.map(String.init)
        return [
            "Science": "Science",
            "SST": "Social Science",
            "English": "English Language and Literature",
            "Sanskrit": "Sanskrit / Hindi",
            "Mathematics": "Mathematics",
            "IT": "Information Technology",
        ][segment ?? ""]
    }

    public static func chapterMatches(_ lhs: String, _ rhs: String) -> Bool {
        let a = lhs.trimmingCharacters(in: .whitespaces).lowercased()
        let b = rhs.trimmingCharacters(in: .whitespaces).lowercased()
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    private static func item(subject: String, row: [String: String]) -> SyllabusItem {
        SyllabusItem(
            subject: subject,
            unit: (row["Unit"] ?? row["Area"] ?? row["Language"] ?? "").trimmingCharacters(in: .whitespaces),
            chapter: (row["Chapter"] ?? row["Chapter / Topic"] ?? row["Item"] ?? "").trimmingCharacters(in: .whitespaces),
            marksWeight: (row["Marks Weight"] ?? "").trimmingCharacters(in: .whitespaces),
            status: SyllabusStatus(rawValue: (row["Status"] ?? "NS").trimmingCharacters(in: .whitespaces)) ?? .notStarted,
            evidence: (row["Evidence"] ?? "").trimmingCharacters(in: .whitespaces)
        )
    }

    private static func cells(_ line: String) -> [String] {
        let pieces = line.trimmingCharacters(in: .whitespaces).split(separator: "|", omittingEmptySubsequences: false)
        guard pieces.count >= 3 else { return [] }
        return pieces.dropFirst().dropLast().map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}

public enum SyllabusError: Error, LocalizedError, Sendable {
    case topicNotFoundOrAmbiguous(subject: String, chapter: String)
    case malformedTable

    public var errorDescription: String? {
        switch self {
        case .topicNotFoundOrAmbiguous(let subject, let chapter): "\(chapter) was not found unambiguously in the \(subject) syllabus."
        case .malformedTable: "The syllabus table is malformed."
        }
    }
}
