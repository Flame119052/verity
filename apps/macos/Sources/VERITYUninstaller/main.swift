import AppKit
import Foundation

@main
@MainActor
struct VERITYUninstaller {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.activate(ignoringOtherApps: true)

        let arguments = CommandLine.arguments
        let alreadyConfirmed = arguments.contains("--confirmed")
        let removeDataFromArguments = arguments.contains("--remove-data")
        let targetApp: URL? = arguments.firstIndex(of: "--target-app").flatMap { index in
            let valueIndex = arguments.index(after: index)
            guard arguments.indices.contains(valueIndex) else { return nil }
            return URL(fileURLWithPath: arguments[valueIndex]).standardizedFileURL
        }

        let removeData = NSButton(checkboxWithTitle: "Also remove VERITY Native settings, timer recovery, and caches", target: nil, action: nil)
        removeData.state = .on

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Uninstall")
        alert.messageText = "Uninstall VERITY Native?"
        alert.informativeText = "The app will be moved to the Trash. Your Markdown vault and Claude, Codex, or Antigravity installations and credentials will never be deleted."
        alert.accessoryView = removeData
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        if !alreadyConfirmed, alert.runModal() != .alertFirstButtonReturn { return }

        let bundleIdentifier = "app.verity.native"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).forEach { _ = $0.terminate() }
        for _ in 0..<20 {
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).isEmpty else { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        var failures: [String] = []
        var candidates: [URL] = []
        if let targetApp {
            candidates.append(targetApp)
        } else {
            if let registered = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                candidates.append(registered)
            }
            candidates += FileManager.default.urls(
                for: .applicationDirectory,
                in: [.localDomainMask, .userDomainMask]
            ).map { $0.appendingPathComponent("VERITY.app", isDirectory: true) }
        }
        var seen = Set<String>()
        for installedApp in candidates where seen.insert(installedApp.standardizedFileURL.path).inserted {
            guard FileManager.default.fileExists(atPath: installedApp.path) else { continue }
            do { _ = try FileManager.default.trashItem(at: installedApp, resultingItemURL: nil) }
            catch { failures.append("VERITY.app: \(error.localizedDescription)") }
        }

        if alreadyConfirmed ? removeDataFromArguments : removeData.state == .on {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let paths = [
                home.appendingPathComponent("Library/Application Support/VERITY Native", isDirectory: true),
                home.appendingPathComponent("Library/Caches/\(bundleIdentifier)", isDirectory: true),
                home.appendingPathComponent("Library/Preferences/\(bundleIdentifier).plist"),
                home.appendingPathComponent("Library/Saved Application State/\(bundleIdentifier).savedState", isDirectory: true),
            ]
            for url in paths where FileManager.default.fileExists(atPath: url.path) {
                do { try FileManager.default.removeItem(at: url) }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }

        let result = NSAlert()
        if failures.isEmpty {
            result.alertStyle = .informational
            result.messageText = "VERITY Native was uninstalled"
            result.informativeText = "Your Markdown vault and AI provider tools were preserved. You can eject the installer disk image."
        } else {
            result.alertStyle = .warning
            result.messageText = "Uninstall finished with warnings"
            result.informativeText = failures.joined(separator: "\n")
        }
        result.addButton(withTitle: "Done")
        result.runModal()

        let ownExecutable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        if ownExecutable.lastPathComponent.hasPrefix("verity-uninstaller-") {
            try? FileManager.default.removeItem(at: ownExecutable)
        }
    }
}
