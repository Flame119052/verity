import Foundation
import VerityDomain

public actor CourseCursorRepository {
    public static let relativePath = "Progress/Course-Cursor.md"
    private let access: CoordinatedFileAccess
    private var fingerprint: FileFingerprint?

    public init(root: URL) {
        self.access = CoordinatedFileAccess(root: root)
    }

    public func load() throws -> [CourseCursor] {
        guard try access.exists(Self.relativePath) else {
            fingerprint = try access.write(Self.render([], today: Self.today()), to: Self.relativePath, requireAbsent: true)
            return []
        }
        let result = try access.read(Self.relativePath)
        fingerprint = result.fingerprint
        let rows = Markdown.parseTable(result.content)
        guard !rows.isEmpty else { return [] }
        return rows.compactMap { row in
            guard let course = row["course"]?.trimmingCharacters(in: .whitespaces), !course.isEmpty else { return nil }
            return CourseCursor(
                course: course,
                lastTopic: Self.optional(row["last_completed_topic"]),
                lastBlockType: Self.optional(row["last_completed_blockType"]),
                date: row["date"]?.trimmingCharacters(in: .whitespaces) ?? Self.today()
            )
        }
    }

    public func advance(course: String, topic: String?, blockType: String, blocks: [Block]) throws -> Block? {
        guard blocks.contains(where: { $0.course == course && $0.topic == topic && $0.blockType == blockType }) else {
            throw CourseCursorError.unknownBlock(course: course, topic: topic, blockType: blockType)
        }
        var cursors = try load()
        let cursor = CourseCursor(course: course, lastTopic: topic, lastBlockType: blockType, date: Self.today())
        if let index = cursors.firstIndex(where: { $0.course == course }) { cursors[index] = cursor }
        else { cursors.append(cursor) }
        fingerprint = try access.write(Self.render(cursors, today: Self.today()), to: Self.relativePath, expectedFingerprint: fingerprint)
        return DomainRules.nextBlock(after: cursor, in: blocks, course: course)
    }

    public static func render(_ cursors: [CourseCursor], today: String) -> String {
        let header = """
        ---
        type: course_cursor
        status: Active
        mode: Course-first, no weekly schedule
        last_updated: \(today)
        ---

        # Course Cursor

        This file tracks active course progress. Updated by the Study Command Center backend.

        | course | last_completed_topic | last_completed_blockType | date |
        | --- | --- | --- | --- |
        """
        let rows = cursors.map {
            "| \(Markdown.sanitizeCell($0.course)) | \(Markdown.sanitizeCell($0.lastTopic ?? "")) | \(Markdown.sanitizeCell($0.lastBlockType ?? "")) | \($0.date) |"
        }
        return header + (rows.isEmpty ? "" : "\n" + rows.joined(separator: "\n"))
    }

    private static func optional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func today() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

public enum CourseCursorError: Error, LocalizedError, Sendable {
    case unknownBlock(course: String, topic: String?, blockType: String)

    public var errorDescription: String? {
        switch self {
        case .unknownBlock(let course, let topic, let blockType):
            "No block exists for \(course), \(topic ?? "no topic"), \(blockType)."
        }
    }
}
