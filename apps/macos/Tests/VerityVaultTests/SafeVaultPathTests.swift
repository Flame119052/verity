import Foundation
import Testing
@testable import VerityVault

struct SafeVaultPathTests {
    @Test func permitsConfinedRelativePath() throws {
        let root = URL(fileURLWithPath: "/tmp/verity-vault")
        let resolved = try SafeVaultPathResolver(root: root).resolve("Progress/Homework.md")
        #expect(resolved.path == "/tmp/verity-vault/Progress/Homework.md")
    }

    @Test func rejectsTraversalAndAbsolutePaths() {
        let resolver = SafeVaultPathResolver(root: URL(fileURLWithPath: "/tmp/verity-vault"))
        #expect(throws: (any Error).self) { try resolver.resolve("../secret") }
        #expect(throws: (any Error).self) { try resolver.resolve("/etc/passwd") }
    }
}
