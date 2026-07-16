import CryptoKit
import Foundation

public struct FileFingerprint: Codable, Equatable, Sendable {
    public var sha256: String
    public var byteCount: Int

    public init(sha256: String, byteCount: Int) {
        self.sha256 = sha256
        self.byteCount = byteCount
    }
}

public enum VaultFileError: Error, LocalizedError, Sendable {
    case coordination(String)
    case invalidUTF8(String)
    case staleFile(path: String)
    case writeVerification(path: String)

    public var errorDescription: String? {
        switch self {
        case .coordination(let message): "File coordination failed: \(message)"
        case .invalidUTF8(let path): "The vault file is not valid UTF-8: \(path)"
        case .staleFile(let path): "The file changed since it was loaded: \(path)"
        case .writeVerification(let path): "The written file could not be verified: \(path)"
        }
    }
}

public struct CoordinatedFileAccess: @unchecked Sendable {
    private let resolver: SafeVaultPathResolver
    private let fileManager: FileManager

    public init(root: URL, fileManager: FileManager = .default) {
        self.resolver = SafeVaultPathResolver(root: root)
        self.fileManager = fileManager
    }

    public func exists(_ relativePath: String) throws -> Bool {
        let url = try resolver.resolve(relativePath)
        return fileManager.fileExists(atPath: url.path)
    }

    public func read(_ relativePath: String) throws -> (content: String, fingerprint: FileFingerprint) {
        let result = try readData(relativePath)
        guard let content = String(data: result.data, encoding: .utf8) else {
            throw VaultFileError.invalidUTF8(relativePath)
        }
        return (content, result.fingerprint)
    }

    public func readData(_ relativePath: String) throws -> (data: Data, fingerprint: FileFingerprint) {
        let url = try resolver.resolve(relativePath, allowMissingLeaf: false)
        var coordinationError: NSError?
        var result: Result<Data, Error>?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url,
            options: .withoutChanges,
            error: &coordinationError
        ) { coordinatedURL in
            result = Result { try Data(contentsOf: coordinatedURL) }
        }
        if let coordinationError { throw VaultFileError.coordination(coordinationError.localizedDescription) }
        let data = try result?.get() ?? Data()
        return (data, Self.fingerprint(data))
    }

    public func remove(_ relativePath: String, expectedFingerprint: FileFingerprint? = nil) throws {
        let url = try resolver.resolve(relativePath, allowMissingLeaf: false)
        var coordinationError: NSError?
        var removeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                if let expectedFingerprint {
                    guard fileManager.fileExists(atPath: coordinatedURL.path) else {
                        throw VaultFileError.staleFile(path: relativePath)
                    }
                    let current = Self.fingerprint(try Data(contentsOf: coordinatedURL))
                    guard current == expectedFingerprint else {
                        throw VaultFileError.staleFile(path: relativePath)
                    }
                }
                try fileManager.removeItem(at: coordinatedURL)
            }
            catch { removeError = error }
        }
        if let coordinationError { throw VaultFileError.coordination(coordinationError.localizedDescription) }
        if let removeError { throw removeError }
    }

    @discardableResult
    public func write(
        _ content: String,
        to relativePath: String,
        expectedFingerprint: FileFingerprint? = nil,
        requireAbsent: Bool = false
    ) throws -> FileFingerprint {
        return try writeData(
            Data(content.utf8),
            to: relativePath,
            expectedFingerprint: expectedFingerprint,
            requireAbsent: requireAbsent
        )
    }

    @discardableResult
    public func writeData(
        _ data: Data,
        to relativePath: String,
        expectedFingerprint: FileFingerprint? = nil,
        requireAbsent: Bool = false
    ) throws -> FileFingerprint {
        let url = try resolver.resolve(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let expected = Self.fingerprint(data)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedURL in
            do {
                let exists = fileManager.fileExists(atPath: coordinatedURL.path)
                if requireAbsent, exists {
                    throw VaultFileError.staleFile(path: relativePath)
                }
                if let expectedFingerprint {
                    guard exists else { throw VaultFileError.staleFile(path: relativePath) }
                    let current = Self.fingerprint(try Data(contentsOf: coordinatedURL))
                    guard current == expectedFingerprint else {
                        throw VaultFileError.staleFile(path: relativePath)
                    }
                }
                let temporary = coordinatedURL.deletingLastPathComponent()
                    .appendingPathComponent(".\(coordinatedURL.lastPathComponent).verity-\(UUID().uuidString).tmp")
                try data.write(to: temporary, options: [.atomic])
                if fileManager.fileExists(atPath: coordinatedURL.path) {
                    _ = try fileManager.replaceItemAt(coordinatedURL, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: coordinatedURL)
                }
            } catch {
                writeError = error
            }
        }
        if let coordinationError { throw VaultFileError.coordination(coordinationError.localizedDescription) }
        if let writeError { throw writeError }
        let verified = try readData(relativePath).fingerprint
        guard verified == expected else { throw VaultFileError.writeVerification(path: relativePath) }
        return verified
    }

    public static func fingerprint(_ data: Data) -> FileFingerprint {
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return FileFingerprint(sha256: digest, byteCount: data.count)
    }
}
