import Foundation
import VerityDomain

public actor SessionRepository {
    private let root: URL
    private let access: CoordinatedFileAccess
    private var fingerprints: [String: FileFingerprint] = [:]

    public init(root: URL) {
        self.root = root
        self.access = CoordinatedFileAccess(root: root)
    }

    public func create(mode: AssistantMode, provider: AssistantProvider, model: String, effort: String, courseName: String? = nil) throws -> AssistantSession {
        if mode == .research, courseName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            throw SessionRepositoryError.researchCourseRequired
        }
        let now = ISO8601DateFormatter().string(from: Date())
        let session = AssistantSession(id: UUID().uuidString.lowercased(), provider: provider, mode: mode, model: model, effort: effort, courseName: courseName, createdAt: now, updatedAt: now)
        try persist(session)
        return session
    }

    public func get(_ id: String) throws -> AssistantSession? {
        try DomainRules.validateIdentifier(id)
        let path = sessionPath(id)
        guard try access.exists(path) else { return nil }
        let result = try access.read(path)
        fingerprints[id] = result.fingerprint
        return try JSONDecoder().decode(AssistantSession.self, from: Data(result.content.utf8))
    }

    public func list() throws -> [AssistantSession] {
        let directory = root.appendingPathComponent("Progress/Sessions", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .compactMap { try? get($0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func append(_ message: AssistantMessage, to id: String, continuationID: String? = nil) throws -> AssistantSession {
        guard var session = try get(id) else { throw SessionRepositoryError.notFound(id) }
        session.messages.append(message)
        session.updatedAt = ISO8601DateFormatter().string(from: Date())
        if let continuationID {
            switch session.provider {
            case .claude: session.claudeSessionID = continuationID
            case .codex: session.codexSessionID = continuationID
            case .antigravity: break
            }
        }
        try persist(session)
        return session
    }

    public func delete(_ id: String) throws {
        try DomainRules.validateIdentifier(id)
        let jsonPath = sessionPath(id)
        if try access.exists(jsonPath) {
            let result = try access.read(jsonPath)
            try access.remove(jsonPath, expectedFingerprint: result.fingerprint)
            fingerprints.removeValue(forKey: id)
        }
        let attachmentFolder = "Progress/Sessions/\(id)"
        if try access.exists(attachmentFolder) { try access.remove(attachmentFolder) }
    }

    public func markApplied(sessionID: String, review: ProposalReviewSnapshot, appliedAt: String) throws -> AssistantSession {
        guard var session = try get(sessionID) else { throw SessionRepositoryError.notFound(sessionID) }
        let reviewed = Dictionary(uniqueKeysWithValues: review.proposals.map { (($0.file + "\u{1F}" + $0.newContent), true) })
        for messageIndex in session.messages.indices {
            guard var proposals = session.messages[messageIndex].proposals else { continue }
            for proposalIndex in proposals.indices {
                let key = proposals[proposalIndex].file + "\u{1F}" + proposals[proposalIndex].newContent
                if reviewed[key] == true {
                    proposals[proposalIndex].appliedAt = appliedAt
                    proposals[proposalIndex].approvalDigest = review.digest
                }
            }
            session.messages[messageIndex].proposals = proposals
        }
        session.updatedAt = appliedAt
        try persist(session)
        return session
    }

    private func persist(_ session: AssistantSession) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let text = String(decoding: try encoder.encode(session), as: UTF8.self)
        let expected = fingerprints[session.id]
        fingerprints[session.id] = try access.write(
            text,
            to: sessionPath(session.id),
            expectedFingerprint: expected,
            requireAbsent: expected == nil
        )
    }

    private func sessionPath(_ id: String) -> String { "Progress/Sessions/\(id).json" }
}

public struct ProposalReviewSnapshot: Sendable {
    public var proposals: [Proposal]
    public var digest: String

    public init(proposals: [Proposal], digest: String) {
        self.proposals = proposals
        self.digest = digest
    }
}

public enum SessionRepositoryError: Error, LocalizedError, Sendable {
    case notFound(String)
    case researchCourseRequired

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "DISPATCH session not found: \(id)"
        case .researchCourseRequired: "Research sessions require a course."
        }
    }
}
