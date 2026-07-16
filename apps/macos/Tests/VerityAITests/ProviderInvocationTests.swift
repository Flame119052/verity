import Testing
@testable import VerityAI

struct ProviderInvocationTests {
    @Test func codexIsAlwaysReadOnly() {
        let invocation = ProviderInvocationBuilder.codex(prompt: "Help", model: "gpt-5.6", effort: "high")
        #expect(invocation.executable == "codex")
        #expect(invocation.arguments.contains("--sandbox"))
        #expect(invocation.arguments.contains("read-only"))
        #expect(invocation.arguments.contains("--json"))
    }

    @Test func claudeDeniesMutationTools() {
        let invocation = ProviderInvocationBuilder.claude(prompt: "Help", model: "sonnet", effort: "high")
        #expect(invocation.arguments.contains("--disallowedTools"))
        #expect(invocation.arguments.contains("Write Edit Bash NotebookEdit"))
    }

    @Test func antigravityDoesNotReceiveVaultDirectory() {
        let invocation = ProviderInvocationBuilder.antigravity(prompt: "Help", model: "Gemini")
        #expect(!invocation.arguments.contains("--add-dir"))
    }
}
