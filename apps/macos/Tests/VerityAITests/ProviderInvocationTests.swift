import Foundation
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

    @Test func claudeSetupUsesOfficialPackageAndExplicitLogin() {
        #expect(ProviderSetupCommand.installSummary(for: .claude) == "npm install -g @anthropic-ai/claude-code")
        #expect(ProviderSetupCommand.authenticationArguments(for: .claude) == ["auth", "login"])
    }

    @Test func codexSetupUsesDeviceAuthorization() {
        #expect(ProviderSetupCommand.installSummary(for: .codex) == "npm install -g @openai/codex")
        #expect(ProviderSetupCommand.authenticationArguments(for: .codex) == ["login", "--device-auth"])
    }

    @Test func antigravitySetupUsesOfficialInstallerAndInteractiveOAuth() {
        #expect(ProviderSetupCommand.installSummary(for: .antigravity) == "Official Google Antigravity installer")
        #expect(ProviderSetupCommand.authenticationArguments(for: .antigravity).isEmpty)
    }

    @Test func codexInstallationExecutesOfficialGlobalPackageCommand() async throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable(named: "npm", body: """
        printf '%s\\n' "$@" > "$HOME/npm-arguments"
        mkdir -p "$HOME/.local/bin"
        printf '#!/bin/sh\\nexit 0\\n' > "$HOME/.local/bin/codex"
        chmod +x "$HOME/.local/bin/codex"
        """)
        let service = AssistantService(root: fixture.vault, runner: fixture.runner)

        try await service.installProvider(.codex)

        let arguments = try String(contentsOf: fixture.home.appendingPathComponent("npm-arguments"), encoding: .utf8)
        #expect(arguments == "install\n-g\n@openai/codex\n")
        #expect((await service.providerStatus(.codex)).installed)
    }

    @Test func antigravityInstallationDownloadsOfficialScriptWithoutShellPipe() async throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable(named: "curl", body: """
        printf '%s\\n' "$@" > "$HOME/curl-arguments"
        output=''
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '-o' ]; then shift; output="$1"; fi
          shift
        done
        printf '#!/bin/sh\\nmkdir -p "$HOME/.local/bin"\\nprintf '\"'\"'#!/bin/sh\\nexit 0\\n'\"'\"' > "$HOME/.local/bin/agy"\\nchmod +x "$HOME/.local/bin/agy"\\n' > "$output"
        """)
        let service = AssistantService(root: fixture.vault, runner: fixture.runner)

        try await service.installProvider(.antigravity)

        let arguments = try String(contentsOf: fixture.home.appendingPathComponent("curl-arguments"), encoding: .utf8)
        #expect(arguments.contains("https://antigravity.google/cli/install.sh"))
        #expect(arguments.contains("-o"))
        #expect((await service.providerStatus(.antigravity)).installed)
    }

    @Test func antigravityRejectsMalformedInstallerDownload() async throws {
        let fixture = try InstallFixture()
        defer { fixture.cleanup() }
        try fixture.writeExecutable(named: "curl", body: """
        output=''
        while [ "$#" -gt 0 ]; do
          if [ "$1" = '-o' ]; then shift; output="$1"; fi
          shift
        done
        printf 'not an installer' > "$output"
        """)
        let service = AssistantService(root: fixture.vault, runner: fixture.runner)
        var rejected = false

        do { try await service.installProvider(.antigravity) }
        catch AssistantServiceError.invalidInstallerDownload { rejected = true }

        #expect(rejected)
        #expect(!(await service.providerStatus(.antigravity)).installed)
    }
}

private struct InstallFixture {
    let root: URL
    let home: URL
    let bin: URL
    let vault: URL
    let runner: ProviderProcessRunner

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("verity-provider-install-tests-\(UUID().uuidString)")
        home = root.appendingPathComponent("home", isDirectory: true)
        bin = root.appendingPathComponent("bin", isDirectory: true)
        vault = root.appendingPathComponent("vault", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        runner = ProviderProcessRunner(
            timeout: .seconds(5),
            maximumOutputBytes: 512 * 1_024,
            environment: ["PATH": bin.path, "HOME": home.path, "SHELL": "/bin/sh"]
        )
    }

    func writeExecutable(named name: String, body: String) throws {
        let url = bin.appendingPathComponent(name)
        try Data("#!/bin/sh\nset -eu\n\(body)\n".utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}
