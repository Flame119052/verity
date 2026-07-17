import Foundation
import AppKit
import Observation
import ServiceManagement
import UserNotifications

public struct UpdateNotice: Identifiable, Sendable {
    public let id = UUID()
    public var title: String
    public var message: String
    public var releaseURL: URL?
}
import VerityAI
import VerityDomain
import VerityVault

@MainActor
@Observable
public final class AppState {
    public var selectedWorkspace: Workspace
    public var isOnboardingPresented: Bool
    public var selectedVaultURL: URL?
    public var lastError: String?
    public var isLoading = false
    public var homework: [HomeworkItem] = []
    public var schedule: [ScheduleSlot] = []
    public var todaySchedule: [ScheduleSlot] = []
    public var blocks: [Block] = []
    public var syllabus: [SyllabusItem] = []
    public var cursors: [CourseCursor] = []
    public var timeLogs: [TimeLogEntry] = []
    public var sessions: [AssistantSession] = []
    public var selectedSessionID: String?
    public var assistantBusy = false
    public var providerStatuses: [AssistantProvider: ProviderStatus] = [:]
    public var providerSetupBusy: AssistantProvider?
    public var providerSetupMessages: [AssistantProvider: String] = [:]
    public var selectedCourse: String?
    public var selectedDate: String
    public var activeTimer: ActiveTimer?
    public var elapsedSeconds = 0
    public var lastLoggedMinutes: Int?
    public var lastLoggedTarget: TimerTarget?
    public var launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    public var studyRemindersEnabled = UserDefaults.standard.bool(forKey: "studyRemindersEnabled")
    public var requestedNewItemWorkspace: Workspace?
    public var updateNotice: UpdateNotice?
    public var isCheckingForUpdates = false

    private let configurationStore: VaultConfigurationStore
    private let studyTimer: StudyTimer
    private let vaultScaffolder: VaultScaffolder
    private var vaultClient: VaultClient?
    private var timerTicker: Task<Void, Never>?
    private var assistantTask: Task<Void, Never>?
    private var vaultChangePresenter: VaultChangePresenter?
    private var vaultReloadTask: Task<Void, Never>?

    public init(
        selectedWorkspace: Workspace = .rack,
        isOnboardingPresented: Bool = true,
        selectedVaultURL: URL? = nil,
        lastError: String? = nil,
        configurationStore: VaultConfigurationStore = VaultConfigurationStore(),
        studyTimer: StudyTimer = StudyTimer(),
        vaultScaffolder: VaultScaffolder = VaultScaffolder()
    ) {
        self.selectedWorkspace = selectedWorkspace
        self.isOnboardingPresented = isOnboardingPresented
        self.selectedVaultURL = selectedVaultURL
        self.lastError = lastError
        self.selectedDate = Self.dateString(Date())
        self.configurationStore = configurationStore
        self.studyTimer = studyTimer
        self.vaultScaffolder = vaultScaffolder
    }

    public var legacyVaultSuggestion: URL? {
        configurationStore.legacyVaultSuggestion()
    }

    public func restoreVault() async {
        guard selectedVaultURL == nil else { return }
        do {
            if let url = try configurationStore.restore() {
                try await useVault(url, persist: false)
            }
        } catch {
            lastError = error.localizedDescription
            isOnboardingPresented = true
        }
    }

    public func useVault(_ url: URL, persist: Bool = true) async throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isReadableKey, .isWritableKey])
        guard values.isDirectory == true, values.isReadable == true, values.isWritable == true else {
            throw CocoaError(.fileReadNoPermission)
        }
        if persist { try configurationStore.save(vaultURL: url) }
        let client = VaultClient(root: url)
        selectedVaultURL = url
        vaultClient = client
        vaultChangePresenter = VaultChangePresenter(root: url) { [weak self] in
            Task { @MainActor [weak self] in self?.scheduleVaultReload() }
        }
        isOnboardingPresented = false
        await reload()
        await restoreTimer()
    }

    public func createVault(at url: URL) async throws {
        try vaultScaffolder.create(at: url)
        try await useVault(url)
    }

    public func changeVault() {
        selectedVaultURL?.stopAccessingSecurityScopedResource()
        selectedVaultURL = nil
        vaultClient = nil
        vaultChangePresenter = nil
        vaultReloadTask?.cancel()
        vaultReloadTask = nil
        isOnboardingPresented = true
        homework = []
        schedule = []
        todaySchedule = []
    }

    public func requestNewItem(in workspace: Workspace) {
        selectedWorkspace = workspace
        requestedNewItemWorkspace = workspace
    }

    public func revealVaultInFinder() {
        guard let selectedVaultURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selectedVaultURL])
    }

    public func reload() async {
        guard let vaultClient else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            async let snapshotRequest = vaultClient.snapshot(date: selectedDate)
            async let todayScheduleRequest = vaultClient.schedule(date: Self.dateString(Date()))
            let (snapshot, loadedTodaySchedule) = try await (snapshotRequest, todayScheduleRequest)
            homework = snapshot.homework
            let openCount = snapshot.homework.filter { $0.status == .open }.count
            NSApplication.shared.dockTile.badgeLabel = openCount == 0 ? nil : String(openCount)
            schedule = snapshot.schedule
            todaySchedule = loadedTodaySchedule
            await refreshStudyReminders()
            blocks = snapshot.blocks
            syllabus = snapshot.syllabus
            cursors = snapshot.cursors
            timeLogs = snapshot.timeLogs
            sessions = snapshot.sessions
            if selectedCourse == nil || !courses.contains(selectedCourse ?? "") {
                selectedCourse = courses.first
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func scheduleVaultReload() {
        vaultReloadTask?.cancel()
        vaultReloadTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await self?.reload()
        }
    }

    public func shiftSelectedDate(days: Int) async {
        let formatter = Self.dateFormatter
        guard let date = formatter.date(from: selectedDate),
              let shifted = Calendar.current.date(byAdding: .day, value: days, to: date)
        else { return }
        selectedDate = formatter.string(from: shifted)
        await reload()
    }

    public func selectToday() async {
        selectedDate = Self.dateString(Date())
        await reload()
    }

    public func addHomework(subject: String, task: String, dueDate: String, minutes: Int, priority: HomeworkPriority) async {
        guard let vaultClient else { return }
        do {
            _ = try await vaultClient.addHomework(subject: subject, task: task, dueDate: dueDate, minutes: minutes, priority: priority)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func markHomeworkDone(id: String) async {
        guard let vaultClient else { return }
        do {
            _ = try await vaultClient.markHomeworkDone(id: id)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func editHomework(_ item: HomeworkItem) async {
        guard let vaultClient else { return }
        do { _ = try await vaultClient.editHomework(item); await reload() }
        catch { lastError = error.localizedDescription }
    }

    public func deleteHomework(id: String) async {
        guard let vaultClient else { return }
        do {
            _ = try await vaultClient.deleteHomework(id: id)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func addScheduleSlot(_ slot: ScheduleSlot) async {
        guard let vaultClient else { return }
        do {
            _ = try await vaultClient.setSchedule(date: selectedDate, slot: slot)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func deleteScheduleSlot(startTime: String) async {
        guard let vaultClient else { return }
        do {
            _ = try await vaultClient.deleteSchedule(date: selectedDate, startTime: startTime)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func updateScheduleSlot(originalStartTime: String, slot: ScheduleSlot) async {
        guard let vaultClient else { return }
        do { _ = try await vaultClient.updateSchedule(date: selectedDate, originalStartTime: originalStartTime, slot: slot); await reload() }
        catch { lastError = error.localizedDescription }
    }

    public func startTimer(_ target: TimerTarget) async {
        do {
            activeTimer = try await studyTimer.start(target: target)
            lastLoggedMinutes = nil
            startTicker()
        } catch { lastError = error.localizedDescription }
    }

    public func startTimer(for slot: ScheduleSlot) async {
        guard slot.referenceType != .fixed else { return }
        if slot.referenceType == .homework {
            await startTimer(TimerTarget(
                referenceType: .homework,
                referenceLabel: slot.referenceLabel,
                course: nil,
                topic: nil,
                blockType: nil
            ))
            return
        }
        let parts = slot.referenceLabel.components(separatedBy: " · ")
        await startTimer(TimerTarget(
            referenceType: .course,
            referenceLabel: slot.referenceLabel,
            course: parts.first ?? slot.referenceLabel,
            topic: parts.count == 3 ? parts[1] : nil,
            blockType: parts.count >= 2 ? parts.last : nil
        ))
    }

    public func startTimer(for homework: HomeworkItem) async {
        await startTimer(TimerTarget(
            referenceType: .homework,
            referenceLabel: "HW · \(homework.subject) — \(homework.task)",
            course: nil,
            topic: nil,
            blockType: nil,
            homeworkID: homework.id
        ))
    }

    public func stopAndLogTimer() async {
        guard let vaultClient else { return }
        do {
            let completedTarget = activeTimer?.target
            let entry = try await studyTimer.preparedLog()
            try await vaultClient.appendTimeLog(entry)
            try await studyTimer.commitLogged()
            lastLoggedMinutes = entry.minutes
            lastLoggedTarget = completedTarget
            activeTimer = nil
            elapsedSeconds = 0
            timerTicker?.cancel()
            timerTicker = nil
            await reload()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func discardTimer() async {
        do {
            try await studyTimer.discard()
            activeTimer = nil
            elapsedSeconds = 0
            timerTicker?.cancel()
            timerTicker = nil
        } catch { lastError = error.localizedDescription }
    }

    public func completeLastLoggedTarget() async {
        guard let target = lastLoggedTarget, lastLoggedMinutes != nil else { return }
        switch target.referenceType {
        case .course:
            guard let course = target.course, let blockType = target.blockType,
                  let block = blocks.first(where: { $0.course == course && $0.topic == target.topic && $0.blockType == blockType })
            else { return }
            await advance(block)
        case .homework:
            guard let id = target.homeworkID else { return }
            await markHomeworkDone(id: id)
        }
        lastLoggedTarget = nil
        lastLoggedMinutes = nil
    }

    public func startNextSelectedCourse() async {
        guard let course = selectedCourse, let block = nextBlock(course: course) else { return }
        await startTimer(TimerTarget(
            referenceType: .course,
            referenceLabel: [block.course, block.topic, block.blockType].compactMap { $0 }.joined(separator: " · "),
            course: block.course,
            topic: block.topic,
            blockType: block.blockType
        ))
    }

    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastError = nil
        } catch {
            launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            lastError = "Launch at login could not be changed: \(error.localizedDescription)"
        }
    }

    public func setStudyReminders(_ enabled: Bool) {
        if !enabled {
            studyRemindersEnabled = false
            UserDefaults.standard.set(false, forKey: "studyRemindersEnabled")
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            return
        }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                guard granted else {
                    studyRemindersEnabled = false
                    UserDefaults.standard.set(false, forKey: "studyRemindersEnabled")
                    lastError = "Study reminders are disabled in System Settings → Notifications → VERITY."
                    return
                }
                studyRemindersEnabled = true
                UserDefaults.standard.set(true, forKey: "studyRemindersEnabled")
                await refreshStudyReminders()
            } catch {
                studyRemindersEnabled = false
                UserDefaults.standard.set(false, forKey: "studyRemindersEnabled")
                lastError = "Study reminders could not be enabled: \(error.localizedDescription)"
            }
        }
    }

    public func handleSystemResume() async {
        updateElapsed()
        await reload()
    }

    private func refreshStudyReminders() async {
        guard studyRemindersEnabled else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            studyRemindersEnabled = false
            UserDefaults.standard.set(false, forKey: "studyRemindersEnabled")
            return
        }
        center.removeAllPendingNotificationRequests()
        let today = Date()
        let calendar = Calendar.current
        for slot in todaySchedule where slot.referenceType != .fixed {
            let time = slot.startTime.split(separator: ":").compactMap { Int($0) }
            guard time.count == 2,
                  let fireDate = calendar.date(bySettingHour: time[0], minute: time[1], second: 0, of: today),
                  fireDate > Date()
            else { continue }
            let content = UNMutableNotificationContent()
            content.title = "Study strip ready"
            content.body = slot.referenceLabel
            content.sound = .default
            let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let request = UNNotificationRequest(
                identifier: "app.verity.native.schedule.\(Self.dateString(today)).\(slot.startTime)",
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    public func checkForUpdates() async {
        guard !isCheckingForUpdates else { return }
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/Flame119052/verity/releases/latest")!)
            request.timeoutInterval = 15
            request.setValue("VERITY-Native", forHTTPHeaderField: "User-Agent")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let configuration = URLSessionConfiguration.ephemeral
            configuration.waitsForConnectivity = false
            let (data, response) = try await URLSession(configuration: configuration).data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw URLError(.badServerResponse)
            }
            struct Release: Decodable { var tag_name: String; var html_url: URL }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let latest = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            if latest.compare(current, options: .numeric) == .orderedDescending {
                updateNotice = UpdateNotice(title: "VERITY \(latest) is available", message: "Open the signed GitHub release to review and install the update.", releaseURL: release.html_url)
            } else {
                updateNotice = UpdateNotice(title: "VERITY is up to date", message: "You are running version \(current).", releaseURL: nil)
            }
        } catch {
            updateNotice = UpdateNotice(title: "Could not check for updates", message: error.localizedDescription, releaseURL: nil)
        }
    }

    public func diagnosticSummary() -> String {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "development"
        let providerLines = AssistantProvider.allCases.map { provider in
            guard let status = providerStatuses[provider] else { return "\(provider.rawValue): not checked" }
            return "\(provider.rawValue): installed=\(status.installed), authentication=\(status.authentication.rawValue)"
        }
        return ([
            "VERITY Native diagnostics (content redacted)",
            "version: \(version) (\(build))",
            "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "architecture: \(architecture)",
            "vault selected: \(selectedVaultURL != nil)",
            "homework rows: \(homework.count)",
            "today schedule rows: \(todaySchedule.count)",
            "course blocks: \(blocks.count)",
            "syllabus rows: \(syllabus.count)",
            "time-log rows: \(timeLogs.count)",
            "sessions: \(sessions.count)",
            "timer active: \(activeTimer != nil)",
        ] + providerLines).joined(separator: "\n")
    }

    private func restoreTimer() async {
        do {
            activeTimer = try await studyTimer.restore()
            if activeTimer != nil { startTicker() }
        } catch { lastError = error.localizedDescription }
    }

    private func startTicker() {
        timerTicker?.cancel()
        updateElapsed()
        timerTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                self?.updateElapsed()
            }
        }
    }

    private func updateElapsed() {
        guard let activeTimer else {
            elapsedSeconds = 0
            return
        }
        elapsedSeconds = max(0, Int(Date().timeIntervalSince(activeTimer.startedAt)))
    }

    public var elapsedClock: String {
        let hours = elapsedSeconds / 3_600
        let minutes = (elapsedSeconds % 3_600) / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    public var courses: [String] {
        Array(Set(blocks.map(\.course))).sorted()
    }

    public var orderedOpenHomework: [HomeworkItem] {
        (try? DomainRules.scoredHomework(homework, today: Self.dateString(Date())).map(\.item)) ?? homework.filter { $0.status == .open }
    }

    public var nextTodayScheduleSlot: ScheduleSlot? {
        let current = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        return todaySchedule.first { slot in
            let parts = slot.startTime.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] + slot.durationMinutes > current
        }
    }

    public func homeworkUrgencyReason(id: String) -> String? {
        try? DomainRules.scoredHomework(homework, today: Self.dateString(Date())).first(where: { $0.item.id == id })?.reason
    }

    public func breakdown(course: String) -> [(block: Block, status: SyllabusStatus)] {
        blocks.filter { $0.course == course }.map { block in
            let status: SyllabusStatus
            if block.course.hasPrefix("Boards-"),
               let subject = SyllabusRepository.subject(for: block.course),
               let topic = block.topic,
               let match = syllabus.first(where: { $0.subject == subject && SyllabusRepository.chapterMatches($0.chapter, topic) }) {
                status = match.status
            } else {
                status = .notStarted
            }
            return (block, status)
        }
    }

    public func nextBlock(course: String) -> Block? {
        DomainRules.nextBlock(after: cursors.first(where: { $0.course == course }), in: blocks, course: course)
    }

    public func advance(_ block: Block) async {
        guard let vaultClient else { return }
        do {
            _ = try await vaultClient.advance(course: block.course, topic: block.topic, blockType: block.blockType, blocks: blocks)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func cycleSyllabus(for block: Block, current: SyllabusStatus) async {
        guard let vaultClient,
              let subject = SyllabusRepository.subject(for: block.course),
              let chapter = block.topic
        else { return }
        do {
            _ = try await vaultClient.updateSyllabus(subject: subject, chapter: chapter, status: current.next)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func statistics(from: String, to: String) -> (courses: [CourseStatistics], homework: HomeworkStatistics) {
        let filteredLogs = timeLogs.filter { $0.date >= from && $0.date <= to }
        let courseRows = courses.map { course -> CourseStatistics in
            let courseBlocks = blocks.filter { $0.course == course }
            let cursor = cursors.first { $0.course == course }
            let completed: Int
            if let cursor,
               let blockType = cursor.lastBlockType,
               let index = courseBlocks.firstIndex(where: { $0.topic == cursor.lastTopic && $0.blockType == blockType }) {
                completed = index + 1
            } else {
                completed = 0
            }
            let minutes = filteredLogs.filter { $0.referenceType == .course && $0.course == course }.reduce(0) { $0 + $1.minutes }
            return CourseStatistics(course: course, totalMinutes: minutes, completedTasks: completed, totalTasks: courseBlocks.count)
        }
        let homeworkMinutes = filteredLogs.filter { $0.referenceType == .homework }.reduce(0) { $0 + $1.minutes }
        return (
            courseRows,
            HomeworkStatistics(
                totalMinutes: homeworkMinutes,
                completedCount: homework.filter { $0.status == .done }.count,
                totalCount: homework.count
            )
        )
    }

    public func adherence(for slot: ScheduleSlot) -> (status: DomainRules.AdherenceStatus, loggedMinutes: Int) {
        DomainRules.adherence(slot: slot, date: selectedDate, logs: timeLogs)
    }

    public var selectedSession: AssistantSession? {
        sessions.first { $0.id == selectedSessionID }
    }

    public func createSession(mode: AssistantMode, provider: AssistantProvider, model: String, effort: String, courseName: String?) async {
        guard let vaultClient else { return }
        do {
            let session = try await vaultClient.createSession(mode: mode, provider: provider, model: model, effort: effort, courseName: courseName)
            selectedSessionID = session.id
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func deleteSession(id: String) async {
        guard let vaultClient else { return }
        do {
            try await vaultClient.deleteSession(id: id)
            if selectedSessionID == id { selectedSessionID = nil }
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    public func sendMessage(_ text: String, attachments: [AssistantAttachment]) async {
        guard let vaultClient, let id = selectedSessionID else { return }
        assistantBusy = true
        defer { assistantBusy = false }
        do {
            _ = try await vaultClient.send(sessionID: id, text: text, attachments: attachments)
            await reload()
        } catch {
            if !Task.isCancelled { lastError = error.localizedDescription }
            await reload()
        }
    }

    public func beginSendingMessage(_ text: String, attachments: [AssistantAttachment]) {
        guard !assistantBusy else { return }
        assistantTask = Task { [weak self] in
            await self?.sendMessage(text, attachments: attachments)
            self?.assistantTask = nil
        }
    }

    public func cancelAssistantReply() {
        assistantTask?.cancel()
        assistantTask = nil
        assistantBusy = false
    }

    public func refreshProviderStatus(_ provider: AssistantProvider) async {
        guard let vaultClient else { return }
        providerStatuses[provider] = await vaultClient.providerStatus(provider)
    }

    public func setUpProvider(_ provider: AssistantProvider) async {
        guard let vaultClient, providerSetupBusy == nil else { return }
        providerSetupBusy = provider
        providerSetupMessages[provider] = providerStatuses[provider]?.installed == true
            ? "Opening secure sign-in…"
            : "Installing automatically with \(ProviderSetupCommand.installSummary(for: provider))…"
        defer { providerSetupBusy = nil }
        do {
            if providerStatuses[provider]?.installed != true {
                try await vaultClient.installProvider(provider)
            }
            await refreshProviderStatus(provider)
            if providerStatuses[provider]?.authentication == .authenticated {
                providerSetupMessages[provider] = "Ready — installation and credentials detected."
            } else {
                providerSetupMessages[provider] = ProviderSetupCommand.authenticationGuidance(for: provider)
                openProviderLogin(provider)
            }
        } catch {
            providerSetupMessages[provider] = "Setup needs attention."
            lastError = error.localizedDescription
        }
    }

    public func installProvider(_ provider: AssistantProvider) async {
        await setUpProvider(provider)
    }

    public func openProviderLogin(_ provider: AssistantProvider) {
        guard let executable = providerStatuses[provider]?.executablePath else {
            lastError = "Install \(provider.rawValue.capitalized) before opening its login flow."
            return
        }
        do {
            let quotedExecutable = Self.shellQuote(executable)
            let arguments = ProviderSetupCommand.authenticationArguments(for: provider)
                .map(Self.shellQuote)
                .joined(separator: " ")
            let command = arguments.isEmpty ? quotedExecutable : "\(quotedExecutable) \(arguments)"
            let guidance = ProviderSetupCommand.authenticationGuidance(for: provider)
            let script = FileManager.default.temporaryDirectory.appendingPathComponent("verity-\(provider.rawValue)-login-\(UUID().uuidString).command")
            let contents = """
            #!/bin/zsh
            trap 'rm -f -- "$0"' EXIT
            printf '\\033[1;36mVERITY · \(provider.rawValue.uppercased()) SIGN-IN\\033[0m\\n'
            printf '%s\\n\\n' \(Self.shellQuote(guidance))
            \(command)
            status=$?
            printf '\\nSign-in flow finished. Return to VERITY Settings and press Check Status.\\n'
            printf 'Exit status: %s\\n' "$status"
            read -k 1 '?Press any key to close this window…'
            exit "$status"
            """
            try Data(contents.utf8).write(to: script, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch { lastError = "Could not open the login flow: \(error.localizedDescription)" }
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    public func reviewProposals(_ proposals: [Proposal]) async -> ProposalReview? {
        guard let vaultClient else { return nil }
        do {
            return try await vaultClient.review(proposals: proposals)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    public func applyProposalReview(_ review: ProposalReview) async {
        guard let vaultClient else { return }
        do {
            _ = try await vaultClient.apply(review: review, sessionID: selectedSessionID)
            await reload()
        } catch { lastError = error.localizedDescription }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }
}
