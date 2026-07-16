import Foundation
import VerityDomain

public actor ScheduleRepository {
    private let access: CoordinatedFileAccess
    private var fingerprints: [String: FileFingerprint] = [:]
    private var knownAbsent: Set<String> = []

    public init(root: URL) {
        self.access = CoordinatedFileAccess(root: root)
    }

    public func load(date: String) throws -> [ScheduleSlot] {
        try DomainRules.validateDate(date)
        let path = Self.relativePath(date)
        guard try access.exists(path) else {
            fingerprints.removeValue(forKey: path)
            knownAbsent.insert(path)
            return []
        }
        let result = try access.read(path)
        fingerprints[path] = result.fingerprint
        knownAbsent.remove(path)
        return Self.parse(result.content)
    }

    public func set(date: String, slot: ScheduleSlot) throws -> [ScheduleSlot] {
        try DomainRules.validateDate(date)
        try DomainRules.validateTime(slot.startTime)
        try DomainRules.validateDuration(slot.durationMinutes)
        var slots = try load(date: date)
        if let index = slots.firstIndex(where: { $0.startTime == slot.startTime }) {
            slots[index] = slot
        } else {
            slots.append(slot)
        }
        slots.sort { $0.startTime < $1.startTime }
        try persist(slots, date: date)
        return slots
    }

    public func delete(date: String, startTime: String) throws -> Bool {
        try DomainRules.validateDate(date)
        try DomainRules.validateTime(startTime)
        var slots = try load(date: date)
        let before = slots.count
        slots.removeAll { $0.startTime == startTime }
        guard before != slots.count else { return false }
        try persist(slots, date: date)
        return true
    }

    public func update(date: String, originalStartTime: String, slot: ScheduleSlot) throws -> [ScheduleSlot] {
        try DomainRules.validateDate(date)
        try DomainRules.validateTime(originalStartTime)
        try DomainRules.validateTime(slot.startTime)
        try DomainRules.validateDuration(slot.durationMinutes)
        var slots = try load(date: date)
        guard let originalIndex = slots.firstIndex(where: { $0.startTime == originalStartTime }) else {
            throw ScheduleRepositoryError.notFound(originalStartTime)
        }
        if slot.startTime != originalStartTime, slots.contains(where: { $0.startTime == slot.startTime }) {
            throw ScheduleRepositoryError.collision(slot.startTime)
        }
        slots[originalIndex] = slot
        slots.sort { $0.startTime < $1.startTime }
        try persist(slots, date: date)
        return slots
    }

    private func persist(_ slots: [ScheduleSlot], date: String) throws {
        let path = Self.relativePath(date)
        fingerprints[path] = try access.write(
            Self.render(slots, date: date),
            to: path,
            expectedFingerprint: fingerprints[path],
            requireAbsent: knownAbsent.contains(path)
        )
        knownAbsent.remove(path)
    }

    public static func relativePath(_ date: String) -> String { "Progress/Schedule-\(date).md" }

    public static func parse(_ content: String) -> [ScheduleSlot] {
        Markdown.parseTable(content).map {
            ScheduleSlot(
                startTime: $0["start_time"]?.trimmingCharacters(in: .whitespaces) ?? "",
                durationMinutes: Int($0["duration_min"] ?? "0") ?? 0,
                referenceType: ScheduleReferenceType(rawValue: $0["ref_type"]?.trimmingCharacters(in: .whitespaces) ?? "") ?? .fixed,
                referenceLabel: $0["ref_label"]?.trimmingCharacters(in: .whitespaces) ?? ""
            )
        }
    }

    public static func render(_ slots: [ScheduleSlot], date: String) -> String {
        let header = """
        ---
        type: schedule
        date: \(date)
        status: Active
        ---

        # Schedule for \(date)

        | start_time | duration_min | ref_type | ref_label |
        | --- | --- | --- | --- |
        """
        let rows = slots.map {
            "| \($0.startTime) | \($0.durationMinutes) | \($0.referenceType.rawValue) | \(Markdown.sanitizeCell($0.referenceLabel)) |"
        }
        return header + (rows.isEmpty ? "" : "\n" + rows.joined(separator: "\n"))
    }
}

public enum ScheduleRepositoryError: Error, LocalizedError, Sendable {
    case notFound(String)
    case collision(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let time): "The schedule strip at \(time) no longer exists. Reload and try again."
        case .collision(let time): "Another schedule strip already starts at \(time). Choose a different time."
        }
    }
}
