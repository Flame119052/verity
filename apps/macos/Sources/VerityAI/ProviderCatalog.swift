import Foundation
import VerityDomain

public struct ProviderDescriptor: Equatable, Sendable, Identifiable {
    public var id: AssistantProvider
    public var label: String
    public var models: [String]
    public var effortLevels: [String]

    public init(id: AssistantProvider, label: String, models: [String], effortLevels: [String]) {
        self.id = id
        self.label = label
        self.models = models
        self.effortLevels = effortLevels
    }
}

public enum ProviderCatalog {
    public static let all: [ProviderDescriptor] = [
        ProviderDescriptor(id: .claude, label: "Claude", models: ["sonnet", "opus", "haiku", "fable"], effortLevels: ["low", "medium", "high", "xhigh", "max"]),
        ProviderDescriptor(id: .codex, label: "Codex", models: ["gpt-5.5"], effortLevels: ["minimal", "low", "medium", "high"]),
        ProviderDescriptor(
            id: .antigravity,
            label: "Antigravity",
            models: [
                "Gemini 3.5 Flash (Medium)", "Gemini 3.5 Flash (High)", "Gemini 3.5 Flash (Low)",
                "Gemini 3.1 Pro (Low)", "Gemini 3.1 Pro (High)",
                "Claude Sonnet 4.6 (Thinking)", "Claude Opus 4.6 (Thinking)", "GPT-OSS 120B (Medium)",
            ],
            effortLevels: []
        ),
    ]
}

public struct ProviderInvocation: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public enum ProviderInvocationBuilder {
    public static func codex(prompt: String, model: String, effort: String, resumeSessionID: String? = nil, systemPrompt: String? = nil) -> ProviderInvocation {
        let finalPrompt = [systemPrompt, prompt].compactMap { $0 }.joined(separator: "\n\n")
        var arguments = ["exec"]
        if let resumeSessionID {
            arguments += ["resume", resumeSessionID, finalPrompt]
        } else {
            arguments += [finalPrompt]
        }
        if !model.isEmpty { arguments += ["-m", model] }
        if !effort.isEmpty { arguments += ["-c", "model_reasoning_effort=\(effort)"] }
        arguments += ["--sandbox", "read-only", "--skip-git-repo-check", "--json"]
        return ProviderInvocation(executable: "codex", arguments: arguments)
    }

    public static func claude(prompt: String, model: String, effort: String, resumeSessionID: String? = nil, systemPrompt: String? = nil, mcpConfigPath: String? = nil) -> ProviderInvocation {
        var arguments = ["-p", prompt, "--model", model, "--effort", effort]
        if let systemPrompt { arguments += ["--append-system-prompt", systemPrompt] }
        if let resumeSessionID { arguments += ["--resume", resumeSessionID] }
        if let mcpConfigPath { arguments += ["--mcp-config", mcpConfigPath] }
        arguments += [
            "--allowedTools", "WebSearch WebFetch Read mcp__playwright__*",
            "--disallowedTools", "Write Edit Bash NotebookEdit",
            "--output-format", "json",
        ]
        return ProviderInvocation(executable: "claude", arguments: arguments)
    }

    public static func antigravity(prompt: String, model: String, systemPrompt: String? = nil) -> ProviderInvocation {
        let finalPrompt = [systemPrompt, prompt].compactMap { $0 }.joined(separator: "\n\n")
        var arguments = ["--print", finalPrompt]
        if !model.isEmpty { arguments += ["--model", model] }
        arguments += ["--mode", "plan"]
        return ProviderInvocation(executable: "agy", arguments: arguments)
    }
}
