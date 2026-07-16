import Foundation
import VerityDomain
import VerityVault

@main
struct VerityVaultSnapshot {
    static func main() async throws {
        let shouldMutate = CommandLine.arguments.dropFirst().first == "--mutate"
        let pathIndex = shouldMutate ? 2 : 1
        guard CommandLine.arguments.indices.contains(pathIndex) else {
            FileHandle.standardError.write(Data("Usage: verity-vault-snapshot [--mutate] <vault>\n".utf8))
            exit(EXIT_FAILURE)
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[pathIndex], isDirectory: true)
        if shouldMutate { try await mutate(root) }
        let homework = try await HomeworkRepository(root: root).load().map {
            ["id": $0.id, "subject": $0.subject, "task": $0.task, "due_date": $0.dueDate,
             "est_minutes": $0.estimatedMinutes, "priority_tag": $0.priority.rawValue,
             "status": $0.status.rawValue, "created_at": $0.createdAt] as [String: Any]
        }
        let schedule = try await ScheduleRepository(root: root).load(date: "2026-07-16").map {
            ["start_time": $0.startTime, "duration_min": $0.durationMinutes,
             "ref_type": $0.referenceType.rawValue, "ref_label": $0.referenceLabel] as [String: Any]
        }
        let cursors = try await CourseCursorRepository(root: root).load().map {
            ["course": $0.course, "lastTopic": json($0.lastTopic),
             "lastBlockType": json($0.lastBlockType), "date": $0.date] as [String: Any]
        }
        let logs = try await TimeLogRepository(root: root).load().map {
            ["date": $0.date, "ref_type": $0.referenceType.rawValue, "ref_label": $0.referenceLabel,
             "course": json($0.course), "topic": json($0.topic), "blockType": json($0.blockType),
             "started_at": $0.startedAt, "stopped_at": $0.stoppedAt, "minutes": $0.minutes] as [String: Any]
        }
        let syllabus = try await SyllabusRepository(root: root).load().map {
            ["subject": $0.subject, "unit": $0.unit, "chapter": $0.chapter,
             "marksWeight": $0.marksWeight, "status": $0.status.rawValue, "evidence": $0.evidence]
        }
        let blocks = BlockLibraryParser(root: root).parse().sorted {
            [$0.course, $0.topic ?? "", $0.blockType].joined(separator: "\u{1F}")
                < [$1.course, $1.topic ?? "", $1.blockType].joined(separator: "\u{1F}")
        }.map {
            ["course": $0.course, "topic": json($0.topic), "blockType": $0.blockType,
             "durationRange": $0.durationRange, "source": $0.source, "action": $0.action,
             "output": $0.output, "benchmark": $0.benchmark] as [String: Any]
        }
        let snapshot: [String: Any] = [
            "homework": homework, "schedule": schedule, "cursors": cursors,
            "logs": logs, "syllabus": syllabus, "blocks": blocks,
        ]
        let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted])
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data("\n".utf8))
    }

    private static func json(_ value: String?) -> Any {
        value.map { $0 as Any } ?? NSNull()
    }

    private static func mutate(_ root: URL) async throws {
        _ = try await HomeworkRepository(root: root).markDone("hw-1")
        _ = try await ScheduleRepository(root: root).set(
            date: "2026-07-16",
            slot: ScheduleSlot(startTime: "10:00", durationMinutes: 30, referenceType: .homework, referenceLabel: "HW · Mathematics — Corrections")
        )
        _ = try await SyllabusRepository(root: root).update(subject: "Mathematics", chapter: "Algebra", status: .practiced)
        try await TimeLogRepository(root: root).append(TimeLogEntry(
            date: "2026-07-16",
            referenceType: .homework,
            referenceLabel: "HW · Mathematics — Corrections",
            course: nil,
            topic: nil,
            blockType: nil,
            startedAt: "2026-07-16T10:00:00Z",
            stoppedAt: "2026-07-16T10:30:00Z",
            minutes: 30
        ))
    }
}
