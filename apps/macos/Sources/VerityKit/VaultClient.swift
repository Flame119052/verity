import Foundation
import VerityAI
import VerityDomain
import VerityVault

public struct VaultSnapshot: Sendable {
    public var homework: [HomeworkItem]
    public var schedule: [ScheduleSlot]
    public var blocks: [Block]
    public var syllabus: [SyllabusItem]
    public var cursors: [CourseCursor]
    public var timeLogs: [TimeLogEntry]
    public var sessions: [AssistantSession]

    public init(homework: [HomeworkItem], schedule: [ScheduleSlot], blocks: [Block], syllabus: [SyllabusItem], cursors: [CourseCursor], timeLogs: [TimeLogEntry], sessions: [AssistantSession]) {
        self.homework = homework
        self.schedule = schedule
        self.blocks = blocks
        self.syllabus = syllabus
        self.cursors = cursors
        self.timeLogs = timeLogs
        self.sessions = sessions
    }
}

public actor VaultClient {
    public let root: URL
    private let homework: HomeworkRepository
    private let schedule: ScheduleRepository
    private let timeLog: TimeLogRepository
    private let cursor: CourseCursorRepository
    private let syllabus: SyllabusRepository
    private let blockParser: BlockLibraryParser
    private let assistant: AssistantService

    public init(root: URL) {
        self.root = root
        self.homework = HomeworkRepository(root: root)
        self.schedule = ScheduleRepository(root: root)
        self.timeLog = TimeLogRepository(root: root)
        self.cursor = CourseCursorRepository(root: root)
        self.syllabus = SyllabusRepository(root: root)
        self.blockParser = BlockLibraryParser(root: root)
        self.assistant = AssistantService(root: root)
    }

    public func snapshot(date: String) async throws -> VaultSnapshot {
        async let homeworkItems = homework.load()
        async let scheduleSlots = schedule.load(date: date)
        async let syllabusItems = syllabus.load()
        async let courseCursors = cursor.load()
        async let timeLogs = timeLog.load()
        async let assistantSessions = assistant.listSessions()
        let blocks = blockParser.parse()
        return try await VaultSnapshot(
            homework: homeworkItems,
            schedule: scheduleSlots,
            blocks: blocks,
            syllabus: syllabusItems,
            cursors: courseCursors,
            timeLogs: timeLogs,
            sessions: assistantSessions
        )
    }

    public func addHomework(subject: String, task: String, dueDate: String, minutes: Int, priority: HomeworkPriority) async throws -> HomeworkItem {
        try await homework.add(subject: subject, task: task, dueDate: dueDate, estimatedMinutes: minutes, priority: priority)
    }

    public func markHomeworkDone(id: String) async throws -> HomeworkItem? {
        try await homework.markDone(id)
    }

    public func editHomework(_ item: HomeworkItem) async throws -> HomeworkItem? {
        try await homework.update(item.id) { stored in
            stored.subject = item.subject
            stored.task = item.task
            stored.dueDate = item.dueDate
            stored.estimatedMinutes = item.estimatedMinutes
            stored.priority = item.priority
        }
    }

    public func deleteHomework(id: String) async throws -> Bool {
        try await homework.delete(id)
    }

    public func setSchedule(date: String, slot: ScheduleSlot) async throws -> [ScheduleSlot] {
        try await schedule.set(date: date, slot: slot)
    }

    public func schedule(date: String) async throws -> [ScheduleSlot] {
        try await schedule.load(date: date)
    }

    public func deleteSchedule(date: String, startTime: String) async throws -> Bool {
        try await schedule.delete(date: date, startTime: startTime)
    }

    public func updateSchedule(date: String, originalStartTime: String, slot: ScheduleSlot) async throws -> [ScheduleSlot] {
        try await schedule.update(date: date, originalStartTime: originalStartTime, slot: slot)
    }

    public func appendTimeLog(_ entry: TimeLogEntry) async throws {
        try await timeLog.append(entry)
    }

    public func advance(course: String, topic: String?, blockType: String, blocks: [Block]) async throws -> Block? {
        try await cursor.advance(course: course, topic: topic, blockType: blockType, blocks: blocks)
    }

    public func updateSyllabus(subject: String, chapter: String, status: SyllabusStatus) async throws -> SyllabusItem {
        try await syllabus.update(subject: subject, chapter: chapter, status: status)
    }

    public func createSession(mode: AssistantMode, provider: AssistantProvider, model: String, effort: String, courseName: String?) async throws -> AssistantSession {
        try await assistant.create(mode: mode, provider: provider, model: model, effort: effort, courseName: courseName)
    }

    public func deleteSession(id: String) async throws { try await assistant.delete(id: id) }

    public func send(sessionID: String, text: String, attachments: [AssistantAttachment]) async throws -> AssistantSession {
        try await assistant.send(sessionID: sessionID, text: text, attachments: attachments)
    }

    public func providerStatus(_ provider: AssistantProvider) async -> ProviderStatus {
        await assistant.providerStatus(provider)
    }

    public func installProvider(_ provider: AssistantProvider) async throws {
        try await assistant.installProvider(provider)
    }

    public func review(proposals: [Proposal]) async throws -> ProposalReview {
        try await assistant.review(proposals)
    }

    public func apply(review: ProposalReview, sessionID: String?) async throws -> [String] {
        let token = await assistant.authorize(review)
        let files = try await assistant.apply(review, token: token)
        if let sessionID { try await assistant.markApplied(sessionID: sessionID, review: review) }
        return files
    }
}
