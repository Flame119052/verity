import Foundation
import VerityDomain
import VerityVault

public struct AssistantAttachment: Sendable {
    public var filename: String
    public var data: Data

    public init(filename: String, data: Data) {
        self.filename = filename
        self.data = data
    }
}

public enum AssistantAttachmentPolicy {
    public static let maximumBytes = 25 * 1_024 * 1_024
    public static let maximumAntigravityInlineBytes = 200 * 1_024

    public static func validatedFilenames(_ attachments: [AssistantAttachment]) throws -> [String] {
        var seen = Set<String>()
        return try attachments.map { attachment in
            guard attachment.data.count <= maximumBytes else { throw AssistantServiceError.attachmentTooLarge(attachment.filename) }
            let filename = URL(fileURLWithPath: attachment.filename).lastPathComponent
            guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("\0") else {
                throw AssistantServiceError.invalidAttachmentName
            }
            guard seen.insert(filename.lowercased()).inserted else { throw AssistantServiceError.duplicateAttachmentName(filename) }
            return filename
        }
    }

    public static func antigravityInlineText(_ attachment: AssistantAttachment) -> String? {
        guard attachment.data.count <= maximumAntigravityInlineBytes,
              !attachment.data.contains(0),
              let value = String(data: attachment.data, encoding: .utf8)
        else { return nil }
        return "\n--- \(URL(fileURLWithPath: attachment.filename).lastPathComponent) ---\n\(value)\n"
    }
}

public struct ProviderStatus: Equatable, Sendable {
    public enum Authentication: String, Sendable { case authenticated, notAuthenticated, unknown }
    public var installed: Bool
    public var authentication: Authentication
    public var executablePath: String?

    public init(installed: Bool, authentication: Authentication, executablePath: String?) {
        self.installed = installed
        self.authentication = authentication
        self.executablePath = executablePath
    }
}

public actor AssistantService {
    private let root: URL
    private let sessions: SessionRepository
    private let runner: ProviderProcessRunner
    private let access: CoordinatedFileAccess
    private let proposalApplier: VaultProposalApplier
    private var busySessions: Set<String> = []

    public init(root: URL, runner: ProviderProcessRunner = ProviderProcessRunner()) {
        self.root = root
        self.sessions = SessionRepository(root: root)
        self.runner = runner
        self.access = CoordinatedFileAccess(root: root)
        self.proposalApplier = VaultProposalApplier(root: root)
    }

    public func listSessions() async throws -> [AssistantSession] { try await sessions.list() }
    public func session(id: String) async throws -> AssistantSession? { try await sessions.get(id) }
    public func create(mode: AssistantMode, provider: AssistantProvider, model: String, effort: String, courseName: String?) async throws -> AssistantSession {
        try await sessions.create(mode: mode, provider: provider, model: model, effort: effort, courseName: courseName)
    }
    public func delete(id: String) async throws { try await sessions.delete(id) }

    public func providerStatus(_ provider: AssistantProvider) async -> ProviderStatus {
        let executableName = provider == .antigravity ? "agy" : provider.rawValue
        let executable = try? await runner.resolveExecutable(named: executableName)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let authentication: ProviderStatus.Authentication
        switch provider {
        case .claude:
            if FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude.json").path) { authentication = .authenticated }
            else if FileManager.default.fileExists(atPath: home.appendingPathComponent(".claude").path) { authentication = .unknown }
            else { authentication = .notAuthenticated }
        case .codex:
            if FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex/auth.json").path) { authentication = .authenticated }
            else if FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) { authentication = .unknown }
            else { authentication = .notAuthenticated }
        case .antigravity:
            authentication = .unknown
        }
        return ProviderStatus(installed: executable != nil, authentication: authentication, executablePath: executable?.path)
    }

    public func installProvider(_ provider: AssistantProvider) async throws {
        guard provider != .antigravity else { throw AssistantServiceError.manualAntigravityInstall }
        let package = provider == .claude ? "@anthropic-ai/claude-code" : "@openai/codex"
        let npm = try await runner.resolveExecutable(named: "npm")
        _ = try await runner.run(executable: npm, arguments: ["install", "-g", package], workingDirectory: FileManager.default.homeDirectoryForCurrentUser)
        let status = await providerStatus(provider)
        guard status.installed else { throw AssistantServiceError.installDidNotExposeExecutable(provider.rawValue) }
    }

    public func send(sessionID: String, text: String, attachments: [AssistantAttachment] = []) async throws -> AssistantSession {
        guard !text.isEmpty else { throw AssistantServiceError.emptyMessage }
        guard text.count <= 100_000 else { throw AssistantServiceError.messageTooLong(text.count) }
        guard !busySessions.contains(sessionID) else { throw AssistantServiceError.sessionBusy }
        guard busySessions.count < 2 else { throw AssistantServiceError.globalCapacity }
        busySessions.insert(sessionID)
        defer { busySessions.remove(sessionID) }
        guard let session = try await sessions.get(sessionID) else { throw SessionRepositoryError.notFound(sessionID) }

        let attachmentPaths = try save(attachments: attachments, sessionID: sessionID)
        let prompt = buildPrompt(text: text, attachmentPaths: attachmentPaths, attachments: attachments, session: session)
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await sessions.append(
            AssistantMessage(role: .user, text: text, attachments: attachmentPaths.isEmpty ? nil : attachmentPaths, timestamp: now),
            to: sessionID
        )
        let continuationID = session.provider == .claude ? session.claudeSessionID : (session.provider == .codex ? session.codexSessionID : nil)
        let invocation: ProviderInvocation
        switch session.provider {
        case .claude:
            let mcpConfig = Bundle.main.url(forResource: "mcp-config", withExtension: "json")?.path
            invocation = ProviderInvocationBuilder.claude(prompt: prompt, model: session.model, effort: session.effort, resumeSessionID: continuationID, systemPrompt: Self.systemPrompt(session.mode), mcpConfigPath: mcpConfig)
        case .codex:
            invocation = ProviderInvocationBuilder.codex(prompt: prompt, model: session.model, effort: session.effort, resumeSessionID: continuationID, systemPrompt: Self.systemPrompt(session.mode))
        case .antigravity:
            invocation = ProviderInvocationBuilder.antigravity(prompt: prompt, model: session.model, systemPrompt: Self.systemPrompt(session.mode))
        }
        let process = try await runner.run(invocation, workingDirectory: root)
        let output = try ProviderOutputParser.parse(provider: session.provider, stdout: process.stdout)
        let extracted = ProposalExtractor.extract(from: output.resultText)
        return try await sessions.append(
            AssistantMessage(role: .assistant, text: extracted.displayText, proposals: extracted.proposals.isEmpty ? nil : extracted.proposals, timestamp: ISO8601DateFormatter().string(from: Date())),
            to: sessionID,
            continuationID: output.newSessionID
        )
    }

    public func review(_ proposals: [Proposal]) async throws -> ProposalReview {
        try await proposalApplier.review(proposals)
    }

    public func authorize(_ review: ProposalReview) async -> ProposalApprovalToken {
        await proposalApplier.authorize(review)
    }

    public func apply(_ review: ProposalReview, token: ProposalApprovalToken) async throws -> [String] {
        try await proposalApplier.apply(review, using: token)
    }

    public func markApplied(sessionID: String, review: ProposalReview) async throws {
        _ = try await sessions.markApplied(
            sessionID: sessionID,
            review: ProposalReviewSnapshot(proposals: review.entries.map(\.proposal), digest: review.digest),
            appliedAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func save(attachments: [AssistantAttachment], sessionID: String) throws -> [String] {
        var paths: [String] = []
        let filenames = try AssistantAttachmentPolicy.validatedFilenames(attachments)
        for (attachment, filename) in zip(attachments, filenames) {
            let path = "Progress/Sessions/\(sessionID)/attachments/\(filename)"
            _ = try access.writeData(attachment.data, to: path)
            paths.append(path)
        }
        return paths
    }

    private func buildPrompt(text: String, attachmentPaths: [String], attachments: [AssistantAttachment], session: AssistantSession) -> String {
        var prompt: String
        if session.mode == .research && session.messages.isEmpty {
            prompt = "Using the following research material, propose additions or corrections to the course \"\(session.courseName ?? "")\" in this Obsidian vault, following the existing table format in Courses/Boards-Daily-Block-Library.md or Courses/Competition-Daily-Block-Library.md exactly (don't invent new column headers). If you have concrete file changes to propose, include them as a fenced code block labeled json containing a JSON array of {\"file\": \"relative/path.md\", \"newContent\": \"full new file content\"} objects. Do not fabricate facts not in the material below.\n\nMATERIAL:\n\(text)"
        } else {
            prompt = text + "\n\n(If you have concrete vault file changes to propose, include them as a fenced code block labeled json containing a JSON array of {\"file\": ..., \"newContent\": ...} objects. Otherwise just reply normally — most turns won't need this.)"
        }
        if session.provider == .antigravity {
            let inline = attachments.compactMap(AssistantAttachmentPolicy.antigravityInlineText).joined()
            if !inline.isEmpty { prompt += "\n\nAttached files:\n" + inline }
            if !session.messages.isEmpty {
                let transcript = session.messages.suffix(10).map { "\($0.role == .user ? "User" : "Assistant"): \($0.text)" }.joined(separator: "\n\n")
                prompt = "Previous conversation:\n\(transcript)\n\nNew message:\n\(prompt)"
            }
        } else if !attachmentPaths.isEmpty {
            prompt += "\n\nAttached file(s) (read them from the vault):\n" + attachmentPaths.joined(separator: "\n")
        }
        return prompt
    }

    private static func systemPrompt(_ mode: AssistantMode) -> String {
        switch mode {
        case .ask:
            "You are VERITY's in-vault assistant, embedded in a personal study-tracking Obsidian vault app for a student. You have read access to the vault's files and research tools. Have a normal, helpful conversation. If and only if the request clearly implies a concrete vault change, propose it as a fenced json array of {file,newContent}. You cannot write files yourself; every proposal requires explicit approval in VERITY. Never fabricate facts."
        case .research:
            "You are VERITY's course-research assistant. Build exam-relevant study content matching the existing three-stage block tables exactly. Use supplied material as primary context and verify scope when useful. Propose concrete changes as a fenced json array of {file,newContent}. You cannot write files yourself. Never fabricate facts."
        }
    }
}

public enum AssistantServiceError: Error, LocalizedError, Sendable {
    case emptyMessage
    case messageTooLong(Int)
    case sessionBusy
    case globalCapacity
    case attachmentTooLarge(String)
    case invalidAttachmentName
    case duplicateAttachmentName(String)
    case manualAntigravityInstall
    case installDidNotExposeExecutable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyMessage: "Write a message before sending."
        case .messageTooLong(let count): "The message is \(count) characters; the maximum is 100,000."
        case .sessionBusy: "A reply is already in progress for this session."
        case .globalCapacity: "Two provider replies are already running. Wait for one to finish or cancel it."
        case .attachmentTooLarge(let name): "\(name) is larger than 25 MB."
        case .invalidAttachmentName: "An attachment has an invalid filename."
        case .duplicateAttachmentName(let name): "More than one attachment is named \(name). Rename one of them before sending."
        case .manualAntigravityInstall: "Install Antigravity from its official app or CLI page, then ask VERITY to check again."
        case .installDidNotExposeExecutable(let name): "Installation finished, but the \(name) command still was not found. Check your npm global path."
        }
    }
}
