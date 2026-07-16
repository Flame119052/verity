import Foundation

public struct VaultConfiguration: Codable, Equatable, Sendable {
    public var displayPath: String
    public var bookmark: Data
    public var securityScoped: Bool?

    public init(displayPath: String, bookmark: Data, securityScoped: Bool? = nil) {
        self.displayPath = displayPath
        self.bookmark = bookmark
        self.securityScoped = securityScoped
    }
}

public enum VaultConfigurationError: Error, LocalizedError, Sendable {
    case staleBookmark
    case inaccessibleBookmark

    public var errorDescription: String? {
        switch self {
        case .staleBookmark: "The saved vault location changed. Choose the vault again."
        case .inaccessibleBookmark: "VERITY can no longer access the saved vault. Choose it again."
        }
    }
}

public struct VaultConfigurationStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let configURL: URL
    private let useSecurityScopedBookmarks: Bool

    public init(
        fileManager: FileManager = .default,
        configURL: URL? = nil,
        useSecurityScopedBookmarks: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    ) {
        self.fileManager = fileManager
        self.useSecurityScopedBookmarks = useSecurityScopedBookmarks
        if let configURL {
            self.configURL = configURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.configURL = support
                .appendingPathComponent("VERITY Native", isDirectory: true)
                .appendingPathComponent("config.json")
        }
    }

    public func save(vaultURL: URL) throws {
        let bookmark = try vaultURL.bookmarkData(
            options: useSecurityScopedBookmarks ? [.withSecurityScope] : [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let configuration = VaultConfiguration(
            displayPath: vaultURL.path,
            bookmark: bookmark,
            securityScoped: useSecurityScopedBookmarks
        )
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(configuration)
        try data.write(to: configURL, options: [.atomic])
    }

    public func restore() throws -> URL? {
        guard fileManager.fileExists(atPath: configURL.path) else { return nil }
        let configuration = try JSONDecoder().decode(VaultConfiguration.self, from: Data(contentsOf: configURL))
        var stale = false
        let isSecurityScoped = configuration.securityScoped ?? true
        let url = try URL(
            resolvingBookmarkData: configuration.bookmark,
            options: isSecurityScoped ? [.withSecurityScope] : [],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        )
        guard !stale else { throw VaultConfigurationError.staleBookmark }
        guard !isSecurityScoped || url.startAccessingSecurityScopedResource() || fileManager.isReadableFile(atPath: url.path) else {
            throw VaultConfigurationError.inaccessibleBookmark
        }
        guard fileManager.isReadableFile(atPath: url.path) else { throw VaultConfigurationError.inaccessibleBookmark }
        return url
    }

    public func clear() throws {
        if fileManager.fileExists(atPath: configURL.path) {
            try fileManager.removeItem(at: configURL)
        }
    }

    public func legacyVaultSuggestion() -> URL? {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let legacyConfig = support.appendingPathComponent("VERITY/config.json")
        guard let data = try? Data(contentsOf: legacyConfig),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["vaultPath"] as? String,
              fileManager.fileExists(atPath: path)
        else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
