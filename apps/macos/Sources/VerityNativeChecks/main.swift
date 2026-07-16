import Foundation
import VerityAI
import VerityDomain
import VerityKit
import VerityVault

@main
struct VerityNativeChecks {
    static func main() async throws {
        var checks = Checks()
        checks.expect(Markdown.sanitizeCell("alpha|beta\ngamma") == "alpha❘beta gamma", "Markdown cell sanitation")
        checks.expect(Markdown.parseTable("| a | b |\n| --- | --- |\n| 1 | 2 |").first == ["a": "1", "b": "2"], "Markdown table parsing")
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let quickHomework = HomeworkQuickParser.parse("Science: lab report due 12/07 45m high", now: Date(timeIntervalSince1970: 1_767_225_600), calendar: utcCalendar)
        checks.expect(quickHomework == ParsedHomework(subject: "Science", task: "lab report", dueDate: "2026-07-12", estimatedMinutes: 45, priority: .high), "Homework quick-add compatibility")
        checks.expect(HomeworkQuickParser.parse("Math: exercise due 31/02 20m", now: Date(timeIntervalSince1970: 1_767_225_600), calendar: utcCalendar)?.task.contains("31/02") == true, "Homework quick-add rejects impossible dates")
        let adherenceSlot = ScheduleSlot(startTime: "09:00", durationMinutes: 60, referenceType: .course, referenceLabel: "Boards-Mathematics · Algebra · First Pass")
        let adherenceLog = TimeLogEntry(date: "2026-01-01", referenceType: .course, referenceLabel: "Maths", course: "Boards-Mathematics", topic: "Algebra", blockType: "First Pass", startedAt: "", stoppedAt: "", minutes: 54)
        checks.expect(DomainRules.adherence(slot: adherenceSlot, date: "2026-01-01", logs: [adherenceLog], now: Date(timeIntervalSince1970: 1_767_225_600), calendar: utcCalendar).status == .completed, "Schedule adherence preserves 90 percent completion rule")
        checks.expectThrows("Path traversal rejection") {
            _ = try SafeVaultPathResolver(root: URL(fileURLWithPath: "/tmp/verity-check-root")).resolve("../escape")
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("verity-native-checks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try prepareVault(root)

        let coordinatedAccess = CoordinatedFileAccess(root: root)
        let guardedPath = "Notes/Fingerprint-Guard.md"
        let originalFingerprint = try coordinatedAccess.write("original", to: guardedPath, requireAbsent: true)
        try "external edit".write(to: root.appendingPathComponent(guardedPath), atomically: true, encoding: .utf8)
        checks.expectThrows("Coordinated write rejects changed fingerprint") {
            _ = try coordinatedAccess.write("replacement", to: guardedPath, expectedFingerprint: originalFingerprint)
        }
        try FileManager.default.removeItem(at: root.appendingPathComponent(guardedPath))
        checks.expectThrows("Coordinated write rejects deleted expected file") {
            _ = try coordinatedAccess.write("replacement", to: guardedPath, expectedFingerprint: originalFingerprint)
        }
        try "new external file".write(to: root.appendingPathComponent(guardedPath), atomically: true, encoding: .utf8)
        checks.expectThrows("Coordinated create requires absent destination") {
            _ = try coordinatedAccess.write("replacement", to: guardedPath, requireAbsent: true)
        }
        var repeatedFingerprint = try coordinatedAccess.write("0", to: "Notes/Repeated.md", requireAbsent: true)
        for value in 1...100 {
            repeatedFingerprint = try coordinatedAccess.write(String(value), to: "Notes/Repeated.md", expectedFingerprint: repeatedFingerprint)
        }
        let repeatedContent = try coordinatedAccess.read("Notes/Repeated.md").content
        checks.expect(repeatedContent == "100", "Repeated coordinated edits remain consistent")

        let homework = HomeworkRepository(root: root)
        let added = try await homework.add(subject: "Maths", task: "Solve exercise", dueDate: "2026-07-20", estimatedMinutes: 45, priority: .high, now: Date(timeIntervalSince1970: 0))
        let loadedHomework = try await homework.load()
        checks.expect(loadedHomework.contains(where: { $0.id == added.id && $0.priority == .high }), "Homework repository round trip")
        _ = try await homework.markDone(added.id)
        let completedHomework = try await homework.load()
        checks.expect(completedHomework.first(where: { $0.id == added.id })?.status == .done, "Homework completion persistence")

        let schedule = ScheduleRepository(root: root)
        _ = try await schedule.set(date: "2026-07-16", slot: ScheduleSlot(startTime: "10:00", durationMinutes: 45, referenceType: .course, referenceLabel: "Boards-Mathematics · Algebra · First Pass"))
        _ = try await schedule.set(date: "2026-07-16", slot: ScheduleSlot(startTime: "09:00", durationMinutes: 30, referenceType: .fixed, referenceLabel: "Breakfast"))
        let loadedSchedule = try await schedule.load(date: "2026-07-16")
        checks.expect(loadedSchedule.map(\.startTime) == ["09:00", "10:00"], "Schedule stable time ordering")
        var rejectedScheduleCollision = false
        do { _ = try await schedule.update(date: "2026-07-16", originalStartTime: "09:00", slot: ScheduleSlot(startTime: "10:00", durationMinutes: 30, referenceType: .fixed, referenceLabel: "Collision")) }
        catch ScheduleRepositoryError.collision { rejectedScheduleCollision = true }
        catch { }
        checks.expect(rejectedScheduleCollision, "Schedule edit collision protection")

        let blocks = BlockLibraryParser(root: root).parse()
        checks.expect(blocks.contains(where: { $0.course == "Boards-Mathematics" && $0.topic == "Algebra" && $0.blockType == "First Pass" }), "Boards block library parsing")
        let cursor = CourseCursorRepository(root: root)
        let first = blocks.first { $0.course == "Boards-Mathematics" && $0.topic == "Algebra" }
        if let first {
            _ = try await cursor.advance(course: first.course, topic: first.topic, blockType: first.blockType, blocks: blocks)
            let loadedCursors = try await cursor.load()
            checks.expect(loadedCursors.first?.lastBlockType == first.blockType, "Course cursor validation and persistence")
        } else {
            checks.fail("Course cursor validation and persistence", "fixture block missing")
        }

        let syllabus = SyllabusRepository(root: root)
        let initialSyllabus = try await syllabus.load()
        checks.expect(initialSyllabus.first?.status == .notStarted, "Syllabus parse")
        _ = try await syllabus.update(subject: "Mathematics", chapter: "Algebra", status: .learning)
        let updatedSyllabus = try await syllabus.load()
        checks.expect(updatedSyllabus.first?.status == .learning, "Syllabus targeted update")

        let timerURL = root.appendingPathComponent("timer.json")
        let timer = StudyTimer(persistenceURL: timerURL)
        _ = try await timer.start(target: TimerTarget(referenceType: .course, referenceLabel: "Maths", course: "Boards-Mathematics", topic: "Algebra", blockType: "First Pass"), at: Date(timeIntervalSince1970: 0))
        let restoredTimer = try await timer.restore()
        checks.expect(restoredTimer != nil, "Timer recovery")
        let entry = try await timer.preparedLog(stoppingAt: Date(timeIntervalSince1970: 95))
        checks.expect(entry.minutes == 2, "Timer minute rounding")
        let retryableTimer = try await timer.restore()
        checks.expect(retryableTimer != nil, "Prepared timer log remains recoverable until commit")
        try await timer.commitLogged()
        let clearedTimer = try await timer.restore()
        checks.expect(clearedTimer == nil, "Timer commit clears recovery")
        let enduranceTimer = StudyTimer(persistenceURL: root.appendingPathComponent("endurance-timer.json"))
        _ = try await enduranceTimer.start(target: TimerTarget(referenceType: .course, referenceLabel: "Endurance", course: "Course", topic: nil, blockType: "Block"), at: Date(timeIntervalSince1970: 0))
        let dayLog = try await enduranceTimer.preparedLog(stoppingAt: Date(timeIntervalSince1970: 86_400))
        checks.expect(dayLog.minutes == 1_440, "24-hour timer recovery math")
        try await enduranceTimer.discard()
        let discardedTimer = try await enduranceTimer.restore()
        checks.expect(discardedTimer == nil, "Timer discard clears recovery without logging")

        let sessions = SessionRepository(root: root)
        let session = try await sessions.create(mode: .ask, provider: .codex, model: "gpt-5.5", effort: "high")
        _ = try await sessions.append(AssistantMessage(role: .user, text: "Hello", timestamp: "2026-07-16T00:00:00Z"), to: session.id)
        let loadedSession = try await sessions.get(session.id)
        checks.expect(loadedSession?.messages.count == 1, "DISPATCH session persistence")
        let largeSession = try await sessions.create(mode: .ask, provider: .codex, model: "test", effort: "low")
        var largeTranscript = largeSession
        largeTranscript.messages = (0..<500).map {
            AssistantMessage(
                role: $0.isMultiple(of: 2) ? .user : .assistant,
                text: "Message \($0) " + String(repeating: "x", count: 200),
                timestamp: "2026-07-16T00:\(String(format: "%02d", $0 % 60)):00Z"
            )
        }
        let largeSessionPath = root.appendingPathComponent("Progress/Sessions/\(largeSession.id).json")
        let largeEncoder = JSONEncoder()
        largeEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try largeEncoder.encode(largeTranscript).write(to: largeSessionPath, options: [.atomic])
        let reloadedLargeSession = try await sessions.get(largeSession.id)
        checks.expect(reloadedLargeSession?.messages.count == 500, "Large DISPATCH transcript persistence")
        _ = try await sessions.append(AssistantMessage(role: .assistant, text: "Proposal", proposals: [Proposal(file: "Notes/Applied.md", newContent: "content")], timestamp: "2026-07-16T00:00:01Z"), to: session.id)
        _ = try await sessions.markApplied(sessionID: session.id, review: ProposalReviewSnapshot(proposals: [Proposal(file: "Notes/Applied.md", newContent: "content")], digest: "digest"), appliedAt: "2026-07-16T00:00:02Z")
        let appliedSession = try await sessions.get(session.id)
        checks.expect(appliedSession?.messages.last?.proposals?.first?.approvalDigest == "digest", "DISPATCH applied proposal is durably marked")
        let legacyProposal = try JSONDecoder().decode(Proposal.self, from: Data("{\"file\":\"Notes/Legacy.md\",\"newContent\":\"legacy\"}".utf8))
        checks.expect(legacyProposal.appliedAt == nil, "Legacy proposal JSON remains compatible")

        let codexInvocation = ProviderInvocationBuilder.codex(prompt: "Hello", model: "gpt-5.5", effort: "high")
        checks.expect(codexInvocation.arguments.contains("read-only") && codexInvocation.arguments.contains("--json"), "Codex read-only invocation")
        let claudeInvocation = ProviderInvocationBuilder.claude(prompt: "Hello", model: "sonnet", effort: "high")
        checks.expect(claudeInvocation.arguments.contains("Write Edit Bash NotebookEdit"), "Claude mutation-tool denial")
        let agyInvocation = ProviderInvocationBuilder.antigravity(prompt: "Hello", model: "Gemini")
        checks.expect(!agyInvocation.arguments.contains("--add-dir") && agyInvocation.arguments.suffix(2) == ["--mode", "plan"], "Antigravity vault isolation")

        let providerFixture = root.appendingPathComponent("provider-output.txt")
        try Data(repeating: 65, count: 1_024 * 1_024).write(to: providerFixture)
        let providerRunner = ProviderProcessRunner(timeout: .seconds(5), maximumOutputBytes: 2 * 1_024 * 1_024)
        let providerResult = try await providerRunner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [providerFixture.path], workingDirectory: root)
        checks.expect(providerResult.stdout.utf8.count == 1_024 * 1_024, "Provider output drains without pipe deadlock")
        let cappedRunner = ProviderProcessRunner(timeout: .seconds(5), maximumOutputBytes: 512 * 1_024)
        var rejectedOutputFlood = false
        do { _ = try await cappedRunner.run(executable: URL(fileURLWithPath: "/bin/cat"), arguments: [providerFixture.path], workingDirectory: root) }
        catch ProviderProcessError.outputTooLarge { rejectedOutputFlood = true }
        catch { }
        checks.expect(rejectedOutputFlood, "Provider output byte cap")
        let timeoutRunner = ProviderProcessRunner(timeout: .milliseconds(50))
        var timedOut = false
        do { _ = try await timeoutRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["2"], workingDirectory: root) }
        catch ProviderProcessError.timedOut { timedOut = true }
        catch { }
        checks.expect(timedOut, "Provider timeout terminates subprocess")
        let cancellationRunner = ProviderProcessRunner(timeout: .seconds(5))
        let cancellationStarted = Date()
        let cancellationTask = Task {
            try await cancellationRunner.run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["5"], workingDirectory: root)
        }
        try? await Task.sleep(for: .milliseconds(50))
        cancellationTask.cancel()
        var cancelledProvider = false
        do { _ = try await cancellationTask.value }
        catch is CancellationError { cancelledProvider = true }
        catch { cancelledProvider = true }
        checks.expect(cancelledProvider && Date().timeIntervalSince(cancellationStarted) < 1, "Provider task cancellation terminates subprocess")
        var preservedExitCode = false
        do { _ = try await providerRunner.run(executable: URL(fileURLWithPath: "/usr/bin/false"), arguments: [], workingDirectory: root) }
        catch ProviderProcessError.failed(let code, _) { preservedExitCode = code != 0 }
        catch { }
        checks.expect(preservedExitCode, "Provider non-zero exit is preserved")

        let fakeBin = root.appendingPathComponent("fake-bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        let fakeCodex = fakeBin.appendingPathComponent("codex")
        try Data("""
        #!/bin/sh
        sleep 0.2
        printf '%s\n' '{"type":"thread.started","thread_id":"fake"}' '{"type":"item.completed","item":{"type":"agent_message","text":"Done"}}'
        """.utf8).write(to: fakeCodex)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fakeCodex.path)
        var fakeEnvironment = ProcessInfo.processInfo.environment
        fakeEnvironment["PATH"] = fakeBin.path + ":/usr/bin:/bin"
        let fakeAssistant = AssistantService(root: root, runner: ProviderProcessRunner(timeout: .seconds(3), environment: fakeEnvironment))
        let concurrentA = try await fakeAssistant.create(mode: .ask, provider: .codex, model: "test", effort: "low", courseName: nil)
        let concurrentB = try await fakeAssistant.create(mode: .ask, provider: .codex, model: "test", effort: "low", courseName: nil)
        async let replyA = fakeAssistant.send(sessionID: concurrentA.id, text: "A")
        async let replyB = fakeAssistant.send(sessionID: concurrentB.id, text: "B")
        let concurrentReplies = try await [replyA, replyB]
        checks.expect(concurrentReplies.allSatisfy { $0.messages.last?.text == "Done" }, "Two provider sessions can run concurrently")
        let busyTask = Task { try await fakeAssistant.send(sessionID: concurrentA.id, text: "first") }
        try? await Task.sleep(for: .milliseconds(40))
        var rejectedSameSessionSend = false
        do { _ = try await fakeAssistant.send(sessionID: concurrentA.id, text: "second") }
        catch AssistantServiceError.sessionBusy { rejectedSameSessionSend = true }
        catch { }
        _ = try await busyTask.value
        checks.expect(rejectedSameSessionSend, "Concurrent send to one session is rejected")

        let codexJSONL = """
        {"type":"thread.started","thread_id":"abc"}
        {"type":"item.completed","item":{"type":"agent_message","text":"Done"}}
        """
        let parsed = try ProviderOutputParser.parseCodex(codexJSONL)
        checks.expect(parsed.resultText == "Done" && parsed.newSessionID == "abc", "Codex JSONL parsing")
        checks.expectThrows("Malformed Claude output rejection") { _ = try ProviderOutputParser.parseClaude("{}") }
        checks.expectThrows("Empty Antigravity output rejection") { _ = try ProviderOutputParser.parseAntigravity("thinking\ndone") }
        let extracted = ProposalExtractor.extract(from: "Reply\n```json\n[{\"file\":\"Notes/Test.md\",\"newContent\":\"new\"}]\n```")
        checks.expect(extracted.displayText == "Reply" && extracted.proposals.count == 1, "Proposal extraction")
        let spoofed = ProposalExtractor.extract(from: "```json\n[{\"file\":\"Notes/Test.md\",\"newContent\":\"new\",\"appliedAt\":\"spoofed\",\"approvalDigest\":\"spoofed\"}]\n```")
        checks.expect(spoofed.proposals.first?.appliedAt == nil, "Provider cannot spoof applied proposal state")
        let validAttachments = [
            AssistantAttachment(filename: "notes.txt", data: Data("notes".utf8)),
            AssistantAttachment(filename: "diagram.md", data: Data("diagram".utf8))
        ]
        let validatedAttachmentNames = try AssistantAttachmentPolicy.validatedFilenames(validAttachments)
        checks.expect(validatedAttachmentNames == ["notes.txt", "diagram.md"], "Attachment filename and size validation")
        checks.expectThrows("Duplicate attachment basename rejection") {
            _ = try AssistantAttachmentPolicy.validatedFilenames([
                AssistantAttachment(filename: "/one/Notes.txt", data: Data()),
                AssistantAttachment(filename: "/two/notes.txt", data: Data())
            ])
        }
        checks.expect(AssistantAttachmentPolicy.antigravityInlineText(AssistantAttachment(filename: "binary.bin", data: Data([0, 1, 2]))) == nil, "Antigravity binary attachment isolation")
        let lineDiff = LineDiff.compare(old: "one\ntwo", new: "one\nthree")
        checks.expect(lineDiff?.map(\.kind) == [.unchanged, .removed, .added], "Proposal line diff")

        let proposalFile = root.appendingPathComponent("Notes/Test.md")
        try FileManager.default.createDirectory(at: proposalFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: proposalFile)
        let applier = VaultProposalApplier(root: root)
        let review = try await applier.review([Proposal(file: "Notes/Test.md", newContent: "new")])
        let token = await applier.authorize(review)
        _ = try await applier.apply(review, using: token)
        let appliedContent = try String(contentsOf: proposalFile, encoding: .utf8)
        checks.expect(appliedContent == "new", "Explicit proposal approval and apply")
        let onlyOneReview = try await applier.review([
            Proposal(file: "Notes/Only-One.md", newContent: "first"),
            Proposal(file: "Notes/Leave-Alone.md", newContent: "second")
        ])
        let singleReview = try await applier.review([onlyOneReview.entries[0].proposal])
        let singleToken = await applier.authorize(singleReview)
        _ = try await applier.apply(singleReview, using: singleToken)
        checks.expect(
            FileManager.default.fileExists(atPath: root.appendingPathComponent("Notes/Only-One.md").path)
                && !FileManager.default.fileExists(atPath: root.appendingPathComponent("Notes/Leave-Alone.md").path),
            "Apply One leaves unselected proposal untouched"
        )
        var rejectedReusedToken = false
        do { _ = try await applier.apply(review, using: token) }
        catch { rejectedReusedToken = true }
        checks.expect(rejectedReusedToken, "Approval token is single use")
        let expiredReview = try await applier.review([Proposal(file: "Notes/Test.md", newContent: "expired")])
        let expiredToken = await applier.authorize(expiredReview, lifetime: -1)
        var rejectedExpiredToken = false
        do { _ = try await applier.apply(expiredReview, using: expiredToken) }
        catch ProposalApprovalError.invalidOrExpiredToken { rejectedExpiredToken = true }
        catch { }
        checks.expect(rejectedExpiredToken, "Proposal approval token expiry")

        let staleReview = try await applier.review([Proposal(file: "Notes/Test.md", newContent: "should-not-apply")])
        try Data("external-edit".utf8).write(to: proposalFile, options: [.atomic])
        let staleToken = await applier.authorize(staleReview)
        var rejectedStaleReview = false
        do { _ = try await applier.apply(staleReview, using: staleToken) }
        catch ProposalApprovalError.staleFile { rejectedStaleReview = true }
        catch { }
        let staleContent = try String(contentsOf: proposalFile, encoding: .utf8)
        checks.expect(rejectedStaleReview && staleContent == "external-edit", "Reviewed proposal rejects external edits")

        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("verity-outside-\(UUID().uuidString)")
        try Data("private".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let escapeLink = root.appendingPathComponent("Notes/escape.md")
        try FileManager.default.createSymbolicLink(at: escapeLink, withDestinationURL: outside)
        checks.expectThrows("Symlink escape rejection") {
            _ = try SafeVaultPathResolver(root: root).resolve("Notes/escape.md", allowMissingLeaf: false)
        }

        let rollbackApplier = VaultProposalApplier(root: root)
        let oversizedName = "Notes/" + String(repeating: "x", count: 300) + ".md"
        let rollbackReview = try await rollbackApplier.review([
            Proposal(file: "Notes/New-Then-Rollback.md", newContent: "temporary"),
            Proposal(file: oversizedName, newContent: "must fail")
        ])
        let rollbackToken = await rollbackApplier.authorize(rollbackReview)
        do { _ = try await rollbackApplier.apply(rollbackReview, using: rollbackToken) }
        catch { }
        checks.expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Notes/New-Then-Rollback.md").path), "Proposal batch rollback removes new files")

        let scaffoldURL = FileManager.default.temporaryDirectory.appendingPathComponent("verity-scaffold-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: scaffoldURL) }
        try VaultScaffolder().create(at: scaffoldURL, date: Date(timeIntervalSince1970: 0))
        let requiredScaffoldFiles = [
            "Progress/Homework.md", "Progress/Course-Cursor.md", "Progress/Time-Log.md",
            "Boards/Syllabus-Checklist.md", "Courses/Boards-Daily-Block-Library.md",
            "Courses/Competition-Daily-Block-Library.md"
        ]
        checks.expect(requiredScaffoldFiles.allSatisfy { FileManager.default.fileExists(atPath: scaffoldURL.appendingPathComponent($0).path) }, "New vault scaffold is complete")

        let bulkHomework = (0..<5_000).map { index in
            HomeworkItem(id: "bulk-\(index)", subject: "Subject", task: "Task \(index)", dueDate: "2026-12-31", estimatedMinutes: 30, priority: .normal, status: .open, createdAt: "2026-01-01T00:00:00Z")
        }
        let bulkRendered = HomeworkRepository.render(bulkHomework, today: "2026-01-01")
        checks.expect(HomeworkRepository.parse(bulkRendered).count == 5_000, "Large vault table round trip")

        let stateConfigURL = root.appendingPathComponent("state-config.json")
        let stateTimerURL = root.appendingPathComponent("state-timer.json")
        let appState = await MainActor.run {
            AppState(
                configurationStore: VaultConfigurationStore(configURL: stateConfigURL),
                studyTimer: StudyTimer(persistenceURL: stateTimerURL)
            )
        }
        let bookmarkStore = VaultConfigurationStore(
            configURL: root.appendingPathComponent("bookmark-config.json"),
            useSecurityScopedBookmarks: false
        )
        try bookmarkStore.save(vaultURL: scaffoldURL)
        let restoredBookmarkURL = try bookmarkStore.restore()
        checks.expect(restoredBookmarkURL?.standardizedFileURL == scaffoldURL.standardizedFileURL, "Non-sandbox vault bookmark round trip")
        let beforeNoOp = try contentsSnapshot(scaffoldURL)
        try await appState.useVault(scaffoldURL, persist: false)
        let afterNoOp = try contentsSnapshot(scaffoldURL)
        if beforeNoOp != afterNoOp {
            let changed = Set(beforeNoOp.keys).union(afterNoOp.keys).filter { beforeNoOp[$0] != afterNoOp[$0] }.sorted()
            print("INFO  Byte-stability differences: \(changed.joined(separator: ", "))")
        }
        checks.expect(beforeNoOp == afterNoOp, "Native open and reload are byte-stable")
        let diagnosticSummary = await MainActor.run { appState.diagnosticSummary() }
        checks.expect(!diagnosticSummary.contains(scaffoldURL.path) && diagnosticSummary.contains("content redacted"), "Diagnostics redact vault paths and content")
        await appState.addHomework(subject: "English", task: "Draft response", dueDate: "2026-07-18", minutes: 25, priority: .normal)
        let appStateLoadedHomework = await MainActor.run { appState.homework }
        checks.expect(appStateLoadedHomework.contains(where: { $0.subject == "English" }), "App state orchestrates native vault mutation and reload")
        await MainActor.run { appState.changeVault() }

        checks.finish()
    }

    private static func prepareVault(_ root: URL) throws {
        let boards = root.appendingPathComponent("Courses/Boards-Daily-Block-Library.md")
        let syllabus = root.appendingPathComponent("Boards/Syllabus-Checklist.md")
        try FileManager.default.createDirectory(at: boards.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: syllabus.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        # Blocks

        ## Universal Block Types

        | Block | Duration |
        | --- | --- |
        | First Pass | 45m |
        | Exercise Drill | 60m |

        ## Mathematics Block Bank

        | Chapter | First Pass Output | Drill Output |
        | --- | --- | --- |
        | Algebra | Method sheet | Solved set |
        """.write(to: boards, atomically: true, encoding: .utf8)
        try """
        ---
        type: syllabus
        ---

        # Syllabus Checklist

        ## Mathematics

        | Unit | Chapter | Marks Weight | Status | Evidence |
        | --- | --- | --- | --- | --- |
        | I | Algebra | 10 | NS | - |
        """.write(to: syllabus, atomically: true, encoding: .utf8)
    }

    private static func contentsSnapshot(_ root: URL) throws -> [String: Data] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [:] }
        var snapshot: [String: Data] = [:]
        for case let url as URL in enumerator {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count + 1))
            snapshot[relative] = try Data(contentsOf: url)
        }
        return snapshot
    }
}

private struct Checks {
    private var failures: [(String, String)] = []
    private var total = 0

    mutating func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
        total += 1
        if condition() { print("PASS  \(name)") }
        else { fail(name, "condition was false") }
    }

    mutating func expectThrows(_ name: String, _ operation: () throws -> Void) {
        total += 1
        do {
            try operation()
            fail(name, "expected an error")
        } catch {
            print("PASS  \(name)")
        }
    }

    mutating func fail(_ name: String, _ reason: String) {
        failures.append((name, reason))
        print("FAIL  \(name): \(reason)")
    }

    func finish() -> Never {
        if failures.isEmpty {
            print("\nVERITY native checks passed: \(total)/\(total)")
            exit(EXIT_SUCCESS)
        }
        print("\nVERITY native checks failed: \(failures.count)/\(total)")
        exit(EXIT_FAILURE)
    }
}
