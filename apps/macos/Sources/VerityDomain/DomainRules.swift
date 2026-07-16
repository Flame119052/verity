import Foundation

public enum DomainValidationError: Error, Equatable, LocalizedError, Sendable {
    case empty(field: String)
    case invalidDate(String)
    case invalidTime(String)
    case invalidDuration(Int)
    case invalidIdentifier(String)

    public var errorDescription: String? {
        switch self {
        case .empty(let field): "\(field) cannot be empty."
        case .invalidDate(let value): "\(value) is not a valid YYYY-MM-DD date."
        case .invalidTime(let value): "\(value) is not a valid HH:mm time."
        case .invalidDuration(let value): "\(value) is not a valid positive duration."
        case .invalidIdentifier(let value): "\(value) is not a safe identifier."
        }
    }
}

public enum DomainRules {
    public enum AdherenceStatus: String, Equatable, Sendable {
        case completed, partial, pending, notLogged = "not_logged", notTracked = "not_tracked"
    }
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()

    public static func validateDate(_ value: String) throws {
        guard value.count == 10, dateFormatter.date(from: value) != nil else {
            throw DomainValidationError.invalidDate(value)
        }
    }

    public static func validateTime(_ value: String) throws {
        let pieces = value.split(separator: ":", omittingEmptySubsequences: false)
        guard pieces.count == 2,
              pieces[0].count == 2,
              pieces[1].count == 2,
              let hour = Int(pieces[0]),
              let minute = Int(pieces[1]),
              (0...23).contains(hour),
              (0...59).contains(minute)
        else { throw DomainValidationError.invalidTime(value) }
    }

    public static func validateDuration(_ value: Int) throws {
        guard value > 0 else { throw DomainValidationError.invalidDuration(value) }
    }

    public static func validateIdentifier(_ value: String) throws {
        guard !value.isEmpty,
              value.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { throw DomainValidationError.invalidIdentifier(value) }
    }

    public static func nextBlock(after cursor: CourseCursor?, in blocks: [Block], course: String) -> Block? {
        let courseBlocks = blocks.filter { $0.course == course }
        guard let cursor, let blockType = cursor.lastBlockType else { return courseBlocks.first }
        guard let index = courseBlocks.firstIndex(where: {
            $0.topic == cursor.lastTopic && $0.blockType == blockType
        }) else { return courseBlocks.first }
        let nextIndex = courseBlocks.index(after: index)
        return nextIndex < courseBlocks.endIndex ? courseBlocks[nextIndex] : nil
    }

    public static func logMinutes(start: Date, stop: Date) -> Int {
        max(1, Int((stop.timeIntervalSince(start) / 60).rounded()))
    }

    public static func scoredHomework(_ items: [HomeworkItem], today: String) throws -> [(item: HomeworkItem, score: Int, reason: String)] {
        try validateDate(today)
        guard let todayDate = dateFormatter.date(from: today) else { throw DomainValidationError.invalidDate(today) }
        return items
            .filter { $0.status == .open }
            .compactMap { item in
                guard let due = dateFormatter.date(from: item.dueDate) else { return nil }
                let days = Calendar(identifier: .gregorian).dateComponents([.day], from: todayDate, to: due).day ?? 0
                let score: Int
                let reason: String
                if days < 0 {
                    score = 1_000 + abs(days) + item.priority.scoreAdjustment
                    reason = "overdue by \(abs(days)) days"
                } else {
                    score = days + item.priority.scoreAdjustment
                    reason = "due in \(days) days"
                }
                return (item, score, reason)
            }
            .sorted { lhs, rhs in
                let lhsOverdue = lhs.score >= 1_000
                let rhsOverdue = rhs.score >= 1_000
                if lhsOverdue != rhsOverdue { return lhsOverdue && !rhsOverdue }
                return lhs.score < rhs.score
            }
    }

    public static func adherence(
        slot: ScheduleSlot,
        date: String,
        logs: [TimeLogEntry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (status: AdherenceStatus, loggedMinutes: Int) {
        guard slot.referenceType != .fixed else { return (.notTracked, 0) }
        let matching = logs.filter { entry in
            guard entry.date == date else { return false }
            if slot.referenceType == .homework { return entry.referenceType == .homework }
            return entry.referenceType == .course && entry.course == slot.referenceLabel.components(separatedBy: " · ").first
        }
        let logged = matching.reduce(0) { $0 + $1.minutes }
        let required = Double(slot.durationMinutes) * 0.9
        if Double(logged) >= required { return (.completed, logged) }
        if logged > 0 { return (.partial, logged) }
        let today = localDateString(now, calendar: calendar)
        if date > today { return (.pending, 0) }
        if date < today { return (.notLogged, 0) }
        let pieces = slot.startTime.split(separator: ":").compactMap { Int($0) }
        guard pieces.count == 2 else { return (.pending, 0) }
        let currentMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let slotStart = pieces[0] * 60 + pieces[1]
        return Double(currentMinutes - slotStart) >= required ? (.notLogged, 0) : (.pending, 0)
    }

    private static func localDateString(_ date: Date, calendar: Calendar) -> String {
        let values = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", values.year ?? 0, values.month ?? 0, values.day ?? 0)
    }
}
