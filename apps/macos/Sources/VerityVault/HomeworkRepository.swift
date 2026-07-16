import Foundation
import VerityDomain

public actor HomeworkRepository {
    public static let relativePath = "Progress/Homework.md"
    private let access: CoordinatedFileAccess
    private var fingerprint: FileFingerprint?

    public init(root: URL) {
        self.access = CoordinatedFileAccess(root: root)
    }

    public func load() throws -> [HomeworkItem] {
        guard try access.exists(Self.relativePath) else {
            fingerprint = try access.write(Self.render([], today: Self.today()), to: Self.relativePath, requireAbsent: true)
            return []
        }
        let result = try access.read(Self.relativePath)
        fingerprint = result.fingerprint
        return Self.parse(result.content)
    }

    public func add(
        subject: String,
        task: String,
        dueDate: String,
        estimatedMinutes: Int,
        priority: HomeworkPriority = .normal,
        now: Date = Date()
    ) throws -> HomeworkItem {
        guard !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.empty(field: "Subject")
        }
        guard !task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DomainValidationError.empty(field: "Task")
        }
        try DomainRules.validateDate(dueDate)
        try DomainRules.validateDuration(estimatedMinutes)
        var items = try load()
        let item = HomeworkItem(
            id: String(UUID().uuidString.lowercased().prefix(8)),
            subject: subject,
            task: task,
            dueDate: dueDate,
            estimatedMinutes: estimatedMinutes,
            priority: priority,
            status: .open,
            createdAt: Self.iso(now)
        )
        items.append(item)
        try persist(items)
        return item
    }

    public func update(_ id: String, transform: (inout HomeworkItem) throws -> Void) throws -> HomeworkItem? {
        var items = try load()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        try transform(&items[index])
        try DomainRules.validateDate(items[index].dueDate)
        try DomainRules.validateDuration(items[index].estimatedMinutes)
        try persist(items)
        return items[index]
    }

    public func markDone(_ id: String) throws -> HomeworkItem? {
        try update(id) { $0.status = .done }
    }

    public func delete(_ id: String) throws -> Bool {
        var items = try load()
        let before = items.count
        items.removeAll { $0.id == id }
        guard items.count != before else { return false }
        try persist(items)
        return true
    }

    private func persist(_ items: [HomeworkItem]) throws {
        fingerprint = try access.write(Self.render(items, today: Self.today()), to: Self.relativePath, expectedFingerprint: fingerprint)
    }

    public static func parse(_ content: String) -> [HomeworkItem] {
        Markdown.parseTable(content).compactMap { row in
            guard let id = row["id"]?.trimmingCharacters(in: .whitespaces), !id.isEmpty else { return nil }
            return HomeworkItem(
                id: id,
                subject: row["subject"]?.trimmingCharacters(in: .whitespaces) ?? "",
                task: row["task"]?.trimmingCharacters(in: .whitespaces) ?? "",
                dueDate: row["due_date"]?.trimmingCharacters(in: .whitespaces) ?? "",
                estimatedMinutes: Int(row["est_minutes"] ?? "0") ?? 0,
                priority: HomeworkPriority(rawValue: row["priority_tag"]?.trimmingCharacters(in: .whitespaces) ?? "") ?? .normal,
                status: HomeworkStatus(rawValue: row["status"]?.trimmingCharacters(in: .whitespaces) ?? "") ?? .open,
                createdAt: row["created_at"]?.trimmingCharacters(in: .whitespaces) ?? ""
            )
        }
    }

    public static func render(_ items: [HomeworkItem], today: String) -> String {
        let header = """
        ---
        type: homework_tracker
        status: Active
        last_updated: \(today)
        ---

        # Homework Tracker

        Track daily homework and tasks.

        | id | subject | task | due_date | est_minutes | priority_tag | status | created_at |
        | --- | --- | --- | --- | --- | --- | --- | --- |
        """
        let rows = items.map {
            "| \($0.id) | \(Markdown.sanitizeCell($0.subject)) | \(Markdown.sanitizeCell($0.task)) | \($0.dueDate) | \($0.estimatedMinutes) | \($0.priority.rawValue) | \($0.status.rawValue) | \($0.createdAt) |"
        }
        return header + (rows.isEmpty ? "" : "\n" + rows.joined(separator: "\n"))
    }

    private static func today(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
