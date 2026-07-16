import Foundation

public struct LineDiffEntry: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable { case unchanged, removed, added }
    public var kind: Kind
    public var line: String
    public var id: UUID = UUID()

    public init(kind: Kind, line: String) {
        self.kind = kind
        self.line = line
    }
}

public enum LineDiff {
    public static func compare(old: String, new: String, maximumCells: Int = 1_000_000) -> [LineDiffEntry]? {
        let lhs = old.components(separatedBy: "\n")
        let rhs = new.components(separatedBy: "\n")
        guard lhs.count * rhs.count <= maximumCells else { return nil }
        var lengths = Array(repeating: Array(repeating: 0, count: rhs.count + 1), count: lhs.count + 1)
        if !lhs.isEmpty, !rhs.isEmpty {
            for i in 1...lhs.count {
                for j in 1...rhs.count {
                    lengths[i][j] = lhs[i - 1] == rhs[j - 1]
                        ? lengths[i - 1][j - 1] + 1
                        : max(lengths[i - 1][j], lengths[i][j - 1])
                }
            }
        }
        var result: [LineDiffEntry] = []
        var i = lhs.count
        var j = rhs.count
        while i > 0 || j > 0 {
            if i > 0, j > 0, lhs[i - 1] == rhs[j - 1] {
                result.append(LineDiffEntry(kind: .unchanged, line: lhs[i - 1])); i -= 1; j -= 1
            } else if j > 0, (i == 0 || lengths[i][j - 1] >= lengths[i - 1][j]) {
                result.append(LineDiffEntry(kind: .added, line: rhs[j - 1])); j -= 1
            } else {
                result.append(LineDiffEntry(kind: .removed, line: lhs[i - 1])); i -= 1
            }
        }
        return result.reversed()
    }
}
