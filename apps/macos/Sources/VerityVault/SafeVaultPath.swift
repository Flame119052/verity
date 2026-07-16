import Foundation

public enum VaultPathError: Error, Equatable, LocalizedError, Sendable {
    case empty
    case absolute(String)
    case traversal(String)
    case outsideVault(String)
    case symbolicLink(String)

    public var errorDescription: String? {
        switch self {
        case .empty: "The vault-relative path is empty."
        case .absolute(let path): "Absolute vault path is forbidden: \(path)"
        case .traversal(let path): "Path traversal is forbidden: \(path)"
        case .outsideVault(let path): "Path resolves outside the selected vault: \(path)"
        case .symbolicLink(let path): "Symbolic-link traversal is forbidden: \(path)"
        }
    }
}

public struct SafeVaultPathResolver: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func resolve(_ relativePath: String, allowMissingLeaf: Bool = true) throws -> URL {
        guard !relativePath.isEmpty else { throw VaultPathError.empty }
        guard !relativePath.hasPrefix("/"), !NSString(string: relativePath).isAbsolutePath else {
            throw VaultPathError.absolute(relativePath)
        }
        let components = NSString(string: relativePath).pathComponents
        guard !components.contains(".."), !relativePath.contains("\0") else {
            throw VaultPathError.traversal(relativePath)
        }
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard parent.path == root.path || parent.path.hasPrefix(rootPath) else {
            throw VaultPathError.outsideVault(relativePath)
        }
        if FileManager.default.fileExists(atPath: candidate.path) {
            let resolved = candidate.resolvingSymlinksInPath()
            guard resolved.path == root.path || resolved.path.hasPrefix(rootPath) else {
                throw VaultPathError.symbolicLink(relativePath)
            }
            return resolved
        }
        guard allowMissingLeaf else { throw CocoaError(.fileNoSuchFile) }
        return candidate
    }
}
