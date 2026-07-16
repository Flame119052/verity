import Foundation
import VerityDomain

public actor TimeLogRepository {
    public static let relativePath = "Progress/Time-Log.md"
    private let access: CoordinatedFileAccess
    private var fingerprint: FileFingerprint?

    public init(root: URL) {
        self.access = CoordinatedFileAccess(root: root)
    }

    public func load() throws -> [TimeLogEntry] {
        guard try access.exists(Self.relativePath) else {
            fingerprint = try access.write(Self.render([], today: Self.today()), to: Self.relativePath, requireAbsent: true)
            return []
        }
        let result = try access.read(Self.relativePath)
        fingerprint = result.fingerprint
        return Self.parse(result.content)
    }

    public func append(_ entry: TimeLogEntry) throws {
        try DomainRules.validateDate(entry.date)
        try DomainRules.validateDuration(entry.minutes)
        var entries = try load()
        if entries.contains(where: { $0.id == entry.id }) { return }
        entries.append(entry)
        fingerprint = try access.write(Self.render(entries, today: Self.today()), to: Self.relativePath, expectedFingerprint: fingerprint)
    }

    public static func parse(_ content: String) -> [TimeLogEntry] {
        Markdown.parseTable(content).map {
            TimeLogEntry(
                date: $0["date"]?.trimmingCharacters(in: .whitespaces) ?? "",
                referenceType: TimeLogReferenceType(rawValue: $0["ref_type"]?.trimmingCharacters(in: .whitespaces) ?? "") ?? .course,
                referenceLabel: $0["ref_label"]?.trimmingCharacters(in: .whitespaces) ?? "",
                course: uncell($0["course"]),
                topic: uncell($0["topic"]),
                blockType: uncell($0["blockType"]),
                startedAt: $0["started_at"]?.trimmingCharacters(in: .whitespaces) ?? "",
                stoppedAt: $0["stopped_at"]?.trimmingCharacters(in: .whitespaces) ?? "",
                minutes: Int($0["minutes"] ?? "0") ?? 0
            )
        }
    }

    public static func render(_ entries: [TimeLogEntry], today: String) -> String {
        let header = """
        ---
        type: time_log
        status: Active
        last_updated: \(today)
        ---

        # Time Log

        Append-only log of study and homework time.

        | date | ref_type | ref_label | course | topic | blockType | started_at | stopped_at | minutes |
        | --- | --- | --- | --- | --- | --- | --- | --- | --- |
        """
        let rows = entries.map {
            "| \($0.date) | \($0.referenceType.rawValue) | \(Markdown.sanitizeCell($0.referenceLabel)) | \(cell($0.course)) | \(cell($0.topic)) | \(cell($0.blockType)) | \(Markdown.sanitizeCell($0.startedAt)) | \(Markdown.sanitizeCell($0.stoppedAt)) | \($0.minutes) |"
        }
        return header + (rows.isEmpty ? "" : "\n" + rows.joined(separator: "\n"))
    }

    private static func cell(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return Markdown.sanitizeCell(value)
    }

    private static func uncell(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespaces) ?? ""
        return trimmed.isEmpty || trimmed == "-" ? nil : trimmed
    }

    private static func today(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
