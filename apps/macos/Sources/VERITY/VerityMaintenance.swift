import AppKit
import Foundation
import ServiceManagement
import VerityKit

@MainActor
enum VerityMaintenance {
    static func requestUninstall(state: AppState) {
        guard state.activeTimer == nil else {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Finish the active timer first"
            alert.informativeText = "Stop and log or discard the current timer before uninstalling so recovery state is never lost."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        let removeData = NSButton(
            checkboxWithTitle: "Also remove Native settings, timer recovery, and caches",
            target: nil,
            action: nil
        )
        removeData.state = .on

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.icon = NSImage(systemSymbolName: "trash.circle.fill", accessibilityDescription: "Uninstall VERITY")
        alert.messageText = "Uninstall VERITY Native?"
        alert.informativeText = "VERITY.app will move to the Trash. Your Markdown vault, Electron legacy copy, provider CLIs, and provider credentials are always preserved."
        alert.accessoryView = removeData
        alert.addButton(withTitle: "Uninstall VERITY")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            let bundledHelper = Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/verity-uninstaller")
            guard FileManager.default.isExecutableFile(atPath: bundledHelper.path) else {
                throw MaintenanceError.helperMissing
            }
            let temporaryHelper = FileManager.default.temporaryDirectory
                .appendingPathComponent("verity-uninstaller-\(UUID().uuidString)")
            try FileManager.default.copyItem(at: bundledHelper, to: temporaryHelper)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: temporaryHelper.path)

            let process = Process()
            process.executableURL = temporaryHelper
            process.arguments = [
                "--confirmed",
                "--target-app", Bundle.main.bundleURL.path,
            ] + (removeData.state == .on ? ["--remove-data"] : [])
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            state.lastError = "VERITY could not start its uninstaller: \(error.localizedDescription)"
        }
    }
}

private enum MaintenanceError: LocalizedError {
    case helperMissing

    var errorDescription: String? {
        "The embedded uninstaller is missing. Reinstall VERITY from its DMG, or run Uninstall VERITY.app from the installer."
    }
}
