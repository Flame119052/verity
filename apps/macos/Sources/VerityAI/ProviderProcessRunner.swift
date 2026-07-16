import Foundation

public struct ProviderProcessResult: Sendable {
    public var stdout: String
    public var stderr: String
    public var exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }
}

public enum ProviderProcessError: Error, LocalizedError, Sendable {
    case executableNotFound(String)
    case launch(String)
    case failed(code: Int32, message: String)
    case timedOut
    case outputTooLarge

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name): "The \(name) command-line tool was not found."
        case .launch(let message): "The provider could not launch: \(message)"
        case .failed(let code, let message): "The provider exited with code \(code): \(message)"
        case .timedOut: "The provider did not finish within five minutes."
        case .outputTooLarge: "The provider produced more than 20 MB of output."
        }
    }
}

public actor ProviderProcessRunner {
    public let timeout: Duration
    public let maximumOutputBytes: Int
    private let baseEnvironment: [String: String]

    public init(
        timeout: Duration = .seconds(300),
        maximumOutputBytes: Int = 20 * 1_024 * 1_024,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.timeout = timeout
        self.maximumOutputBytes = maximumOutputBytes
        self.baseEnvironment = environment
    }

    public func resolveExecutable(named name: String, environment: [String: String]? = nil) throws -> URL {
        let environment = environment ?? baseEnvironment
        let paths = Self.commandSearchPaths(environment: environment)
        for path in paths {
            let url = URL(fileURLWithPath: path).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        throw ProviderProcessError.executableNotFound(name)
    }

    public func run(_ invocation: ProviderInvocation, workingDirectory: URL) async throws -> ProviderProcessResult {
        let executable = try resolveExecutable(named: invocation.executable)
        return try await run(executable: executable, arguments: invocation.arguments, workingDirectory: workingDirectory)
    }

    public func run(executable: URL, arguments: [String], workingDirectory: URL) async throws -> ProviderProcessResult {
        let process = Process()
        let outputDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("verity-provider-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }
        let stdoutURL = outputDirectory.appendingPathComponent("stdout")
        let stderrURL = outputDirectory.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
        }
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        var environment = baseEnvironment
        environment["PATH"] = Self.commandSearchPaths(environment: environment).joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        let exitEvents = AsyncStream<Int32> { continuation in
            process.terminationHandler = { finished in
                continuation.yield(finished.terminationStatus)
                continuation.finish()
            }
        }
        do { try process.run() }
        catch { throw ProviderProcessError.launch(error.localizedDescription) }

        let box = ProcessBox(process)
        let timeout = self.timeout
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: ProviderProcessResult.self) { group in
                group.addTask {
                    var iterator = exitEvents.makeAsyncIterator()
                    guard let exitCode = await iterator.next() else { throw CancellationError() }
                    try? stdoutHandle.synchronize()
                    try? stderrHandle.synchronize()
                    let stdout = try Data(contentsOf: stdoutURL, options: .mappedIfSafe)
                    let stderr = try Data(contentsOf: stderrURL, options: .mappedIfSafe)
                    guard stdout.count + stderr.count <= self.maximumOutputBytes else { throw ProviderProcessError.outputTooLarge }
                    let output = String(decoding: stdout, as: UTF8.self)
                    let errors = String(decoding: stderr, as: UTF8.self)
                    guard exitCode == 0 else {
                        throw ProviderProcessError.failed(code: exitCode, message: errors.isEmpty ? output : errors)
                    }
                    return ProviderProcessResult(stdout: output, stderr: errors, exitCode: exitCode)
                }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    if box.process.isRunning { box.process.terminate() }
                    throw ProviderProcessError.timedOut
                }
                group.addTask {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .milliseconds(50))
                        let stdoutSize = ((try? FileManager.default.attributesOfItem(atPath: stdoutURL.path)[.size]) as? NSNumber)?.intValue ?? 0
                        let stderrSize = ((try? FileManager.default.attributesOfItem(atPath: stderrURL.path)[.size]) as? NSNumber)?.intValue ?? 0
                        if stdoutSize + stderrSize > self.maximumOutputBytes {
                            if box.process.isRunning { box.process.terminate() }
                            throw ProviderProcessError.outputTooLarge
                        }
                    }
                    throw CancellationError()
                }
                guard let result = try await group.next() else { throw ProviderProcessError.launch("No process result") }
                group.cancelAll()
                return result
            }
        } onCancel: {
            if box.process.isRunning { box.process.terminate() }
        }
    }

    private static func commandSearchPaths(environment: [String: String]) -> [String] {
        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        var candidates = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        candidates.append(contentsOf: [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
            "\(home)/.local/bin", "\(home)/.npm-global/bin", "\(home)/Library/pnpm", "\(home)/.bun/bin"
        ])
        candidates.append(contentsOf: loginShellPaths(environment: environment))
        var seen = Set<String>()
        return candidates.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func loginShellPaths(environment: [String: String]) -> [String] {
        let shell = environment["SHELL"].flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil } ?? "/bin/zsh"
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-lic", "printf '%s' \"$PATH\""]
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            let completion = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in completion.signal() }
            try process.run()
            guard completion.wait(timeout: .now() + 2) == .success else {
                process.terminate()
                return []
            }
            guard process.terminationStatus == 0 else { return [] }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self).split(separator: ":").map(String.init)
        } catch {
            return []
        }
    }
}

private final class ProcessBox: @unchecked Sendable {
    let process: Process
    init(_ process: Process) { self.process = process }
}
