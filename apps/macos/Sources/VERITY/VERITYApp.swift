import SwiftUI
import AppKit
import Sparkle
import VerityDesign
import VerityAI
import VerityDomain
import VerityKit

@main
struct VERITYApp: App {
    @State private var state = AppState()
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true
    @NSApplicationDelegateAdaptor(VERITYAppDelegate.self) private var appDelegate
    private let updateController = VerityUpdateController()

    init() {
        VerityFonts.register()
    }

    var body: some Scene {
        Window("VERITY", id: "main") {
            RootView(state: state)
                .frame(minWidth: 1040, minHeight: 680)
                .onAppear { appDelegate.state = state }
        }
        .defaultSize(width: 1200, height: 800)
        .windowStyle(.hiddenTitleBar)
        .commands {
            VerityCommands(state: state, updateController: updateController)
        }

        MenuBarExtra("VERITY", systemImage: "checkmark.seal", isInserted: $showMenuBarExtra) {
            MenuBarCockpit(state: state, updateController: updateController)
        }
        // A real NSMenu-style status item dismisses after every command and never
        // leaves a borderless popover stranded above other applications.
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(state: state, showMenuBarExtra: $showMenuBarExtra, updateController: updateController)
                .frame(width: 680, height: 520)
        }
    }
}

@MainActor
private final class VerityUpdateController: NSObject, SPUUpdaterDelegate {
    private var sparkleController: SPUStandardUpdaterController?

    var usesSignedAutomaticUpdates: Bool { sparkleController != nil }
    var channel: String { UserDefaults.standard.string(forKey: "updateChannel") == "beta" ? "beta" : "stable" }

    init(bundle: Bundle = .main) {
        super.init()
        let feed = (bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if feed?.hasPrefix("https://") == true, key?.isEmpty == false {
            sparkleController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: self,
                userDriverDelegate: nil
            )
        } else {
            sparkleController = nil
        }
    }

    func setChannel(_ channel: String) {
        UserDefaults.standard.set(channel == "beta" ? "beta" : "stable", forKey: "updateChannel")
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel == "beta" ? ["beta"] : []
    }

    func checkForUpdates(state: AppState) {
        if let sparkleController {
            sparkleController.checkForUpdates(nil)
        } else {
            Task { await state.checkForUpdates() }
        }
    }
}

@MainActor
private final class VERITYAppDelegate: NSObject, NSApplicationDelegate {
    weak var state: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemResumed),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemResumed),
            name: .NSSystemClockDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(systemResumed),
            name: .NSSystemTimeZoneDidChange,
            object: nil
        )
    }

    @objc private func systemResumed() {
        Task { await state?.handleSystemResume() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first(where: { $0.identifier?.rawValue == "main" })?.makeKeyAndOrderFront(nil)
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let state, state.activeTimer != nil else { return .terminateNow }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "A study timer is still running"
        alert.informativeText = "Log the elapsed time before quitting, keep VERITY running from the menu bar, discard the timer, or cancel."
        alert.addButton(withTitle: "Stop, Log, and Quit")
        alert.addButton(withTitle: "Keep Running in Menu Bar")
        alert.addButton(withTitle: "Discard and Quit")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task {
                await state.stopAndLogTimer()
                sender.reply(toApplicationShouldTerminate: state.activeTimer == nil)
            }
            return .terminateLater
        case .alertSecondButtonReturn:
            sender.windows.filter { $0.identifier?.rawValue == "main" }.forEach { $0.performClose(nil) }
            return .terminateCancel
        case .alertThirdButtonReturn:
            Task {
                await state.discardTimer()
                sender.reply(toApplicationShouldTerminate: state.activeTimer == nil)
            }
            return .terminateLater
        default:
            return .terminateCancel
        }
    }
}

private struct RootView: View {
    @Bindable var state: AppState

    var body: some View {
        ZStack {
            BoardBackdrop().ignoresSafeArea()
            VStack(spacing: 0) {
                CommandHeader(state: state)
                WorkspaceView(state: state, workspace: state.selectedWorkspace)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                FunctionKeyRail(workspace: state.selectedWorkspace)
            }
            .padding(.horizontal, 22)
            .frame(maxWidth: 1280)
            .overlay(alignment: .leading) { Rectangle().fill(VerityTheme.boardEdge).frame(width: 1) }
            .overlay(alignment: .trailing) { Rectangle().fill(VerityTheme.boardEdge).frame(width: 1) }
            .disabled(state.selectedVaultURL == nil)

            if state.isOnboardingPresented || state.selectedVaultURL == nil {
                OnboardingView(state: state)
                    .transition(.opacity)
            }
        }
        .background(VerityTheme.board)
        .preferredColorScheme(.dark)
        .task { await state.restoreVault() }
        .alert("VERITY could not complete that action", isPresented: Binding(
            get: { state.lastError != nil },
            set: { if !$0 { state.lastError = nil } }
        )) {
            Button("OK") { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "Unknown error")
        }
        .alert(item: $state.updateNotice) { notice in
            if let url = notice.releaseURL {
                Alert(
                    title: Text(notice.title),
                    message: Text(notice.message),
                    primaryButton: .default(Text("Open Release")) { NSWorkspace.shared.open(url) },
                    secondaryButton: .cancel()
                )
            } else {
                Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK")))
            }
        }
    }
}

private struct CommandHeader: View {
    @Bindable var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                Text("VERITY")
                    .font(VerityTheme.stencil(21))
                    .tracking(2.1)
                    .foregroundStyle(Color(red: 0.812, green: 0.839, blue: 0.886))
                Text("STUDY OPS")
                    .font(VerityTheme.mono(10))
                    .tracking(2.8)
                    .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
                    .padding(.top, 5)
            }
            .frame(minWidth: 210, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(Workspace.allCases) { workspace in
                    Button {
                        state.selectedWorkspace = workspace
                    } label: {
                        HStack(spacing: 8) {
                            StatusLED(
                                color: workspace == .chrono && state.activeTimer != nil ? VerityTheme.success : VerityTheme.warning,
                                isActive: state.selectedWorkspace == workspace || (workspace == .chrono && state.activeTimer != nil)
                            )
                            Text(workspace.title)
                                .font(VerityTheme.mono(11, semibold: true))
                                .tracking(1.54)
                            Text(String(workspace.shortcut))
                                .font(VerityTheme.mono(9))
                                .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color(red: 0.043, green: 0.051, blue: 0.063), in: RoundedRectangle(cornerRadius: 2))
                                .overlay { RoundedRectangle(cornerRadius: 2).stroke(VerityTheme.boardEdge) }
                        }
                        .foregroundStyle(state.selectedWorkspace == workspace ? Color(red: 0.910, green: 0.875, blue: 0.784) : Color(red: 0.290, green: 0.318, blue: 0.369))
                        .padding(.horizontal, 13)
                        .padding(.top, 8)
                        .padding(.bottom, 7)
                        .background(
                            LinearGradient(
                                colors: state.selectedWorkspace == workspace
                                    ? [Color(red: 0.125, green: 0.145, blue: 0.180), Color(red: 0.090, green: 0.106, blue: 0.133)]
                                    : [Color(red: 0.094, green: 0.110, blue: 0.137), Color(red: 0.071, green: 0.082, blue: 0.106)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            in: RoundedRectangle(cornerRadius: 3)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(state.selectedWorkspace == workspace ? Color(red: 0.227, green: 0.259, blue: 0.318) : VerityTheme.boardEdge, lineWidth: 1)
                        }
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(state.selectedWorkspace == workspace ? Color(red: 0.227, green: 0.259, blue: 0.318) : VerityTheme.boardEdge)
                                .frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(workspace.title)
                    .accessibilityHint(Text(verbatim: "Command \(workspace.shortcut)"))
                }
            }

            Spacer(minLength: 8)

            if state.isLoading {
                ProgressView().controlSize(.small)
            }
            if state.activeTimer != nil {
                Button {
                    state.selectedWorkspace = .chrono
                } label: {
                    HStack(spacing: 7) {
                        StatusLED(color: VerityTheme.success)
                        Text(state.elapsedClock)
                            .font(VerityTheme.mono(12, semibold: true))
                            .monospacedDigit()
                    }
                    .foregroundStyle(VerityTheme.success)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.black.opacity(0.32), in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(VerityTheme.boardEdge) }
                }
                .buttonStyle(.plain)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(formatted(context.date, as: "HH:mm"))
                            .font(VerityTheme.mono(30, semibold: true))
                            .foregroundStyle(Color(red: 0.851, green: 0.875, blue: 0.914))
                        Text(":" + formatted(context.date, as: "ss"))
                            .font(VerityTheme.mono(18))
                            .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
                    }
                    .monospacedDigit()
                    Text(formatted(context.date, as: "EEEE · dd MMM · yyyy").uppercased())
                        .font(VerityTheme.mono(10))
                        .tracking(2.2)
                        .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Current time")
            }
            .frame(minWidth: 170, alignment: .trailing)
        }
        .padding(.top, 38)
        .padding(.bottom, 12)
        .background(
            LinearGradient(colors: [Color(red: 0.078, green: 0.094, blue: 0.122), VerityTheme.board], startPoint: .top, endPoint: .bottom)
        )
        .overlay(alignment: .bottom) { Rectangle().fill(VerityTheme.boardEdge).frame(height: 2) }
        .shadow(color: .black.opacity(0.32), radius: 9, y: 10)
    }

    private func formatted(_ date: Date, as format: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}

private struct FunctionKeyRail: View {
    let workspace: Workspace

    private var hints: [(String, String)] {
        switch workspace {
        case .rack: [("J/K", "MOVE"), ("RETURN", "EDIT / NEW"), ("⌘N", "NEW STRIP"), ("⌘T", "TODAY")]
        case .chrono: [("RETURN", "START"), ("⌘SPACE", "STOP + LOG"), ("⌘D", "MARK DONE")]
        case .pending: [("J/K", "MOVE"), ("⌘⇧N", "QUICK ADD"), ("X", "MARK DONE")]
        case .roster: [("J/K", "COURSE"), ("RETURN", "ADVANCE STATUS")]
        case .tally: [("[ / ]", "WEEK"), ("⌘T", "THIS WEEK")]
        case .dispatch: [("⌘N", "NEW SESSION"), ("⌘RETURN", "SEND"), ("ESC", "CANCEL")]
        }
    }

    var body: some View {
        HStack(spacing: 18) {
            key("⌘1–6", "BOARD")
            ForEach(Array(hints.enumerated()), id: \.offset) { _, hint in key(hint.0, hint.1) }
            Spacer()
            key("ESC", "CANCEL")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(LinearGradient(colors: [Color(red: 0.067, green: 0.078, blue: 0.098), Color(red: 0.043, green: 0.051, blue: 0.067)], startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(VerityTheme.boardEdge).frame(height: 1) }
        .accessibilityHidden(true)
    }

    private func key(_ shortcut: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(shortcut)
                .font(VerityTheme.mono(10, semibold: true))
                .foregroundStyle(Color(red: 0.725, green: 0.761, blue: 0.820))
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Color(red: 0.090, green: 0.106, blue: 0.133), in: RoundedRectangle(cornerRadius: 3))
                .overlay { RoundedRectangle(cornerRadius: 3).stroke(Color(red: 0.212, green: 0.239, blue: 0.286)) }
            Text(label)
                .font(VerityTheme.mono(10))
                .tracking(1)
                .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
        }
    }
}

private struct WorkspaceView: View {
    @Bindable var state: AppState
    let workspace: Workspace

    @ViewBuilder
    var body: some View {
        switch workspace {
        case .rack: RackWorkspace(state: state)
        case .chrono: ChronoWorkspace(state: state)
        case .pending: PendingWorkspace(state: state)
        case .roster: RosterWorkspace(state: state)
        case .tally: TallyWorkspace(state: state)
        case .dispatch: DispatchWorkspace(state: state)
        }
    }
}

private struct DispatchWorkspace: View {
    @Bindable var state: AppState
    @State private var isCreating = false
    @State private var draft = ""
    @State private var attachments: [URL] = []
    @State private var proposalReview: ProposalReview?
    @State private var sessionToDelete: AssistantSession?

    var body: some View {
        BoardSurface(title: "DISPATCH") {
            if let session = state.selectedSession {
                sessionView(session)
            } else {
                sessionList
            }
        }
        .sheet(isPresented: $isCreating) {
            NewSessionForm(courses: state.courses) { mode, provider, model, effort, course in
                Task { await state.createSession(mode: mode, provider: provider, model: model, effort: effort, courseName: course) }
                isCreating = false
            } onCancel: { isCreating = false }
        }
        .onChange(of: state.requestedNewItemWorkspace) { _, request in
            guard request == .dispatch else { return }
            isCreating = true
            state.requestedNewItemWorkspace = nil
        }
        .onAppear {
            guard state.requestedNewItemWorkspace == .dispatch else { return }
            isCreating = true
            state.requestedNewItemWorkspace = nil
        }
        .sheet(item: $proposalReview) { review in
            ProposalReviewSheet(review: review) { singleProposal in
                Task {
                    if let singleProposal, let singleReview = await state.reviewProposals([singleProposal]) {
                        await state.applyProposalReview(singleReview)
                    } else if singleProposal == nil {
                        await state.applyProposalReview(review)
                    }
                }
                proposalReview = nil
            } onCancel: {
                proposalReview = nil
            }
        }
        .confirmationDialog("Delete this DISPATCH session?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Session and Attachments", role: .destructive) {
                if let session = sessionToDelete { Task { await state.deleteSession(id: session.id) } }
                sessionToDelete = nil
            }
            Button("Cancel", role: .cancel) { sessionToDelete = nil }
        } message: {
            Text("This removes the local session transcript and its copied attachments from the selected vault. It does not change study files proposed by the session.")
        }
    }

    private var sessionList: some View {
        Group {
            HStack {
                Text("\(state.sessions.count) SESSIONS")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(VerityTheme.etch)
                Spacer()
                Button("New Session", systemImage: "plus") { isCreating = true }
                    .buttonStyle(VerityHardwareButtonStyle())
            }
            if state.sessions.isEmpty {
                EmptyBay("No DISPATCH sessions", systemImage: "bubble.left.and.bubble.right", detail: "Start an Ask or Research session with a supported local AI provider.")
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(state.sessions) { session in
                            Button { state.selectedSessionID = session.id } label: {
                                PaperStrip(
                                    accent: session.mode == .research ? .purple : .blue,
                                    capText: session.mode == .research ? "RSRCH" : "ASK",
                                    capSub: session.provider.rawValue.uppercased()
                                ) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(session.courseName ?? session.mode.rawValue.capitalized).font(.headline)
                                            Text("\(session.provider.rawValue.uppercased()) · \(session.model) · \(session.updatedAt)")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(VerityTheme.ink.opacity(0.6))
                                            if let preview = session.messages.last?.text, !preview.isEmpty {
                                                Text(preview).lineLimit(2).font(.subheadline)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sessionView(_ session: AssistantSession) -> some View {
        HStack {
            Button("Back", systemImage: "chevron.left") { state.selectedSessionID = nil }
            VStack(alignment: .leading) {
                Text(session.courseName ?? session.mode.rawValue.capitalized).font(.headline)
                Text("\(session.provider.rawValue.uppercased()) · \(session.model)")
                    .font(.caption.monospaced())
                    .foregroundStyle(VerityTheme.etch)
            }
            Spacer()
            if state.assistantBusy {
                ProgressView().controlSize(.small)
                Button("Cancel Reply", systemImage: "xmark.circle") { state.cancelAssistantReply() }
            }
            Button("Delete Session", systemImage: "trash", role: .destructive) {
                sessionToDelete = session
            }
            .labelStyle(.iconOnly)
        }

        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(session.messages) { message in
                        MessageBubble(message: message) { proposals in
                            Task { proposalReview = await state.reviewProposals(proposals) }
                        }
                        .id(message.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: session.messages.count) { _, _ in
                if let last = session.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }

        VStack(spacing: 8) {
            if !attachments.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(attachments, id: \.self) { url in
                            HStack(spacing: 5) {
                                Image(systemName: "paperclip")
                                Text(url.lastPathComponent).lineLimit(1)
                                Button("Remove", systemImage: "xmark.circle.fill") { attachments.removeAll { $0 == url } }
                                    .labelStyle(.iconOnly)
                                    .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
            HStack(alignment: .bottom) {
                Button("Attach Files", systemImage: "paperclip") { chooseAttachments() }
                    .labelStyle(.iconOnly)
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 44, maxHeight: 120)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(VerityTheme.boardRaised, in: RoundedRectangle(cornerRadius: 4))
                    .overlay { RoundedRectangle(cornerRadius: 4).stroke(VerityTheme.boardEdge) }
                Button("Send", systemImage: "arrow.up.circle.fill") { send() }
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.assistantBusy)
                    .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }

    private func chooseAttachments() {
        let panel = NSOpenPanel()
        panel.title = "Attach Study Material"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        attachments.append(contentsOf: panel.urls.filter { !attachments.contains($0) })
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let payloads = attachments.compactMap { url -> AssistantAttachment? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return AssistantAttachment(filename: url.lastPathComponent, data: data)
        }
        draft = ""
        attachments = []
        state.beginSendingMessage(text, attachments: payloads)
    }
}

private struct MessageBubble: View {
    let message: AssistantMessage
    let review: ([Proposal]) -> Void

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 80) }
            VStack(alignment: .leading, spacing: 10) {
                Text(message.role == .user ? "YOU" : "VERITY")
                    .font(.caption2.bold().monospaced())
                    .foregroundStyle(message.role == .user ? VerityTheme.etch : VerityTheme.ink.opacity(0.55))
                Text(message.text).textSelection(.enabled)
                if let attachments = message.attachments {
                    ForEach(attachments, id: \.self) { Label(URL(fileURLWithPath: $0).lastPathComponent, systemImage: "paperclip") }
                }
                if let proposals = message.proposals, !proposals.isEmpty {
                    Divider()
                    ForEach(proposals) { proposal in
                        HStack {
                            Label(proposal.file, systemImage: "doc.badge.gearshape")
                                .font(.caption.monospaced())
                            Spacer()
                            if proposal.appliedAt != nil {
                                Label("Applied", systemImage: "checkmark.seal.fill")
                                    .foregroundStyle(VerityTheme.success)
                                    .font(.caption.bold())
                            } else {
                                Button("Review") { review([proposal]) }
                            }
                        }
                    }
                    let unapplied = proposals.filter { $0.appliedAt == nil }
                    if unapplied.count > 1 {
                        Button("Review All \(unapplied.count) Changes") { review(unapplied) }
                            .buttonStyle(VerityHardwareButtonStyle())
                    }
                }
            }
            .padding(14)
            .foregroundStyle(message.role == .user ? VerityTheme.etch : VerityTheme.ink)
            .background(
                message.role == .user ? AnyShapeStyle(VerityTheme.boardRaised) : AnyShapeStyle(VerityTheme.paper),
                in: RoundedRectangle(cornerRadius: 4, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(message.role == .user ? VerityTheme.boardEdge : VerityTheme.ink.opacity(0.16), lineWidth: 1)
            }
            if message.role == .assistant { Spacer(minLength: 80) }
        }
    }
}

private struct NewSessionForm: View {
    let courses: [String]
    @State private var mode: AssistantMode = .ask
    @State private var provider: AssistantProvider = .claude
    @State private var model = ProviderCatalog.all[0].models[0]
    @State private var effort = "high"
    @State private var course = ""
    let onSave: (AssistantMode, AssistantProvider, String, String, String?) -> Void
    let onCancel: () -> Void

    private var descriptor: ProviderDescriptor { ProviderCatalog.all.first { $0.id == provider }! }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New DISPATCH Session").font(.title2.bold())
            Form {
                Picker("Mode", selection: $mode) {
                    Text("Ask").tag(AssistantMode.ask)
                    Text("Research").tag(AssistantMode.research)
                }.pickerStyle(.segmented)
                Picker("Provider", selection: $provider) {
                    ForEach(ProviderCatalog.all) { Text($0.label).tag($0.id) }
                }
                Picker("Model", selection: $model) {
                    ForEach(descriptor.models, id: \.self) { Text($0).tag($0) }
                }
                if !descriptor.effortLevels.isEmpty {
                    Picker("Effort", selection: $effort) {
                        ForEach(descriptor.effortLevels, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                }
                if mode == .research {
                    Picker("Course", selection: $course) {
                        Text("Choose a course").tag("")
                        ForEach(courses, id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Create Session") { onSave(mode, provider, model, effort, mode == .research ? course : nil) }
                    .buttonStyle(VerityHardwareButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isEmpty || (mode == .research && course.isEmpty))
            }
        }
        .padding(24)
        .frame(width: 520)
        .onChange(of: provider) { _, newProvider in
            if let new = ProviderCatalog.all.first(where: { $0.id == newProvider }) {
                model = new.models.first ?? ""
                effort = new.effortLevels.contains("high") ? "high" : (new.effortLevels.first ?? "")
            }
        }
    }
}

private struct ProposalReviewSheet: View {
    let review: ProposalReview
    let onApply: (Proposal?) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Review Vault Changes", systemImage: "exclamationmark.shield.fill")
                .font(.title2.bold())
            Text("DISPATCH cannot write these files until you explicitly apply them. Read each destination and proposed content carefully.")
                .foregroundStyle(.secondary)
            TabView {
                ForEach(review.entries, id: \.proposal.id) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.proposal.file).font(.headline.monospaced()).textSelection(.enabled)
                        HSplitView {
                            reviewPane(title: entry.originalContent == nil ? "NEW FILE" : "CURRENT", content: entry.originalContent ?? "This file does not exist yet.")
                            reviewPane(title: "PROPOSED", content: entry.proposal.newContent)
                        }
                        if let diff = LineDiff.compare(old: entry.originalContent ?? "", new: entry.proposal.newContent) {
                            DisclosureGroup("Line-by-line changes (\(diff.filter { $0.kind == .added }.count) added, \(diff.filter { $0.kind == .removed }.count) removed)") {
                                ScrollView {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        ForEach(diff) { row in
                                            Text(diffPrefix(row.kind) + row.line)
                                                .font(.caption.monospaced())
                                                .foregroundStyle(diffForeground(row.kind))
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.horizontal, 6).padding(.vertical, 1)
                                                .background(diffBackground(row.kind))
                                                .textSelection(.enabled)
                                        }
                                    }
                                }
                                .frame(minHeight: 120, maxHeight: 220)
                            }
                        } else {
                            Text("Line diff omitted because this change is exceptionally large; compare the complete current and proposed panes above.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if review.entries.count > 1 {
                            HStack {
                                Spacer()
                                Button("Apply Only This Change") { onApply(entry.proposal) }
                                    .help("Rechecks this file, then applies only this proposal")
                            }
                        }
                    }
                    .padding()
                    .tabItem { Text(URL(fileURLWithPath: entry.proposal.file).lastPathComponent) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(review.entries.count == 1 ? "Apply Reviewed Change" : "Apply All Reviewed Changes") { onApply(nil) }
                    .buttonStyle(VerityHardwareButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 760, minHeight: 560)
    }

    private func reviewPane(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold().monospaced()).foregroundStyle(.secondary)
            ScrollView {
                Text(content)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func diffPrefix(_ kind: LineDiffEntry.Kind) -> String {
        switch kind { case .unchanged: "  "; case .removed: "− "; case .added: "+ " }
    }

    private func diffForeground(_ kind: LineDiffEntry.Kind) -> Color {
        switch kind { case .unchanged: .secondary; case .removed: VerityTheme.danger; case .added: VerityTheme.success }
    }

    private func diffBackground(_ kind: LineDiffEntry.Kind) -> Color {
        switch kind { case .unchanged: .clear; case .removed: VerityTheme.danger.opacity(0.09); case .added: VerityTheme.success.opacity(0.09) }
    }
}

private struct RosterWorkspace: View {
    @Bindable var state: AppState

    private var selectedCourse: Binding<String> {
        Binding(
            get: { state.selectedCourse ?? state.courses.first ?? "" },
            set: { state.selectedCourse = $0 }
        )
    }

    var body: some View {
        BoardSurface(title: "ROSTER") {
            if state.courses.isEmpty {
                EmptyBay("No courses found", systemImage: "books.vertical", detail: "Add compatible course block libraries to the selected vault.")
                    .frame(maxWidth: .infinity, minHeight: 280)
            } else {
                HStack {
                    Picker("Course", selection: selectedCourse) {
                        ForEach(state.courses, id: \.self) { Text($0).tag($0) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 360)
                    Spacer()
                    if let course = state.selectedCourse, let next = state.nextBlock(course: course) {
                        Text("NEXT · \([next.topic, next.blockType].compactMap { $0 }.joined(separator: " · "))")
                            .font(.caption.bold().monospaced())
                            .foregroundStyle(VerityTheme.warning)
                    }
                }

                if let course = state.selectedCourse {
                    let rows = state.breakdown(course: course)
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(rows.enumerated()), id: \.element.block.id) { _, row in
                                let isNext = state.nextBlock(course: course)?.id == row.block.id
                                PaperStrip(accent: isNext ? VerityTheme.warning : .blue, capText: StripCode.make(course), isSelected: isNext) {
                                    HStack(spacing: 14) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(row.block.topic ?? course).font(.headline)
                                            Text(row.block.blockType.uppercased())
                                                .font(.caption.bold().monospaced())
                                            if !row.block.output.isEmpty {
                                                Text(row.block.output)
                                                    .font(.caption)
                                                    .foregroundStyle(VerityTheme.ink.opacity(0.65))
                                            }
                                        }
                                        Spacer()
                                        if course.hasPrefix("Boards-"), row.block.topic != nil {
                                            Button(row.status.rawValue) {
                                                Task { await state.cycleSyllabus(for: row.block, current: row.status) }
                                            }
                                            .buttonStyle(.bordered)
                                            .help("Cycle syllabus status")
                                        }
                                        if isNext {
                                            Button("Mark Done", systemImage: "checkmark") {
                                                Task { await state.advance(row.block) }
                                            }
                                            .buttonStyle(VerityHardwareButtonStyle())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct TallyWorkspace: View {
    @Bindable var state: AppState
    @State private var weekStart = Self.monday(containing: Date())

    private var weekEnd: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
    }

    private var stats: (courses: [CourseStatistics], homework: HomeworkStatistics) {
        state.statistics(from: Self.format(weekStart), to: Self.format(weekEnd))
    }

    var body: some View {
        BoardSurface(title: "TALLY") {
            HStack {
                Button("Previous Week", systemImage: "chevron.left") { shift(-7) }.labelStyle(.iconOnly)
                Text("\(Self.format(weekStart)) — \(Self.format(weekEnd))")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(VerityTheme.etch)
                Button("Next Week", systemImage: "chevron.right") { shift(7) }.labelStyle(.iconOnly)
                Button("This Week") { weekStart = Self.monday(containing: Date()) }
                Spacer()
            }

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                    ForEach(stats.courses) { row in
                        MetricCard(
                            title: row.course,
                            minutes: row.totalMinutes,
                            completed: row.completedTasks,
                            total: row.totalTasks,
                            percent: row.percentComplete,
                            accent: .blue
                        )
                    }
                    MetricCard(
                        title: "Homework",
                        minutes: stats.homework.totalMinutes,
                        completed: stats.homework.completedCount,
                        total: stats.homework.totalCount,
                        percent: stats.homework.percentComplete,
                        accent: VerityTheme.warning
                    )
                }
            }
        }
    }

    private func shift(_ days: Int) {
        weekStart = Calendar.current.date(byAdding: .day, value: days, to: weekStart) ?? weekStart
    }

    private static func monday(containing date: Date) -> Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return calendar.startOfDay(for: start)
    }

    private static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct MetricCard: View {
    let title: String
    let minutes: Int
    let completed: Int
    let total: Int
    let percent: Int
    let accent: Color

    var body: some View {
        PaperStrip(accent: accent, capText: StripCode.make(title)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.uppercased()).font(.headline.monospaced())
                HStack(alignment: .firstTextBaseline) {
                    Text("\(minutes)").font(.system(size: 34, weight: .bold, design: .monospaced))
                    Text("MIN").font(.caption.bold())
                    Spacer()
                    Text("\(percent)%").font(.title2.bold().monospacedDigit())
                }
                ProgressView(value: Double(percent), total: 100)
                    .tint(accent)
                    .accessibilityLabel("Course completion")
                    .accessibilityValue("\(percent) percent")
                Text("\(completed) OF \(total) BLOCKS")
                    .font(.caption.monospaced())
                    .foregroundStyle(VerityTheme.ink.opacity(0.6))
            }
        }
    }
}

private struct ChronoWorkspace: View {
    @Bindable var state: AppState
    @State private var confirmDiscard = false

    private var timerOptions: [ScheduleSlot] {
        state.schedule.filter { $0.referenceType != .fixed }
    }

    var body: some View {
        BoardSurface(title: "CHRONO") {
            if let active = state.activeTimer {
                VStack(spacing: 22) {
                    Text(state.elapsedClock)
                        .font(.system(size: 72, weight: .medium, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(VerityTheme.paper)
                        .contentTransition(.numericText())
                        .accessibilityLabel("Elapsed study time")
                        .accessibilityValue(state.elapsedClock)
                    PaperStrip(
                        accent: VerityTheme.success,
                        capText: StripCode.make(active.target.course ?? (active.target.referenceType == .homework ? "HW" : active.target.referenceLabel)),
                        capSub: "ACTIVE",
                        isSelected: true
                    ) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(active.target.referenceLabel).font(.title3.bold())
                            Text(active.target.referenceType.rawValue.uppercased())
                                .font(.caption.bold().monospaced())
                        }
                    }
                    HStack {
                        Button("Stop and Log", systemImage: "stop.fill") {
                            Task { await state.stopAndLogTimer() }
                        }
                        .buttonStyle(VerityHardwareButtonStyle())
                        .controlSize(.large)
                        Button("Discard…", systemImage: "xmark", role: .destructive) { confirmDiscard = true }
                            .controlSize(.large)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 36)
            } else {
                if let minutes = state.lastLoggedMinutes {
                    HStack {
                        Label("Logged \(minutes) minutes", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(VerityTheme.success)
                            .font(.headline)
                        if let target = state.lastLoggedTarget {
                            Button(target.referenceType == .course ? "Mark Block Done" : "Mark Homework Done") {
                                Task { await state.completeLastLoggedTarget() }
                            }
                            .buttonStyle(VerityHardwareButtonStyle())
                        }
                    }
                }
                Text("Pull a strip into the timer")
                    .font(.headline)
                    .foregroundStyle(VerityTheme.etch)
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(timerOptions) { slot in
                            Button {
                                Task { await state.startTimer(for: slot) }
                            } label: {
                                PaperStrip(
                                    accent: slot.referenceType == .homework ? VerityTheme.warning : .blue,
                                    capText: StripCode.make(slot.referenceType == .homework ? "HW" : slot.referenceLabel),
                                    capSub: slot.referenceType.rawValue.uppercased()
                                ) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(slot.referenceLabel).font(.headline)
                                            Text("\(slot.startTime) · \(slot.durationMinutes) MIN")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(VerityTheme.ink.opacity(0.6))
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        ForEach(state.homework.filter { $0.status == .open }.prefix(3)) { item in
                            Button {
                                Task { await state.startTimer(for: item) }
                            } label: {
                                PaperStrip(accent: VerityTheme.warning, capText: "HW", capSub: item.subject.uppercased()) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(item.subject) — \(item.task)").font(.headline)
                                            Text("HOMEWORK · DUE \(item.dueDate)")
                                                .font(.caption.monospaced())
                                                .foregroundStyle(VerityTheme.ink.opacity(0.6))
                                        }
                                        Spacer()
                                        Image(systemName: "play.fill")
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .confirmationDialog("Discard this study timer?", isPresented: $confirmDiscard) {
            Button("Discard Timer", role: .destructive) { Task { await state.discardTimer() } }
            Button("Keep Studying", role: .cancel) {}
        } message: {
            Text("The elapsed time will not be added to the time log.")
        }
    }
}

private struct BoardSurface<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            BoardBackdrop().ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(title)
                        .font(VerityTheme.stencil(16))
                        .tracking(2.88)
                        .foregroundStyle(Color(red: 0.725, green: 0.761, blue: 0.820))
                    Spacer()
                }
                content
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
            .padding(.bottom, 8)
        }
    }
}

private struct OnboardingView: View {
    @Bindable var state: AppState
    @State private var isChoosing = false

    var body: some View {
        ZStack {
            VisualEffect(material: .hudWindow, blendingMode: .behindWindow)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VERITY")
                            .font(.system(size: 30, weight: .black, design: .monospaced))
                        Text("Choose your local study vault")
                            .foregroundStyle(.secondary)
                    }
                }

                Text("VERITY reads and writes ordinary Markdown files in the folder you choose. Your study data remains yours and can still be opened in Obsidian.")
                    .fixedSize(horizontal: false, vertical: true)

                if let suggestion = state.legacyVaultSuggestion {
                    Button {
                        Task { try? await state.useVault(suggestion) }
                    } label: {
                        Label("Use previous VERITY vault", systemImage: "clock.arrow.circlepath")
                    }
                    Text(suggestion.path(percentEncoded: false))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack {
                    Button("Choose Existing Vault…") { chooseVault() }
                        .buttonStyle(VerityHardwareButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    Button("Create New Vault…") { createVault() }
                    if isChoosing { ProgressView().controlSize(.small) }
                }

                Text("VERITY Native keeps its own app settings and does not modify your current Electron VERITY configuration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(30)
            .frame(width: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(VerityTheme.boardEdge, lineWidth: 1)
            }
            .shadow(radius: 24)
        }
    }

    private func chooseVault() {
        let panel = NSOpenPanel()
        panel.title = "Choose a VERITY or Obsidian Vault"
        panel.prompt = "Use Vault"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isChoosing = true
        Task {
            defer { isChoosing = false }
            do { try await state.useVault(url) }
            catch { state.lastError = error.localizedDescription }
        }
    }

    private func createVault() {
        let panel = NSSavePanel()
        panel.title = "Create a New VERITY Vault"
        panel.prompt = "Create Vault"
        panel.nameFieldStringValue = "VERITY Vault"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isChoosing = true
        Task {
            defer { isChoosing = false }
            do { try await state.createVault(at: url) }
            catch { state.lastError = error.localizedDescription }
        }
    }
}

private struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct RackWorkspace: View {
    @Bindable var state: AppState
    @State private var isAdding = false
    @State private var editingSlot: ScheduleSlot?
    @State private var pendingOverwriteSlot: ScheduleSlot?
    @State private var slotToDelete: ScheduleSlot?

    var body: some View {
        BoardSurface(title: "RACK") {
            HStack {
                Button("Previous Day", systemImage: "chevron.left") { Task { await state.shiftSelectedDate(days: -1) } }
                    .labelStyle(.iconOnly)
                Text(state.selectedDate)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(VerityTheme.etch)
                Button("Next Day", systemImage: "chevron.right") { Task { await state.shiftSelectedDate(days: 1) } }
                    .labelStyle(.iconOnly)
                Button("Today") { Task { await state.selectToday() } }
                Spacer()
                Button("New Strip", systemImage: "plus") { isAdding = true }
                    .buttonStyle(VerityHardwareButtonStyle())
            }

            rackTimeline
        }
        .sheet(isPresented: $isAdding) {
            ScheduleSlotForm(state: state) { slot in
                isAdding = false
                if state.schedule.contains(where: { $0.startTime == slot.startTime }) {
                    pendingOverwriteSlot = slot
                } else {
                    Task { await state.addScheduleSlot(slot) }
                }
            } onCancel: { isAdding = false }
        }
        .onChange(of: state.requestedNewItemWorkspace) { _, request in
            guard request == .rack else { return }
            isAdding = true
            state.requestedNewItemWorkspace = nil
        }
        .onAppear {
            guard state.requestedNewItemWorkspace == .rack else { return }
            isAdding = true
            state.requestedNewItemWorkspace = nil
        }
        .sheet(item: $editingSlot) { slot in
            ScheduleSlotForm(state: state, initial: slot) { updated in
                Task { await state.updateScheduleSlot(originalStartTime: slot.startTime, slot: updated) }
                editingSlot = nil
            } onCancel: { editingSlot = nil }
        }
        .confirmationDialog("Replace the strip at this start time?", isPresented: Binding(
            get: { pendingOverwriteSlot != nil },
            set: { if !$0 { pendingOverwriteSlot = nil } }
        ), titleVisibility: .visible) {
            Button("Replace Existing Strip", role: .destructive) {
                if let slot = pendingOverwriteSlot { Task { await state.addScheduleSlot(slot) } }
                pendingOverwriteSlot = nil
            }
            Button("Cancel", role: .cancel) { pendingOverwriteSlot = nil }
        } message: {
            Text(pendingOverwriteSlot.map { "A strip already starts at \($0.startTime). The Markdown schedule format allows one strip per start time." } ?? "")
        }
        .confirmationDialog("Delete this schedule strip?", isPresented: Binding(
            get: { slotToDelete != nil },
            set: { if !$0 { slotToDelete = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Strip", role: .destructive) {
                if let slot = slotToDelete { Task { await state.deleteScheduleSlot(startTime: slot.startTime) } }
                slotToDelete = nil
            }
            Button("Cancel", role: .cancel) { slotToDelete = nil }
        } message: {
            Text(slotToDelete.map { "\($0.startTime) · \($0.referenceLabel)" } ?? "")
        }
    }

    private var rackTimeline: some View {
        let pointsPerMinute = 1.5
        let trackHeight = 1440.0 * pointsPerMinute
        return ScrollViewReader { proxy in
            ScrollView(.vertical) {
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                Color.clear
                                    .frame(width: 1, height: 60 * pointsPerMinute)
                                    .id("rack-hour-\(hour)")
                            }
                        }

                        Rectangle()
                            .fill(VerityTheme.boardEdge)
                            .frame(width: 2, height: trackHeight)
                            .offset(x: 70)

                        ForEach(0...24, id: \.self) { hour in
                            HStack(spacing: 12) {
                                Text(String(format: "%02d:00", hour))
                                    .font(VerityTheme.mono(10))
                                    .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
                                    .frame(width: 58, alignment: .trailing)
                                Rectangle()
                                    .fill(VerityTheme.etch.opacity(0.10))
                                    .frame(height: 1)
                            }
                            .frame(width: geometry.size.width)
                            .offset(y: Double(hour * 60) * pointsPerMinute)
                        }

                        ForEach(state.schedule, id: \.startTime) { slot in
                            let adherence = state.adherence(for: slot)
                            let marker = timelineMarker(for: slot)
                            let start = minutes(slot.startTime)
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(slot.startTime)
                                        .font(VerityTheme.mono(12, semibold: true))
                                        .foregroundStyle(Color(red: 0.804, green: 0.831, blue: 0.878))
                                    Text("\(slot.durationMinutes)m")
                                        .font(VerityTheme.mono(9))
                                        .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
                                }
                                .frame(width: 58, alignment: .trailing)

                                PaperStrip(
                                    accent: color(for: slot.referenceType),
                                    capText: StripCode.make(slot.referenceType == .homework ? "HW" : slot.referenceLabel),
                                    capSub: slot.referenceType.rawValue.uppercased(),
                                    isSelected: marker != nil
                                ) {
                                    HStack(spacing: 12) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(slot.referenceLabel)
                                                .font(VerityTheme.mono(13, semibold: true))
                                                .lineLimit(1)
                                            Text("\(slot.referenceType.rawValue.uppercased()) · \(slot.durationMinutes) MIN")
                                                .font(VerityTheme.mono(10))
                                                .foregroundStyle(VerityTheme.ink.opacity(0.62))
                                        }
                                        Spacer()
                                        if let marker {
                                            Text(marker)
                                                .font(VerityTheme.mono(9, semibold: true))
                                                .tracking(1)
                                                .foregroundStyle(VerityTheme.danger)
                                        }
                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(adherenceLabel(adherence.status))
                                                .font(VerityTheme.mono(9, semibold: true))
                                                .foregroundStyle(adherenceColor(adherence.status))
                                            if adherence.loggedMinutes > 0 {
                                                Text("\(adherence.loggedMinutes) MIN LOGGED")
                                                    .font(VerityTheme.mono(8))
                                                    .foregroundStyle(VerityTheme.ink.opacity(0.55))
                                            }
                                        }
                                        Button("Edit", systemImage: "pencil") { editingSlot = slot }
                                            .labelStyle(.iconOnly)
                                        Button("Delete", systemImage: "trash", role: .destructive) { slotToDelete = slot }
                                            .labelStyle(.iconOnly)
                                    }
                                }
                                .frame(height: max(46, min(Double(slot.durationMinutes) * pointsPerMinute - 4, 120)))
                            }
                            .frame(width: geometry.size.width)
                            .offset(y: Double(start) * pointsPerMinute)
                            .zIndex(marker == nil ? 1 : 3)
                        }

                        if state.selectedDate == todayString {
                            TimelineView(.periodic(from: .now, by: 60)) { context in
                                let now = Calendar.current.component(.hour, from: context.date) * 60
                                    + Calendar.current.component(.minute, from: context.date)
                                HStack(spacing: 0) {
                                    Color.clear.frame(width: 70)
                                    Circle().fill(VerityTheme.danger).frame(width: 8, height: 8).offset(x: -4)
                                    Rectangle().fill(VerityTheme.danger).frame(height: 2)
                                        .shadow(color: VerityTheme.danger, radius: 3)
                                    Text("NOW \(timeString(context.date))")
                                        .font(VerityTheme.mono(9))
                                        .tracking(2.7)
                                        .foregroundStyle(VerityTheme.danger)
                                        .padding(.leading, 6)
                                }
                                .frame(width: geometry.size.width)
                                .offset(y: Double(now) * pointsPerMinute)
                            }
                            .zIndex(4)
                        }

                        if state.schedule.isEmpty {
                            Button("⌁ EMPTY BAY — SLOT A STRIP") { isAdding = true }
                                .buttonStyle(.plain)
                                .font(VerityTheme.mono(11))
                                .tracking(1.7)
                                .foregroundStyle(Color(red: 0.290, green: 0.318, blue: 0.369))
                                .frame(width: max(0, geometry.size.width - 84), height: 40)
                                .overlay { RoundedRectangle(cornerRadius: 2).stroke(VerityTheme.boardEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                                .offset(x: 82, y: trackHeight - 48)
                        }
                    }
                    .frame(height: trackHeight + 10)
                }
                .frame(height: trackHeight + 10)
            }
            .task(id: state.selectedDate) {
                try? await Task.sleep(for: .milliseconds(180))
                let hour = Calendar.current.component(.hour, from: Date())
                proxy.scrollTo("rack-hour-\(max(0, hour - 3))", anchor: .top)
            }
        }
    }

    private var todayString: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func minutes(_ value: String) -> Int {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        return parts.count == 2 ? parts[0] * 60 + parts[1] : 0
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func color(for type: ScheduleReferenceType) -> Color {
        switch type {
        case .course: .blue
        case .homework: VerityTheme.warning
        case .fixed: .purple
        }
    }

    private func adherenceLabel(_ status: DomainRules.AdherenceStatus) -> String {
        switch status {
        case .completed: "COMPLETE"
        case .partial: "PARTIAL"
        case .pending: "PENDING"
        case .notLogged: "NOT LOGGED"
        case .notTracked: "FIXED"
        }
    }

    private func adherenceColor(_ status: DomainRules.AdherenceStatus) -> Color {
        switch status {
        case .completed: VerityTheme.success
        case .partial: VerityTheme.warning
        case .notLogged: VerityTheme.danger
        case .pending, .notTracked: VerityTheme.ink.opacity(0.55)
        }
    }

    private func timelineMarker(for slot: ScheduleSlot) -> String? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard state.selectedDate == formatter.string(from: Date()) else { return nil }
        let now = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        let startParts = slot.startTime.split(separator: ":").compactMap { Int($0) }
        guard startParts.count == 2 else { return nil }
        let start = startParts[0] * 60 + startParts[1]
        if now >= start, now < start + slot.durationMinutes { return "NOW" }
        let futureSlots = state.schedule.filter { candidate in
            let parts = candidate.startTime.split(separator: ":").compactMap { Int($0) }
            return parts.count == 2 && parts[0] * 60 + parts[1] > now
        }
        return futureSlots.first?.id == slot.id ? "NEXT" : nil
    }
}

private struct PendingWorkspace: View {
    @Bindable var state: AppState
    @State private var isAdding = false
    @State private var pendingDeletion: HomeworkItem?
    @State private var editingItem: HomeworkItem?
    @State private var quickDraft = ""

    private var items: [HomeworkItem] {
        let done = state.homework.filter { $0.status == .done }
        return state.orderedOpenHomework + done
    }

    var body: some View {
        BoardSurface(title: "PENDING") {
            HStack {
                Text("\(state.homework.filter { $0.status == .open }.count) OPEN")
                    .font(.caption.bold().monospaced())
                    .foregroundStyle(VerityTheme.etch)
                Spacer()
                Button("New Homework", systemImage: "plus") { isAdding = true }
                    .buttonStyle(VerityHardwareButtonStyle())
            }

            VStack(alignment: .leading, spacing: 5) {
                TextField("Science: lab report due 12/07 45m high", text: $quickDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addQuickHomework() }
                if let parsed = HomeworkQuickParser.parse(quickDraft) {
                    Text("FILES AS  \(parsed.subject) — \(parsed.task) · due \(parsed.dueDate) · \(parsed.estimatedMinutes)m · \(parsed.priority.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(VerityTheme.etch)
                } else {
                    Text("SUBJECT: TASK · due YYYY-MM-DD, DD/MM, tomorrow, Friday, or +3d · 45m · high/normal/low")
                        .font(.caption2.monospaced())
                        .foregroundStyle(VerityTheme.etch.opacity(0.75))
                }
            }

            if items.isEmpty {
                EmptyBay("Nothing pending", systemImage: "checkmark.circle", detail: "Your homework list is clear.")
                    .frame(maxWidth: .infinity, minHeight: 260)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            PaperStrip(accent: priorityColor(item.priority), capText: "HW", capSub: item.subject.uppercased()) {
                                HStack(spacing: 14) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.subject.uppercased())
                                                .font(.caption.bold().monospaced())
                                            Text(item.priority.rawValue.uppercased())
                                                .font(.caption2.bold())
                                                .foregroundStyle(priorityColor(item.priority))
                                        }
                                        Text(item.task)
                                            .font(.headline)
                                            .strikethrough(item.status == .done)
                                        Text("DUE \(item.dueDate) · \(item.estimatedMinutes) MIN")
                                            .font(.caption.monospaced())
                                            .foregroundStyle(VerityTheme.ink.opacity(0.6))
                                        if item.status == .open, let reason = state.homeworkUrgencyReason(id: item.id) {
                                            Text(reason.uppercased())
                                                .font(.caption2.bold().monospaced())
                                                .foregroundStyle(priorityColor(item.priority))
                                        }
                                    }
                                    Spacer()
                                    if item.status == .open {
                                        Button("Edit", systemImage: "pencil") { editingItem = item }
                                            .labelStyle(.iconOnly)
                                        Button("Mark Done", systemImage: "checkmark") {
                                            Task { await state.markHomeworkDone(id: item.id) }
                                        }
                                        .labelStyle(.iconOnly)
                                    }
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        pendingDeletion = item
                                    }
                                    .labelStyle(.iconOnly)
                                }
                            }
                            .opacity(item.status == .done ? 0.55 : 1)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isAdding) {
            HomeworkForm { subject, task, dueDate, minutes, priority in
                Task { await state.addHomework(subject: subject, task: task, dueDate: dueDate, minutes: minutes, priority: priority) }
                isAdding = false
            } onCancel: { isAdding = false }
        }
        .onChange(of: state.requestedNewItemWorkspace) { _, request in
            guard request == .pending else { return }
            isAdding = true
            state.requestedNewItemWorkspace = nil
        }
        .onAppear {
            guard state.requestedNewItemWorkspace == .pending else { return }
            isAdding = true
            state.requestedNewItemWorkspace = nil
        }
        .sheet(item: $editingItem) { item in
            HomeworkForm(initial: item) { subject, task, dueDate, minutes, priority in
                var updated = item
                updated.subject = subject
                updated.task = task
                updated.dueDate = dueDate
                updated.estimatedMinutes = minutes
                updated.priority = priority
                Task { await state.editHomework(updated) }
                editingItem = nil
            } onCancel: { editingItem = nil }
        }
        .confirmationDialog("Delete this homework item?", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        ), titleVisibility: .visible) {
            Button("Delete Homework", role: .destructive) {
                if let item = pendingDeletion { Task { await state.deleteHomework(id: item.id) } }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text(pendingDeletion.map { "\($0.subject) — \($0.task)" } ?? "")
        }
    }

    private func priorityColor(_ priority: HomeworkPriority) -> Color {
        switch priority {
        case .high: VerityTheme.danger
        case .normal: VerityTheme.warning
        case .low: VerityTheme.success
        }
    }

    private func addQuickHomework() {
        guard let parsed = HomeworkQuickParser.parse(quickDraft) else { return }
        quickDraft = ""
        Task { await state.addHomework(subject: parsed.subject, task: parsed.task, dueDate: parsed.dueDate, minutes: parsed.estimatedMinutes, priority: parsed.priority) }
    }
}

private struct HomeworkForm: View {
    @State private var subject = ""
    @State private var task = ""
    @State private var dueDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var minutes = 30
    @State private var priority: HomeworkPriority = .normal
    let onSave: (String, String, String, Int, HomeworkPriority) -> Void
    let onCancel: () -> Void
    private let editing: Bool

    init(initial: HomeworkItem? = nil, onSave: @escaping (String, String, String, Int, HomeworkPriority) -> Void, onCancel: @escaping () -> Void) {
        _subject = State(initialValue: initial?.subject ?? "")
        _task = State(initialValue: initial?.task ?? "")
        if let date = initial.flatMap({ Self.dateFormatter.date(from: $0.dueDate) }) {
            _dueDate = State(initialValue: date)
        } else {
            _dueDate = State(initialValue: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        }
        _minutes = State(initialValue: initial?.estimatedMinutes ?? 30)
        _priority = State(initialValue: initial?.priority ?? .normal)
        self.onSave = onSave
        self.onCancel = onCancel
        self.editing = initial != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editing ? "Edit Homework" : "New Homework").font(.title2.bold())
            Form {
                TextField("Subject", text: $subject)
                TextField("Task", text: $task)
                DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                Stepper("Estimated time: \(minutes) minutes", value: $minutes, in: 5...600, step: 5)
                Picker("Priority", selection: $priority) {
                    ForEach(HomeworkPriority.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(editing ? "Save Changes" : "Add Homework") {
                    onSave(subject, task, Self.dateFormatter.string(from: dueDate), minutes, priority)
                }
                .buttonStyle(VerityHardwareButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(subject.trimmingCharacters(in: .whitespaces).isEmpty || task.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct ScheduleSlotForm: View {
    @Bindable var state: AppState
    @State private var startTime = "09:00"
    @State private var duration = 60
    @State private var type: ScheduleReferenceType = .course
    @State private var label = ""
    @State private var browseAllBlocks = false
    let onSave: (ScheduleSlot) -> Void
    let onCancel: () -> Void
    private let editing: Bool

    init(state: AppState, initial: ScheduleSlot? = nil, onSave: @escaping (ScheduleSlot) -> Void, onCancel: @escaping () -> Void) {
        self.state = state
        _startTime = State(initialValue: initial?.startTime ?? "09:00")
        _duration = State(initialValue: initial?.durationMinutes ?? 60)
        _type = State(initialValue: initial?.referenceType ?? .course)
        _label = State(initialValue: initial?.referenceLabel ?? "")
        _browseAllBlocks = State(initialValue: initial != nil)
        self.onSave = onSave
        self.onCancel = onCancel
        self.editing = initial != nil
    }

    private var candidates: [String] {
        switch type {
        case .course:
            let blocks = browseAllBlocks ? state.blocks : state.courses.compactMap { state.nextBlock(course: $0) }
            return blocks.map { block in
                [block.course, block.topic, block.blockType].compactMap { $0 }.joined(separator: " · ")
            }
        case .homework:
            return state.homework.filter { $0.status == .open }.map { "HW · \($0.subject) — \($0.task)" }
        case .fixed:
            return []
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Schedule Strip").font(.title2.bold())
            Form {
                TextField("Start time (HH:mm)", text: $startTime)
                Stepper("Duration: \(duration) minutes", value: $duration, in: 5...720, step: 5)
                Picker("Type", selection: $type) {
                    Text("Course").tag(ScheduleReferenceType.course)
                    Text("Homework").tag(ScheduleReferenceType.homework)
                    Text("Fixed").tag(ScheduleReferenceType.fixed)
                }
                if type == .course {
                    Toggle("Browse every course block", isOn: $browseAllBlocks)
                }
                if type == .fixed || candidates.isEmpty {
                    TextField(type == .fixed ? "Commitment" : "Label", text: $label)
                } else {
                    Picker("Strip", selection: $label) {
                        Text("Choose a strip").tag("")
                        ForEach(Array(Set(candidates + (label.isEmpty ? [] : [label]))).sorted(), id: \.self) { Text($0).tag($0) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(editing ? "Save Strip" : "Add Strip") {
                    onSave(ScheduleSlot(startTime: startTime, durationMinutes: duration, referenceType: type, referenceLabel: label))
                }
                .buttonStyle(VerityHardwareButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(label.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onChange(of: type) { _, _ in label = candidates.first ?? "" }
        .onChange(of: browseAllBlocks) { _, _ in label = candidates.first ?? label }
        .onChange(of: label) { _, selected in
            guard type == .course,
                  let block = state.blocks.first(where: {
                      [$0.course, $0.topic, $0.blockType].compactMap { $0 }.joined(separator: " · ") == selected
                  }),
                  let firstNumber = block.durationRange.split(whereSeparator: { !$0.isNumber }).first,
                  let suggested = Int(firstNumber)
            else { return }
            duration = suggested
        }
    }
}

private struct MenuBarCockpit: View {
    @Bindable var state: AppState
    let updateController: VerityUpdateController
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        if let active = state.activeTimer {
            Text("STUDYING · \(state.elapsedClock)")
            Text(active.target.referenceLabel)
            Button("Stop and Log", systemImage: "stop.fill") { Task { await state.stopAndLogTimer() } }
            Button("Discard Timer", systemImage: "xmark") { Task { await state.discardTimer() } }
        } else {
            Text("VERITY READY")
            if let next = state.todaySchedule.first(where: { $0.referenceType != .fixed && isUpcomingOrActive($0) }) {
                Button("Start \(next.referenceLabel)", systemImage: "play.fill") {
                    Task { await state.startTimer(for: next) }
                }
            }
        }
        if let next = state.nextTodayScheduleSlot {
            Text("NEXT · \(next.startTime)\(timeUntil(next).map { " · \($0)" } ?? "") · \(next.referenceLabel)")
        }
        if let urgent = state.orderedOpenHomework.first {
            Text("DUE · \(urgent.subject) — \(urgent.task)")
        }
        Divider()
        Button("Quick Add Homework…", systemImage: "plus.circle") {
            revealMain(workspace: .pending, requestNewItem: true)
        }
        Button("Open VERITY", systemImage: "macwindow") { revealMain() }
            .keyboardShortcut("o")
        Divider()
        Toggle("Launch at Login", isOn: Binding(
            get: { state.launchAtLoginEnabled },
            set: { state.setLaunchAtLogin($0) }
        ))
        Button("Check for Updates…") { updateController.checkForUpdates(state: state) }
            .disabled(state.isCheckingForUpdates)
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit VERITY") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func revealMain(workspace: Workspace? = nil, requestNewItem: Bool = false) {
        if let workspace {
            state.selectedWorkspace = workspace
            if requestNewItem { state.requestNewItem(in: workspace) }
        }
        openWindow(id: "main")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func timeUntil(_ slot: ScheduleSlot) -> String? {
        let parts = slot.startTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let now = Date()
        let current = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        let delta = parts[0] * 60 + parts[1] - current
        guard delta > 0 else { return nil }
        return delta >= 60 ? "in \(delta / 60)h \(delta % 60)m" : "in \(delta)m"
    }

    private func isUpcomingOrActive(_ slot: ScheduleSlot) -> Bool {
        let parts = slot.startTime.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return false }
        let current = Calendar.current.component(.hour, from: Date()) * 60 + Calendar.current.component(.minute, from: Date())
        return parts[0] * 60 + parts[1] + slot.durationMinutes > current
    }
}

private struct SettingsView: View {
    @Bindable var state: AppState
    @Binding var showMenuBarExtra: Bool
    let updateController: VerityUpdateController
    @State private var installCandidate: AssistantProvider?

    var body: some View {
        TabView {
            Form {
                LabeledContent("Selected vault") {
                    Text(state.selectedVaultURL?.path(percentEncoded: false) ?? "Not selected")
                        .foregroundStyle(.secondary)
                }
                Toggle("Show VERITY in the menu bar", isOn: $showMenuBarExtra)
                Toggle("Launch VERITY at login", isOn: Binding(
                    get: { state.launchAtLoginEnabled },
                    set: { state.setLaunchAtLogin($0) }
                ))
                Toggle("Notify me when today's study strips begin", isOn: Binding(
                    get: { state.studyRemindersEnabled },
                    set: { state.setStudyReminders($0) }
                ))
                HStack {
                    Button("Change Vault…") { state.changeVault() }
                    Button("Reveal in Finder") { state.revealVaultInFinder() }
                        .disabled(state.selectedVaultURL == nil)
                }
            }
            .padding()
            .tabItem { Label("General", systemImage: "gearshape") }

            Form {
                Section("Current study state") {
                    LabeledContent("Open homework", value: "\(state.orderedOpenHomework.count)")
                    LabeledContent("Today's strips", value: "\(state.todaySchedule.count)")
                    LabeledContent("Courses", value: "\(state.courses.count)")
                    LabeledContent("Timer") {
                        Text(state.activeTimer.map { "Running · \($0.target.referenceLabel)" } ?? "Stopped")
                            .lineLimit(1)
                    }
                }
                Section("Timer safety") {
                    Text("Timer recovery is written before the timer appears as running. Stopping appends the time log before clearing recovery state.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .tabItem { Label("Study", systemImage: "timer") }

            Form {
                Section("Local AI providers") {
                    ForEach(ProviderCatalog.all) { provider in
                        HStack(spacing: 10) {
                            Image(systemName: state.providerStatuses[provider.id]?.installed == true ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(state.providerStatuses[provider.id]?.installed == true ? VerityTheme.success : VerityTheme.warning)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.label).font(.headline)
                                if let status = state.providerStatuses[provider.id] {
                                    Text(providerStatusText(status))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let path = status.executablePath {
                                        Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary)
                                    }
                                } else {
                                    Text("Not checked").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if state.providerSetupBusy == provider.id {
                                ProgressView().controlSize(.small)
                            } else if state.providerStatuses[provider.id]?.installed == false {
                                if provider.id == .antigravity {
                                    Link("Get CLI", destination: URL(string: "https://antigravity.google/cli")!)
                                } else {
                                    Button("Install…") { installCandidate = provider.id }
                                }
                            } else if state.providerStatuses[provider.id]?.installed == true,
                                      state.providerStatuses[provider.id]?.authentication != .authenticated {
                                Button("Open Login") { state.openProviderLogin(provider.id) }
                            }
                            Button("Check") { Task { await state.refreshProviderStatus(provider.id) } }
                        }
                    }
                }
                Section("Approval boundary") {
                    Label("Providers receive read-only vault access. They cannot edit files directly.", systemImage: "lock.shield")
                    Label("Every proposed change must be reviewed and explicitly applied in VERITY.", systemImage: "checkmark.seal")
                }
            }
            .padding()
            .tabItem { Label("Assistant", systemImage: "sparkles") }

            Form {
                LabeledContent("Current version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development")
                }
                Button("Check for Updates…") { updateController.checkForUpdates(state: state) }
                    .disabled(state.isCheckingForUpdates)
                Picker("Update channel", selection: Binding(
                    get: { updateController.channel },
                    set: { updateController.setChannel($0) }
                )) {
                    Text("Stable").tag("stable")
                    Text("Beta").tag("beta")
                }
                Text("Stable receives production releases. Beta also receives prereleases and may be less reliable.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(
                    updateController.usesSignedAutomaticUpdates
                        ? "Signed automatic updates are enabled."
                        : "This development build checks GitHub Releases and opens the signed installer manually.",
                    systemImage: updateController.usesSignedAutomaticUpdates ? "checkmark.shield.fill" : "hammer.fill"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .tabItem { Label("Updates", systemImage: "arrow.triangle.2.circlepath") }

            Form {
                Section("Privacy") {
                    Label("No VERITY account, telemetry, analytics, or cloud backend", systemImage: "hand.raised.fill")
                    Label("Study data remains in the selected Markdown vault", systemImage: "folder.fill")
                    Label("Provider credentials remain in provider-owned storage", systemImage: "key.fill")
                }
                Section("Assistant write boundary") {
                    Text("Providers receive read-only access. Only an exact, visible, unexpired review can authorize VaultProposalApplier to write.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Advanced diagnostics") {
                    Text("The copied report contains app/runtime metadata and row counts only. It excludes vault paths, prompts, messages, file contents, attachments, and credentials.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Copy Redacted Diagnostics") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.diagnosticSummary(), forType: .string)
                    }
                }
            }
            .padding()
            .tabItem { Label("Privacy", systemImage: "lock.shield") }
        }
        .task {
            for provider in AssistantProvider.allCases { await state.refreshProviderStatus(provider) }
        }
        .confirmationDialog("Install this command-line provider?", isPresented: Binding(
            get: { installCandidate != nil },
            set: { if !$0 { installCandidate = nil } }
        ), titleVisibility: .visible) {
            Button("Install with npm") {
                if let provider = installCandidate { Task { await state.installProvider(provider) } }
                installCandidate = nil
            }
            Button("Cancel", role: .cancel) { installCandidate = nil }
        } message: {
            Text("VERITY will run npm install -g for the provider's official CLI package. This downloads software and changes your global npm installation.")
        }
    }

    private func providerStatusText(_ status: ProviderStatus) -> String {
        guard status.installed else { return "Not installed" }
        switch status.authentication {
        case .authenticated: return "Installed · credentials detected"
        case .notAuthenticated: return "Installed · login required"
        case .unknown: return "Installed · authentication status unknown"
        }
    }
}

private struct VerityCommands: Commands {
    @Bindable var state: AppState
    let updateController: VerityUpdateController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { updateController.checkForUpdates(state: state) }
                .disabled(state.isCheckingForUpdates)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Homework…") { state.requestNewItem(in: .pending) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Schedule Strip…") { state.requestNewItem(in: .rack) }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New DISPATCH Session…") { state.requestNewItem(in: .dispatch) }
                .keyboardShortcut("n", modifiers: [.command])
            Divider()
            Button("Change Vault…") { state.changeVault() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Button("Reveal Vault in Finder") { state.revealVaultInFinder() }
                .disabled(state.selectedVaultURL == nil)
        }
        CommandMenu("Study") {
            Button("Start Next Block") { Task { await state.startNextSelectedCourse() } }
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(state.activeTimer != nil || state.selectedCourse == nil)
            Button("Stop and Log") { Task { await state.stopAndLogTimer() } }
                .keyboardShortcut(.space, modifiers: [.command])
                .disabled(state.activeTimer == nil)
            if state.lastLoggedTarget != nil {
                Button("Mark Logged Work Done") { Task { await state.completeLastLoggedTarget() } }
                    .keyboardShortcut("d", modifiers: [.command])
            }
            Divider()
            Button("Today") {
                state.selectedWorkspace = .rack
                Task { await state.selectToday() }
            }
                .keyboardShortcut("t", modifiers: [.command])
        }
        CommandGroup(after: .sidebar) {
            ForEach(Workspace.allCases) { workspace in
                Button(workspace.title) { state.selectedWorkspace = workspace }
                    .keyboardShortcut(KeyEquivalent(workspace.shortcut), modifiers: [.command])
            }
        }
        CommandGroup(replacing: .help) {
            Button("VERITY Help") {
                NSWorkspace.shared.open(URL(string: "https://github.com/Flame119052/verity#readme")!)
            }
            Button("Privacy and Assistant Safety") {
                state.selectedWorkspace = .dispatch
            }
            Divider()
            Button("Report an Issue…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/Flame119052/verity/issues/new/choose")!)
            }
            Button("Release Notes") {
                NSWorkspace.shared.open(URL(string: "https://github.com/Flame119052/verity/releases")!)
            }
        }
    }
}
