import Foundation

public enum Workspace: String, CaseIterable, Codable, Identifiable, Sendable {
    case rack
    case chrono
    case pending
    case roster
    case tally
    case dispatch

    public var id: Self { self }

    public var title: String {
        switch self {
        case .rack: "RACK"
        case .chrono: "CHRONO"
        case .pending: "PENDING"
        case .roster: "ROSTER"
        case .tally: "TALLY"
        case .dispatch: "DISPATCH"
        }
    }

    public var symbol: String {
        switch self {
        case .rack: "calendar.day.timeline.left"
        case .chrono: "timer"
        case .pending: "checklist"
        case .roster: "list.bullet.clipboard"
        case .tally: "chart.bar.xaxis"
        case .dispatch: "bubble.left.and.bubble.right"
        }
    }

    public var shortcut: Character {
        switch self {
        case .rack: "1"
        case .chrono: "2"
        case .pending: "3"
        case .roster: "4"
        case .tally: "5"
        case .dispatch: "6"
        }
    }
}

public enum SyllabusStatus: String, CaseIterable, Codable, Sendable {
    case notStarted = "NS"
    case learning = "L"
    case practiced = "P"
    case examReady = "ER"
    case finished = "F"

    public var next: Self {
        let values = Self.allCases
        let index = values.firstIndex(of: self) ?? 0
        return values[(index + 1) % values.count]
    }
}

public enum HomeworkPriority: String, CaseIterable, Codable, Sendable {
    case high = "High"
    case normal = "Normal"
    case low = "Low"

    public var scoreAdjustment: Int {
        switch self {
        case .high: 100
        case .normal: 50
        case .low: 10
        }
    }
}

public enum HomeworkStatus: String, Codable, Sendable {
    case open
    case done
}

public struct Block: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var course: String
    public var topic: String?
    public var blockType: String
    public var durationRange: String
    public var source: String
    public var action: String
    public var output: String
    public var benchmark: String

    public var id: String { [course, topic ?? "", blockType].joined(separator: "\u{1F}") }

    public init(
        course: String,
        topic: String?,
        blockType: String,
        durationRange: String,
        source: String,
        action: String,
        output: String,
        benchmark: String
    ) {
        self.course = course
        self.topic = topic
        self.blockType = blockType
        self.durationRange = durationRange
        self.source = source
        self.action = action
        self.output = output
        self.benchmark = benchmark
    }
}

public struct SyllabusItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var subject: String
    public var unit: String
    public var chapter: String
    public var marksWeight: String
    public var status: SyllabusStatus
    public var evidence: String

    public var id: String { [subject, unit, chapter].joined(separator: "\u{1F}") }

    public init(subject: String, unit: String, chapter: String, marksWeight: String, status: SyllabusStatus, evidence: String) {
        self.subject = subject
        self.unit = unit
        self.chapter = chapter
        self.marksWeight = marksWeight
        self.status = status
        self.evidence = evidence
    }
}

public struct CourseCursor: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var course: String
    public var lastTopic: String?
    public var lastBlockType: String?
    public var date: String

    public var id: String { course }

    public init(course: String, lastTopic: String?, lastBlockType: String?, date: String) {
        self.course = course
        self.lastTopic = lastTopic
        self.lastBlockType = lastBlockType
        self.date = date
    }
}

public struct HomeworkItem: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String
    public var subject: String
    public var task: String
    public var dueDate: String
    public var estimatedMinutes: Int
    public var priority: HomeworkPriority
    public var status: HomeworkStatus
    public var createdAt: String

    public init(
        id: String,
        subject: String,
        task: String,
        dueDate: String,
        estimatedMinutes: Int,
        priority: HomeworkPriority,
        status: HomeworkStatus,
        createdAt: String
    ) {
        self.id = id
        self.subject = subject
        self.task = task
        self.dueDate = dueDate
        self.estimatedMinutes = estimatedMinutes
        self.priority = priority
        self.status = status
        self.createdAt = createdAt
    }
}

public enum ScheduleReferenceType: String, Codable, Sendable {
    case course
    case homework
    case fixed
}

public struct ScheduleSlot: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var startTime: String
    public var durationMinutes: Int
    public var referenceType: ScheduleReferenceType
    public var referenceLabel: String

    public var id: String { startTime }

    public init(startTime: String, durationMinutes: Int, referenceType: ScheduleReferenceType, referenceLabel: String) {
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.referenceType = referenceType
        self.referenceLabel = referenceLabel
    }
}

public enum TimeLogReferenceType: String, Codable, Sendable {
    case course
    case homework
}

public struct TimeLogEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var date: String
    public var referenceType: TimeLogReferenceType
    public var referenceLabel: String
    public var course: String?
    public var topic: String?
    public var blockType: String?
    public var startedAt: String
    public var stoppedAt: String
    public var minutes: Int

    public var id: String { [startedAt, stoppedAt, referenceLabel].joined(separator: "\u{1F}") }

    public init(
        date: String,
        referenceType: TimeLogReferenceType,
        referenceLabel: String,
        course: String?,
        topic: String?,
        blockType: String?,
        startedAt: String,
        stoppedAt: String,
        minutes: Int
    ) {
        self.date = date
        self.referenceType = referenceType
        self.referenceLabel = referenceLabel
        self.course = course
        self.topic = topic
        self.blockType = blockType
        self.startedAt = startedAt
        self.stoppedAt = stoppedAt
        self.minutes = minutes
    }
}

public struct CourseStatistics: Equatable, Sendable, Identifiable {
    public var course: String
    public var totalMinutes: Int
    public var completedTasks: Int
    public var totalTasks: Int

    public var id: String { course }
    public var percentComplete: Int { totalTasks == 0 ? 0 : Int((Double(completedTasks) / Double(totalTasks) * 100).rounded()) }

    public init(course: String, totalMinutes: Int, completedTasks: Int, totalTasks: Int) {
        self.course = course
        self.totalMinutes = totalMinutes
        self.completedTasks = completedTasks
        self.totalTasks = totalTasks
    }
}

public struct HomeworkStatistics: Equatable, Sendable {
    public var totalMinutes: Int
    public var completedCount: Int
    public var totalCount: Int

    public var percentComplete: Int { totalCount == 0 ? 0 : Int((Double(completedCount) / Double(totalCount) * 100).rounded()) }

    public init(totalMinutes: Int, completedCount: Int, totalCount: Int) {
        self.totalMinutes = totalMinutes
        self.completedCount = completedCount
        self.totalCount = totalCount
    }
}

public struct TimerTarget: Codable, Equatable, Hashable, Sendable {
    public var referenceType: TimeLogReferenceType
    public var referenceLabel: String
    public var course: String?
    public var topic: String?
    public var blockType: String?
    public var homeworkID: String?

    public init(
        referenceType: TimeLogReferenceType,
        referenceLabel: String,
        course: String?,
        topic: String?,
        blockType: String?,
        homeworkID: String? = nil
    ) {
        self.referenceType = referenceType
        self.referenceLabel = referenceLabel
        self.course = course
        self.topic = topic
        self.blockType = blockType
        self.homeworkID = homeworkID
    }
}

public struct ActiveTimer: Codable, Equatable, Sendable {
    public var startedAt: Date
    public var target: TimerTarget

    public init(startedAt: Date, target: TimerTarget) {
        self.startedAt = startedAt
        self.target = target
    }
}

public enum AssistantProvider: String, CaseIterable, Codable, Sendable {
    case claude
    case codex
    case antigravity
}

public enum AssistantMode: String, Codable, Sendable {
    case ask
    case research
}

public struct Proposal: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var file: String
    public var newContent: String
    public var appliedAt: String?
    public var approvalDigest: String?

    public var id: String { file }

    public init(file: String, newContent: String, appliedAt: String? = nil, approvalDigest: String? = nil) {
        self.file = file
        self.newContent = newContent
        self.appliedAt = appliedAt
        self.approvalDigest = approvalDigest
    }
}

public struct AssistantMessage: Codable, Equatable, Sendable, Identifiable {
    public enum Role: String, Codable, Sendable { case user, assistant }

    public var role: Role
    public var text: String
    public var proposals: [Proposal]?
    public var attachments: [String]?
    public var timestamp: String

    public var id: String { [timestamp, role.rawValue].joined(separator: "\u{1F}") }

    public init(role: Role, text: String, proposals: [Proposal]? = nil, attachments: [String]? = nil, timestamp: String) {
        self.role = role
        self.text = text
        self.proposals = proposals
        self.attachments = attachments
        self.timestamp = timestamp
    }
}

public struct AssistantSession: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var provider: AssistantProvider
    public var mode: AssistantMode
    public var model: String
    public var effort: String
    public var courseName: String?
    public var claudeSessionID: String?
    public var codexSessionID: String?
    public var createdAt: String
    public var updatedAt: String
    public var messages: [AssistantMessage]

    enum CodingKeys: String, CodingKey {
        case id, provider, mode, model, effort, courseName
        case claudeSessionID = "claudeSessionId"
        case codexSessionID = "codexSessionId"
        case createdAt, updatedAt, messages
    }

    public init(
        id: String,
        provider: AssistantProvider,
        mode: AssistantMode,
        model: String,
        effort: String,
        courseName: String? = nil,
        claudeSessionID: String? = nil,
        codexSessionID: String? = nil,
        createdAt: String,
        updatedAt: String,
        messages: [AssistantMessage] = []
    ) {
        self.id = id
        self.provider = provider
        self.mode = mode
        self.model = model
        self.effort = effort
        self.courseName = courseName
        self.claudeSessionID = claudeSessionID
        self.codexSessionID = codexSessionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }
}
