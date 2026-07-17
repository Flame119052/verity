import AppKit
import VerityDomain
import VerityKit

/// Owns the menu-bar item through AppKit instead of SwiftUI's `MenuBarExtra`.
/// `NSMenu` closes synchronously after a command, avoiding the stranded menu
/// and missing-content states seen when SwiftUI rebuilt the status scene.
@MainActor
final class VerityStatusMenuController: NSObject, NSMenuDelegate {
    private weak var state: AppState?
    private var updateController: VerityUpdateController?
    private var statusItem: NSStatusItem?
    private var nextStartSlot: ScheduleSlot?

    func configure(state: AppState, updateController: VerityUpdateController) {
        self.state = state
        self.updateController = updateController
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible {
            installStatusItemIfNeeded()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "checkmark.seal.fill", accessibilityDescription: "VERITY")
            button.image?.isTemplate = true
            button.toolTip = "VERITY Study Operations"
        }
        let menu = NSMenu(title: "VERITY")
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let state else {
            addInformation("VERITY is starting…", to: menu)
            return
        }

        if let active = state.activeTimer {
            addInformation("STUDYING · \(state.elapsedClock)", to: menu)
            addInformation(active.target.referenceLabel, to: menu)
            addAction("Stop and Log", symbol: "stop.fill", action: #selector(stopAndLog), to: menu)
            addAction("Discard Timer", symbol: "xmark", action: #selector(discardTimer), to: menu)
        } else {
            addInformation("VERITY READY", to: menu)
            nextStartSlot = state.todaySchedule.first(where: {
                $0.referenceType != .fixed && isUpcomingOrActive($0)
            })
            if let nextStartSlot {
                addAction(
                    "Start \(nextStartSlot.referenceLabel)",
                    symbol: "play.fill",
                    action: #selector(startNextSlot),
                    to: menu
                )
            }
        }

        if let next = state.nextTodayScheduleSlot {
            let relative = timeUntil(next).map { " · \($0)" } ?? ""
            addInformation("NEXT · \(next.startTime)\(relative) · \(next.referenceLabel)", to: menu)
        }
        if let urgent = state.orderedOpenHomework.first {
            addInformation("DUE · \(urgent.subject) — \(urgent.task)", to: menu)
        }

        menu.addItem(.separator())
        addAction("Quick Add Homework…", symbol: "plus.circle", action: #selector(quickAddHomework), to: menu)
        let openItem = addAction("Open VERITY", symbol: "macwindow", action: #selector(openVERITY), to: menu)
        openItem.keyEquivalent = "o"
        menu.addItem(.separator())

        let loginItem = addAction("Launch at Login", action: #selector(toggleLaunchAtLogin), to: menu)
        loginItem.state = state.launchAtLoginEnabled ? .on : .off
        let updateItem = addAction("Check for Updates…", action: #selector(checkForUpdates), to: menu)
        updateItem.isEnabled = !state.isCheckingForUpdates
        addAction("Settings…", action: #selector(openSettings), to: menu)
        menu.addItem(.separator())
        let quitItem = addAction("Quit VERITY", action: #selector(quit), to: menu)
        quitItem.keyEquivalent = "q"
    }

    @discardableResult
    private func addAction(
        _ title: String,
        symbol: String? = nil,
        action: Selector,
        to menu: NSMenu
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        menu.addItem(item)
        return item
    }

    private func addInformation(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    @objc private func stopAndLog() {
        guard let state else { return }
        Task { await state.stopAndLogTimer() }
    }

    @objc private func discardTimer() {
        guard let state else { return }
        Task { await state.discardTimer() }
    }

    @objc private func startNextSlot() {
        guard let state, let slot = nextStartSlot else { return }
        Task { await state.startTimer(for: slot) }
    }

    @objc private func quickAddHomework() {
        revealMain(workspace: .pending, requestNewItem: true)
    }

    @objc private func openVERITY() {
        revealMain()
    }

    @objc private func toggleLaunchAtLogin() {
        guard let state else { return }
        state.setLaunchAtLogin(!state.launchAtLoginEnabled)
    }

    @objc private func checkForUpdates() {
        guard let state else { return }
        updateController?.checkForUpdates(state: state)
    }

    @objc private func openSettings() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func revealMain(workspace: Workspace? = nil, requestNewItem: Bool = false) {
        guard let state else { return }
        if let workspace {
            state.selectedWorkspace = workspace
            if requestNewItem { state.requestNewItem(in: workspace) }
        }
        if let mainWindow = NSApplication.shared.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            mainWindow.makeKeyAndOrderFront(nil)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func timeUntil(_ slot: ScheduleSlot) -> String? {
        let parts = slot.startTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let current = Calendar.current.component(.hour, from: Date()) * 60
            + Calendar.current.component(.minute, from: Date())
        let delta = parts[0] * 60 + parts[1] - current
        guard delta > 0 else { return nil }
        return delta >= 60 ? "in \(delta / 60)h \(delta % 60)m" : "in \(delta)m"
    }

    private func isUpcomingOrActive(_ slot: ScheduleSlot) -> Bool {
        let parts = slot.startTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return false }
        let current = Calendar.current.component(.hour, from: Date()) * 60
            + Calendar.current.component(.minute, from: Date())
        return parts[0] * 60 + parts[1] + slot.durationMinutes > current
    }
}
