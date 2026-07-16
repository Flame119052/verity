import Foundation
import VerityDomain

public enum StudyTimerError: Error, Equatable, LocalizedError, Sendable {
    case alreadyRunning
    case notRunning

    public var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A study timer is already running."
        case .notRunning: "No study timer is running."
        }
    }
}

public actor StudyTimer {
    private let persistenceURL: URL
    private var active: ActiveTimer?

    public init(persistenceURL: URL? = nil) {
        if let persistenceURL {
            self.persistenceURL = persistenceURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.persistenceURL = support
                .appendingPathComponent("VERITY Native", isDirectory: true)
                .appendingPathComponent("active-timer.json")
        }
    }

    public func restore() throws -> ActiveTimer? {
        if let active { return active }
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return nil }
        let decoded = try JSONDecoder().decode(ActiveTimer.self, from: Data(contentsOf: persistenceURL))
        active = decoded
        return decoded
    }

    @discardableResult
    public func start(target: TimerTarget, at date: Date = Date()) throws -> ActiveTimer {
        guard active == nil, !FileManager.default.fileExists(atPath: persistenceURL.path) else {
            throw StudyTimerError.alreadyRunning
        }
        let timer = ActiveTimer(startedAt: date, target: target)
        try FileManager.default.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(timer).write(to: persistenceURL, options: [.atomic])
        active = timer
        return timer
    }

    public func preparedLog(stoppingAt stop: Date = Date(), calendar: Calendar = .current) throws -> TimeLogEntry {
        guard let active else { throw StudyTimerError.notRunning }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return TimeLogEntry(
            date: formatter.string(from: active.startedAt),
            referenceType: active.target.referenceType,
            referenceLabel: active.target.referenceLabel,
            course: active.target.course,
            topic: active.target.topic,
            blockType: active.target.blockType,
            startedAt: ISO8601DateFormatter().string(from: active.startedAt),
            stoppedAt: ISO8601DateFormatter().string(from: stop),
            minutes: DomainRules.logMinutes(start: active.startedAt, stop: stop)
        )
    }

    public func commitLogged() throws {
        guard active != nil else { throw StudyTimerError.notRunning }
        try clearPersistence()
        active = nil
    }

    public func discard() throws {
        guard active != nil || FileManager.default.fileExists(atPath: persistenceURL.path) else {
            throw StudyTimerError.notRunning
        }
        try clearPersistence()
        active = nil
    }

    private func clearPersistence() throws {
        if FileManager.default.fileExists(atPath: persistenceURL.path) {
            try FileManager.default.removeItem(at: persistenceURL)
        }
    }
}
