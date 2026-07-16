import Foundation

public struct ParsedHomework: Equatable, Sendable {
    public var subject: String
    public var task: String
    public var dueDate: String
    public var estimatedMinutes: Int
    public var priority: HomeworkPriority

    public init(subject: String, task: String, dueDate: String, estimatedMinutes: Int, priority: HomeworkPriority) {
        self.subject = subject
        self.task = task
        self.dueDate = dueDate
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
    }
}

public enum HomeworkQuickParser {
    public static func parse(_ raw: String, now: Date = Date(), calendar inputCalendar: Calendar = .current) -> ParsedHomework? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var subject = ""
        if let colon = text.firstIndex(of: ":"), text.distance(from: text.startIndex, to: colon) < 30 {
            subject = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            text = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        var minutes = 30
        var priority = HomeworkPriority.normal
        var dueDate = format(shift(now, days: 1, calendar: inputCalendar), calendar: inputCalendar)
        var dueWasSet = false
        let tokens = text.split(whereSeparator: \.isWhitespace).map(String.init)
        var kept: [String] = []
        var index = 0
        while index < tokens.count {
            let token = tokens[index]
            let normalized = token.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "!"))
            if let value = minutesToken(normalized) { minutes = value; index += 1; continue }
            if let value = HomeworkPriority.allCases.first(where: { $0.rawValue.lowercased() == normalized }) { priority = value; index += 1; continue }
            if normalized == "due", index + 1 < tokens.count, let date = resolve(tokens[index + 1], now: now, calendar: inputCalendar) {
                dueDate = date; dueWasSet = true; index += 2; continue
            }
            if !dueWasSet, let date = resolve(token, now: now, calendar: inputCalendar) {
                dueDate = date; dueWasSet = true; index += 1; continue
            }
            kept.append(token)
            index += 1
        }
        var task = kept.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !task.isEmpty else { return nil }
        if subject.isEmpty {
            let words = task.split(separator: " ").map(String.init)
            subject = words[0]
            if words.count > 1 { task = words.dropFirst().joined(separator: " ") }
        }
        return ParsedHomework(subject: subject, task: task, dueDate: dueDate, estimatedMinutes: minutes, priority: priority)
    }

    private static func minutesToken(_ token: String) -> Int? {
        for suffix in ["min", "m"] where token.hasSuffix(suffix) {
            return Int(token.dropLast(suffix.count))
        }
        return nil
    }

    private static func resolve(_ token: String, now: Date, calendar: Calendar) -> String? {
        let value = token.lowercased()
        if (try? DomainRules.validateDate(value)) != nil { return value }
        if ["tom", "tomorrow", "tmr"].contains(value) { return format(shift(now, days: 1, calendar: calendar), calendar: calendar) }
        if value == "today" { return format(now, calendar: calendar) }
        if value.hasPrefix("+"), value.hasSuffix("d"), let days = Int(value.dropFirst().dropLast()) {
            return format(shift(now, days: days, calendar: calendar), calendar: calendar)
        }
        let parts = value.split(separator: "/")
        if parts.count == 2, let day = Int(parts[0]), let month = Int(parts[1]) {
            let currentYear = calendar.component(.year, from: now)
            var components = DateComponents(year: currentYear, month: month, day: day)
            guard var date = calendar.date(from: components), calendar.component(.day, from: date) == day, calendar.component(.month, from: date) == month else { return nil }
            if date < calendar.startOfDay(for: now) { components.year = currentYear + 1; guard let next = calendar.date(from: components) else { return nil }; date = next }
            return format(date, calendar: calendar)
        }
        let weekdays = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        if let target = weekdays.firstIndex(of: String(value.prefix(3))), value.allSatisfy(\.isLetter) {
            let current = calendar.component(.weekday, from: now) - 1
            var delta = (target - current + 7) % 7
            if delta == 0 { delta = 7 }
            return format(shift(now, days: delta, calendar: calendar), calendar: calendar)
        }
        return nil
    }

    private static func shift(_ date: Date, days: Int, calendar: Calendar) -> Date { calendar.date(byAdding: .day, value: days, to: date) ?? date }
    private static func format(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
