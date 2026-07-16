import Foundation
import VerityDomain
import VerityVault

public struct ProposalReviewEntry: Equatable, Sendable {
    public var proposal: Proposal
    public var originalContent: String?
    public var originalFingerprint: FileFingerprint?

    public init(proposal: Proposal, originalContent: String?, originalFingerprint: FileFingerprint?) {
        self.proposal = proposal
        self.originalContent = originalContent
        self.originalFingerprint = originalFingerprint
    }
}

public struct ProposalReview: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var entries: [ProposalReviewEntry]
    public var digest: String

    public init(id: UUID = UUID(), entries: [ProposalReviewEntry], digest: String) {
        self.id = id
        self.entries = entries
        self.digest = digest
    }
}

public struct ProposalApprovalToken: Hashable, Sendable {
    fileprivate let value: UUID
}

public actor VaultProposalApplier {
    private struct Authorization: Sendable {
        var reviewID: UUID
        var digest: String
        var expiresAt: Date
    }

    private let access: CoordinatedFileAccess
    private var authorizations: [UUID: Authorization] = [:]

    public init(root: URL) {
        self.access = CoordinatedFileAccess(root: root)
    }

    public func review(_ proposals: [Proposal]) throws -> ProposalReview {
        guard !proposals.isEmpty else { throw ProposalApprovalError.empty }
        guard Set(proposals.map(\.file)).count == proposals.count else { throw ProposalApprovalError.duplicatePath }
        var entries: [ProposalReviewEntry] = []
        for proposal in proposals {
            if try access.exists(proposal.file) {
                let original = try access.read(proposal.file)
                entries.append(ProposalReviewEntry(proposal: proposal, originalContent: original.content, originalFingerprint: original.fingerprint))
            } else {
                entries.append(ProposalReviewEntry(proposal: proposal, originalContent: nil, originalFingerprint: nil))
            }
        }
        let data = proposals.flatMap { [Data($0.file.utf8), Data([0]), Data($0.newContent.utf8), Data([0])] }.reduce(into: Data()) { $0.append($1) }
        return ProposalReview(entries: entries, digest: CoordinatedFileAccess.fingerprint(data).sha256)
    }

    public func authorize(_ review: ProposalReview, lifetime: TimeInterval = 120) -> ProposalApprovalToken {
        let token = ProposalApprovalToken(value: UUID())
        authorizations[token.value] = Authorization(reviewID: review.id, digest: review.digest, expiresAt: Date().addingTimeInterval(lifetime))
        return token
    }

    public func apply(_ review: ProposalReview, using token: ProposalApprovalToken) throws -> [String] {
        guard let authorization = authorizations.removeValue(forKey: token.value),
              authorization.reviewID == review.id,
              authorization.digest == review.digest,
              authorization.expiresAt > Date()
        else { throw ProposalApprovalError.invalidOrExpiredToken }

        for entry in review.entries {
            let exists = try access.exists(entry.proposal.file)
            if let fingerprint = entry.originalFingerprint {
                guard exists, try access.read(entry.proposal.file).fingerprint == fingerprint else {
                    throw ProposalApprovalError.staleFile(entry.proposal.file)
                }
            } else if exists {
                throw ProposalApprovalError.staleFile(entry.proposal.file)
            }
        }

        var applied: [ProposalReviewEntry] = []
        do {
            for entry in review.entries {
                _ = try access.write(
                    entry.proposal.newContent,
                    to: entry.proposal.file,
                    expectedFingerprint: entry.originalFingerprint,
                    requireAbsent: entry.originalFingerprint == nil
                )
                applied.append(entry)
            }
            return applied.map { $0.proposal.file }
        } catch {
            var rollbackFailures: [String] = []
            for entry in applied.reversed() {
                if let originalContent = entry.originalContent {
                    do { _ = try access.write(originalContent, to: entry.proposal.file) }
                    catch { rollbackFailures.append(entry.proposal.file) }
                } else if let current = try? access.read(entry.proposal.file) {
                    do { try access.remove(entry.proposal.file, expectedFingerprint: current.fingerprint) }
                    catch { rollbackFailures.append(entry.proposal.file) }
                }
            }
            if !rollbackFailures.isEmpty {
                throw ProposalApprovalError.rollbackFailed(rollbackFailures)
            }
            throw error
        }
    }
}

public enum ProposalApprovalError: Error, LocalizedError, Sendable {
    case empty
    case duplicatePath
    case invalidOrExpiredToken
    case staleFile(String)
    case rollbackFailed([String])

    public var errorDescription: String? {
        switch self {
        case .empty: "There are no proposals to review."
        case .duplicatePath: "A proposal contains the same file more than once."
        case .invalidOrExpiredToken: "Approval expired or does not match the reviewed proposal. Review it again."
        case .staleFile(let file): "\(file) changed after review. Review the updated file before applying."
        case .rollbackFailed(let files): "A proposal batch failed and VERITY could not restore: \(files.joined(separator: ", ")). Stop editing and restore those files from version history or backup."
        }
    }
}
