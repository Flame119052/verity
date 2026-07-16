import Foundation
import Testing
@testable import VerityVault

struct MarkdownTests {
    @Test func sanitizesTableCells() {
        #expect(Markdown.sanitizeCell("alpha|beta\ngamma") == "alpha❘beta gamma")
    }

    @Test func parsesTableLikeTypeScriptImplementation() {
        let content = """
        # Homework

        | id | task |
        | --- | :---: |
        | one | Read chapter |
        """
        #expect(Markdown.parseTable(content) == [["id": "one", "task": "Read chapter"]])
    }

    @Test func extractsLevelTwoSections() {
        let sections = Markdown.extractSections("# Header\n\n## Science\n\n| A |\n| --- |\n| B |\n\n## Maths\nBody")
        #expect(sections.map(\.title) == ["Science", "Maths"])
    }
}
