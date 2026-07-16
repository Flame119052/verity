import Foundation
import VerityDomain

public struct ProviderOutput: Equatable, Sendable {
    public var resultText: String
    public var newSessionID: String?

    public init(resultText: String, newSessionID: String?) {
        self.resultText = resultText
        self.newSessionID = newSessionID
    }
}

public enum ProviderOutputError: Error, LocalizedError, Sendable {
    case malformed(provider: AssistantProvider, reason: String)
    case empty(provider: AssistantProvider)

    public var errorDescription: String? {
        switch self {
        case .malformed(let provider, let reason): "Failed to parse \(provider.rawValue) output: \(reason)"
        case .empty(let provider): "\(provider.rawValue.capitalized) returned an empty response."
        }
    }
}

public enum ProviderOutputParser {
    public static func parse(provider: AssistantProvider, stdout: String) throws -> ProviderOutput {
        switch provider {
        case .claude: try parseClaude(stdout)
        case .codex: try parseCodex(stdout)
        case .antigravity: try parseAntigravity(stdout)
        }
    }

    public static func parseClaude(_ stdout: String) throws -> ProviderOutput {
        guard let data = stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = object["result"] as? String,
              !result.isEmpty
        else { throw ProviderOutputError.malformed(provider: .claude, reason: "missing result field") }
        return ProviderOutput(resultText: result, newSessionID: object["session_id"] as? String)
    }

    public static func parseCodex(_ stdout: String) throws -> ProviderOutput {
        var result = ""
        var sessionID: String?
        var failure: String?
        for line in stdout.components(separatedBy: "\n") where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String
            else { continue }
            if type == "thread.started" { sessionID = object["thread_id"] as? String }
            if type == "item.completed",
               let item = object["item"] as? [String: Any],
               item["type"] as? String == "agent_message",
               let text = item["text"] as? String {
                result = text
            }
            if type == "error" || type == "turn.failed" {
                failure = object["message"] as? String
                    ?? (object["error"] as? [String: Any])?["message"] as? String
            }
        }
        guard !result.isEmpty else {
            throw ProviderOutputError.malformed(provider: .codex, reason: failure ?? "no agent message found")
        }
        return ProviderOutput(resultText: result, newSessionID: sessionID)
    }

    public static func parseAntigravity(_ stdout: String) throws -> ProviderOutput {
        let ansi = try? NSRegularExpression(pattern: "\\u001B\\[[0-9;?]*[A-Za-z]")
        let cleaned = stdout.components(separatedBy: "\n").compactMap { line -> String? in
            let range = NSRange(location: 0, length: (line as NSString).length)
            let stripped = ansi?.stringByReplacingMatches(in: line, range: range, withTemplate: "") ?? line
            let value = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.lowercased() != "thinking", value.lowercased() != "thinking.", value.lowercased() != "done", value.lowercased() != "done." else { return nil }
            return stripped.trimmingCharacters(in: .newlines)
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { throw ProviderOutputError.empty(provider: .antigravity) }
        return ProviderOutput(resultText: cleaned, newSessionID: nil)
    }
}

public struct ExtractedAssistantReply: Equatable, Sendable {
    public var displayText: String
    public var proposals: [Proposal]

    public init(displayText: String, proposals: [Proposal]) {
        self.displayText = displayText
        self.proposals = proposals
    }
}

public enum ProposalExtractor {
    public static func extract(from text: String) -> ExtractedAssistantReply {
        guard let regex = try? NSRegularExpression(pattern: "```json\\s*([\\s\\S]*?)```", options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)),
              match.numberOfRanges > 1
        else { return ExtractedAssistantReply(displayText: text, proposals: []) }
        let ns = text as NSString
        let payload = ns.substring(with: match.range(at: 1))
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([Proposal].self, from: data)
        else { return ExtractedAssistantReply(displayText: text, proposals: []) }
        let proposals = decoded.map { Proposal(file: $0.file, newContent: $0.newContent) }
        let display = ns.replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ExtractedAssistantReply(displayText: display, proposals: proposals)
    }
}
