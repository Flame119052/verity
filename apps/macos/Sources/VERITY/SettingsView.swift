import AppKit
import SwiftUI
import VerityAI
import VerityDesign
import VerityDomain
import VerityKit

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case study
    case assistant
    case updates
    case privacy
    case about

    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .study: "Study"
        case .assistant: "Assistant CLIs"
        case .updates: "Updates"
        case .privacy: "Privacy"
        case .about: "About & Removal"
        }
    }
    var subtitle: String {
        switch self {
        case .general: "Vault and app behavior"
        case .study: "Timer and reminders"
        case .assistant: "Install, sign in, verify"
        case .updates: "Signed release channel"
        case .privacy: "Local-first boundaries"
        case .about: "Build, support, uninstall"
        }
    }
    var symbol: String {
        switch self {
        case .general: "switch.2"
        case .study: "timer"
        case .assistant: "terminal"
        case .updates: "arrow.triangle.2.circlepath"
        case .privacy: "lock.shield"
        case .about: "info.circle"
        }
    }
}

struct SettingsView: View {
    @Bindable var state: AppState
    @Binding var showMenuBarExtra: Bool
    let updateController: VerityUpdateController
    @State private var selection: SettingsSection = .general

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                SettingsBrandPlate()
                List(SettingsSection.allCases, selection: $selection) { section in
                    HStack(spacing: 10) {
                        Image(systemName: section.symbol)
                            .frame(width: 20)
                            .foregroundStyle(selection == section ? VerityTheme.warning : VerityTheme.etch)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(section.title)
                                .font(VerityTheme.mono(12, semibold: true))
                            Text(section.subtitle)
                                .font(VerityTheme.mono(9))
                                .foregroundStyle(VerityTheme.etch)
                        }
                    }
                    .padding(.vertical, 5)
                    .tag(section)
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
            .background(VerityTheme.board)
            .navigationSplitViewColumnWidth(min: 205, ideal: 220, max: 240)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsPageHeader(section: selection)
                    sectionContent
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(BoardBackdrop().ignoresSafeArea())
        }
        .navigationSplitViewStyle(.balanced)
        .preferredColorScheme(.dark)
        .task {
            for provider in AssistantProvider.allCases {
                await state.refreshProviderStatus(provider)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selection {
        case .general: general
        case .study: study
        case .assistant: assistant
        case .updates: updates
        case .privacy: privacy
        case .about: about
        }
    }

    private var general: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "VAULT LINK", symbol: "externaldrive.fill", accent: .cyan) {
                SettingsDetailRow(label: "Selected folder", value: state.selectedVaultURL?.path(percentEncoded: false) ?? "No vault selected", monospaced: true)
                Divider().overlay(VerityTheme.boardEdge)
                Text("The folder is the source of truth. VERITY keeps no shadow database and opening it does not rewrite Markdown.")
                    .settingsDetail()
                HStack {
                    Button("Change Vault…") { state.changeVault() }
                        .buttonStyle(VerityHardwareButtonStyle())
                    Button("Reveal in Finder") { state.revealVaultInFinder() }
                        .disabled(state.selectedVaultURL == nil)
                    Spacer()
                }
            }

            SettingsCard(title: "MAC BEHAVIOR", symbol: "macwindow", accent: VerityTheme.success) {
                SettingsToggleRow(
                    title: "Menu-bar cockpit",
                    detail: "Keep timer, next strip, urgent homework, updates, and quick actions one click away.",
                    isOn: $showMenuBarExtra
                )
                Divider().overlay(VerityTheme.boardEdge)
                SettingsToggleRow(
                    title: "Launch at login",
                    detail: "Register VERITY with macOS Login Items. The switch reflects the system service state.",
                    isOn: Binding(get: { state.launchAtLoginEnabled }, set: { state.setLaunchAtLogin($0) })
                )
            }

            SettingsCard(title: "LOCAL-FIRST CONTRACT", symbol: "checkmark.seal.fill", accent: VerityTheme.warning) {
                SettingsBullet(symbol: "doc.text.fill", title: "Plain Markdown", detail: "Your vault remains readable in Obsidian, Finder, Git, and any text editor.")
                SettingsBullet(symbol: "arrow.triangle.2.circlepath", title: "Conflict-aware writes", detail: "External edits invalidate stale forms and assistant reviews before VERITY writes.")
                SettingsBullet(symbol: "icloud.slash", title: "No VERITY cloud", detail: "No account, hosted database, telemetry, or analytics service is required.")
            }
        }
    }

    private var study: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                SettingsMetric(value: "\(state.orderedOpenHomework.count)", label: "OPEN HOMEWORK", color: VerityTheme.warning)
                SettingsMetric(value: "\(state.todaySchedule.count)", label: "TODAY'S STRIPS", color: .cyan)
                SettingsMetric(value: "\(state.courses.count)", label: "COURSES", color: VerityTheme.success)
            }

            SettingsCard(title: "TIMER STATE", symbol: "stopwatch.fill", accent: .cyan) {
                SettingsDetailRow(label: "Current state", value: state.activeTimer.map { "Running · \($0.target.referenceLabel)" } ?? "Stopped")
                SettingsDetailRow(label: "Recovery", value: state.activeTimer == nil ? "No pending timer" : "Crash-safe recovery armed")
                Text("VERITY writes recovery before a timer appears active. Stop and Log appends the time entry before recovery is cleared.")
                    .settingsDetail()
            }

            SettingsCard(title: "REMINDERS", symbol: "bell.badge.fill", accent: VerityTheme.warning) {
                SettingsToggleRow(
                    title: "Study-strip notifications",
                    detail: "Ask macOS to notify you when a scheduled strip begins. Permission remains under System Settings.",
                    isOn: Binding(get: { state.studyRemindersEnabled }, set: { state.setStudyReminders($0) })
                )
                Text("Turning this off removes VERITY's pending notifications immediately.")
                    .settingsDetail()
            }
        }
    }

    private var assistant: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "ONE-CLICK CLI SETUP", symbol: "terminal.fill", accent: .cyan) {
                Text("Choose Set Up once. VERITY runs the official installation command automatically, then opens the provider's secure sign-in flow only when credentials are still needed.")
                    .settingsDetail()
                ForEach(ProviderCatalog.all) { provider in
                    Divider().overlay(VerityTheme.boardEdge)
                    ProviderSetupRow(
                        provider: provider,
                        status: state.providerStatuses[provider.id],
                        busy: state.providerSetupBusy == provider.id,
                        message: state.providerSetupMessages[provider.id],
                        onSetup: { Task { await state.setUpProvider(provider.id) } },
                        onRefresh: { Task { await state.refreshProviderStatus(provider.id) } }
                    )
                }
            }

            SettingsCard(title: "WHAT SIGN-IN DOES", symbol: "person.badge.key.fill", accent: VerityTheme.warning) {
                SettingsBullet(symbol: "safari", title: "Browser authorization", detail: "Claude and Codex open their vendor-owned account flow. Antigravity uses Google OAuth.")
                SettingsBullet(symbol: "number.square", title: "Authorization codes", detail: "Codex uses device authorization; Antigravity may ask you to paste a one-time code back into Terminal.")
                SettingsBullet(symbol: "key.fill", title: "Provider-owned credentials", detail: "VERITY never asks for, copies, stores, or logs provider passwords and tokens.")
            }

            SettingsCard(title: "APPROVAL FIREWALL", symbol: "lock.shield.fill", accent: VerityTheme.success) {
                SettingsBullet(symbol: "eye.fill", title: "Read-only research", detail: "Provider processes cannot directly edit the vault.")
                SettingsBullet(symbol: "doc.text.magnifyingglass", title: "Visible review", detail: "Current and proposed file contents are shown before approval.")
                SettingsBullet(symbol: "checkmark.seal.fill", title: "Exact snapshot only", detail: "Expired, reused, or externally invalidated approvals are rejected.")
            }
        }
    }

    private var updates: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "INSTALLED RELEASE", symbol: "shippingbox.fill", accent: VerityTheme.success) {
                SettingsDetailRow(label: "Version", value: version)
                SettingsDetailRow(label: "Build", value: build)
                SettingsDetailRow(label: "Update engine", value: updateController.usesSignedAutomaticUpdates ? "Sparkle · EdDSA verified" : "Development fallback")
                SettingsDetailRow(label: "Feed", value: "GitHub HTTPS appcast", monospaced: true)
                HStack {
                    Button(state.isCheckingForUpdates ? "Checking…" : "Check for Updates…") {
                        updateController.checkForUpdates(state: state)
                    }
                    .buttonStyle(VerityHardwareButtonStyle())
                    .disabled(state.isCheckingForUpdates)
                    Link("Release Notes", destination: URL(string: "https://github.com/Flame119052/verity/releases/latest")!)
                    Spacer()
                }
            }

            SettingsCard(title: "RELEASE CHANNEL", symbol: "point.3.connected.trianglepath.dotted", accent: .cyan) {
                Picker("Update channel", selection: Binding(
                    get: { updateController.channel },
                    set: { updateController.setChannel($0) }
                )) {
                    Text("Stable — recommended").tag("stable")
                    Text("Beta — prerelease access").tag("beta")
                }
                .pickerStyle(.radioGroup)
                Text("Stable receives production builds. Beta additionally accepts prerelease items explicitly marked with the beta Sparkle channel.")
                    .settingsDetail()
            }

            SettingsCard(title: "UPDATE INTEGRITY", symbol: "checkmark.shield.fill", accent: VerityTheme.warning) {
                SettingsBullet(symbol: "signature", title: "EdDSA archive signature", detail: "Sparkle rejects an update ZIP that was not signed by VERITY's private update key.")
                SettingsBullet(symbol: "lock.fill", title: "HTTPS feed", detail: "The signed appcast is read from the public repository over HTTPS.")
                SettingsBullet(symbol: "hand.raised.fill", title: "You control installation", detail: "Automatic checks are enabled; installation and relaunch remain visible to you.")
            }
        }
    }

    private var privacy: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "DATA BOUNDARIES", symbol: "hand.raised.fill", accent: VerityTheme.success) {
                SettingsBullet(symbol: "folder.fill", title: "Study data", detail: "Stored only in the selected Markdown vault.")
                SettingsBullet(symbol: "person.crop.circle.badge.xmark", title: "No VERITY identity", detail: "No registration, account profile, analytics ID, or subscription is created.")
                SettingsBullet(symbol: "network.slash", title: "Network use", detail: "Only update checks and provider CLIs you explicitly use contact external services.")
                SettingsBullet(symbol: "key.fill", title: "Credentials", detail: "Remain in each provider's own authenticated CLI storage.")
            }

            SettingsCard(title: "REDACTED DIAGNOSTICS", symbol: "stethoscope", accent: .cyan) {
                Text("The report contains version/runtime metadata and row counts. It excludes vault paths, prompts, messages, file contents, attachments, and credentials.")
                    .settingsDetail()
                Button("Copy Redacted Diagnostics") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.diagnosticSummary(), forType: .string)
                }
                .buttonStyle(VerityHardwareButtonStyle())
            }
        }
    }

    private var about: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "VERITY NATIVE", symbol: "checkmark.seal.fill", accent: VerityTheme.warning) {
                HStack(alignment: .top, spacing: 18) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 72, height: 72)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("VERITY \(version)")
                            .font(VerityTheme.stencil(28))
                        Text("BUILD \(build) · APPLE SILICON · macOS 14+")
                            .font(VerityTheme.mono(10, semibold: true))
                            .tracking(1.1)
                            .foregroundStyle(VerityTheme.warning)
                        Text("A native SwiftUI/AppKit study command center. No Electron, WebView, localhost UI, account, or cloud backend.")
                            .settingsDetail()
                    }
                }
                Divider().overlay(VerityTheme.boardEdge)
                HStack {
                    Link("Documentation", destination: URL(string: "https://github.com/Flame119052/verity#readme")!)
                    Link("Report an Issue", destination: URL(string: "https://github.com/Flame119052/verity/issues/new/choose")!)
                    Link("All Releases", destination: URL(string: "https://github.com/Flame119052/verity/releases")!)
                }
            }

            SettingsCard(title: "REMOVAL & PRESERVATION", symbol: "trash.circle.fill", accent: VerityTheme.danger) {
                Text("The built-in uninstaller moves VERITY.app to the Trash and can clear Native settings and caches. It always preserves your Markdown vault, Electron legacy app, provider CLIs, and provider credentials.")
                    .settingsDetail()
                HStack {
                    Button("Uninstall VERITY…", role: .destructive) {
                        VerityMaintenance.requestUninstall(state: state)
                    }
                    Spacer()
                    Text("Available here and in the VERITY application menu")
                        .font(VerityTheme.mono(9))
                        .foregroundStyle(VerityTheme.etch)
                }
            }

            SettingsCard(title: "SYSTEM", symbol: "desktopcomputer", accent: .cyan) {
                SettingsDetailRow(label: "macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                SettingsDetailRow(label: "Architecture", value: machineArchitecture)
                SettingsDetailRow(label: "Bundle identifier", value: Bundle.main.bundleIdentifier ?? "app.verity.native", monospaced: true)
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Local"
    }

    private var machineArchitecture: String {
        #if arch(arm64)
        "Apple Silicon (arm64)"
        #elseif arch(x86_64)
        "Intel (x86_64)"
        #else
        "Unknown"
        #endif
    }
}

private struct SettingsBrandPlate: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("VERITY")
                .font(VerityTheme.stencil(25))
                .foregroundStyle(.white)
            Text("SYSTEM CONFIGURATION")
                .font(VerityTheme.mono(8, semibold: true))
                .tracking(1.5)
                .foregroundStyle(VerityTheme.warning)
            HStack(spacing: 6) {
                StatusLED(color: VerityTheme.success)
                Text("NATIVE CONTROL CENTER")
                    .font(VerityTheme.mono(8))
                    .foregroundStyle(VerityTheme.etch)
            }
            .padding(.top, 5)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerityTheme.boardRaised)
        .overlay(alignment: .bottom) { Rectangle().fill(VerityTheme.boardEdge).frame(height: 1) }
    }
}

private struct SettingsPageHeader: View {
    let section: SettingsSection
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("CONFIG / \(section.rawValue.uppercased())")
                .font(VerityTheme.mono(9, semibold: true))
                .tracking(1.7)
                .foregroundStyle(VerityTheme.warning)
            Text(section.title)
                .font(VerityTheme.stencil(34))
                .foregroundStyle(.white)
            Text(section.subtitle)
                .font(VerityTheme.mono(11))
                .foregroundStyle(VerityTheme.etch)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    let accent: Color
    @ViewBuilder let content: Content

    init(title: String, symbol: String, accent: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                StatusLED(color: accent)
                Image(systemName: symbol).foregroundStyle(accent)
                Text(title)
                    .font(VerityTheme.mono(10, semibold: true))
                    .tracking(1.2)
                    .foregroundStyle(.white)
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerityTheme.boardRaised.opacity(0.96), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(VerityTheme.boardEdge, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(VerityTheme.mono(12, semibold: true)).foregroundStyle(.white)
                Text(detail).settingsDetail()
            }
            Spacer(minLength: 24)
            Toggle("", isOn: $isOn).labelsHidden()
        }
    }
}

private struct SettingsDetailRow: View {
    let label: String
    let value: String
    var monospaced = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label.uppercased())
                .font(VerityTheme.mono(9, semibold: true))
                .tracking(0.8)
                .foregroundStyle(VerityTheme.etch)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(monospaced ? VerityTheme.mono(10) : VerityTheme.mono(11))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer()
        }
    }
}

private struct SettingsBullet: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol)
                .foregroundStyle(VerityTheme.warning)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(VerityTheme.mono(11, semibold: true)).foregroundStyle(.white)
                Text(detail).settingsDetail()
            }
        }
    }
}

private struct SettingsMetric: View {
    let value: String
    let label: String
    let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack { StatusLED(color: color); Spacer() }
            Text(value).font(VerityTheme.stencil(30)).foregroundStyle(.white)
            Text(label).font(VerityTheme.mono(9, semibold: true)).tracking(1).foregroundStyle(VerityTheme.etch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(VerityTheme.boardRaised, in: RoundedRectangle(cornerRadius: 5))
        .overlay { RoundedRectangle(cornerRadius: 5).stroke(VerityTheme.boardEdge) }
    }
}

private struct ProviderSetupRow: View {
    let provider: ProviderDescriptor
    let status: ProviderStatus?
    let busy: Bool
    let message: String?
    let onSetup: () -> Void
    let onRefresh: () -> Void

    private var isReady: Bool { status?.installed == true && status?.authentication == .authenticated }
    private var accent: Color {
        if isReady { return VerityTheme.success }
        if status?.installed == true { return VerityTheme.warning }
        return VerityTheme.danger
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4).fill(accent.opacity(0.13))
                Image(systemName: isReady ? "checkmark.seal.fill" : "terminal.fill").foregroundStyle(accent)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(provider.label).font(VerityTheme.mono(12, semibold: true)).foregroundStyle(.white)
                    Text(statusText.uppercased())
                        .font(VerityTheme.mono(8, semibold: true))
                        .tracking(0.7)
                        .foregroundStyle(accent)
                }
                Text("INSTALL · \(ProviderSetupCommand.installSummary(for: provider.id))")
                    .font(VerityTheme.mono(8))
                    .foregroundStyle(VerityTheme.etch)
                if let path = status?.executablePath {
                    Text(path).font(VerityTheme.mono(8)).foregroundStyle(VerityTheme.etch.opacity(0.75)).textSelection(.enabled)
                }
                if let message {
                    Text(message).settingsDetail()
                }
            }
            Spacer(minLength: 12)
            if busy {
                ProgressView().controlSize(.small).padding(.top, 8)
            } else {
                VStack(alignment: .trailing, spacing: 6) {
                    if !isReady {
                        Button(status?.installed == true ? "Sign In" : "Set Up") { onSetup() }
                            .buttonStyle(VerityHardwareButtonStyle())
                    }
                    Button("Check Status") { onRefresh() }.controlSize(.small)
                }
            }
        }
    }

    private var statusText: String {
        guard let status else { return "Checking" }
        guard status.installed else { return "Not installed" }
        switch status.authentication {
        case .authenticated: return "Ready"
        case .notAuthenticated: return "Sign-in required"
        case .unknown: return "Verify sign-in"
        }
    }
}

private extension View {
    func settingsDetail() -> some View {
        font(VerityTheme.mono(10))
            .foregroundStyle(VerityTheme.etch)
            .fixedSize(horizontal: false, vertical: true)
    }
}
