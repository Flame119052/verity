# VERITY Native macOS Transition Specification

Status: completed for the 2.0.0 release; retained as the implementation and parity contract
Target: production-quality native macOS app
Minimum OS: macOS 14 Sonoma
Language/toolchain: Swift 6, SwiftUI, AppKit where required
Distribution: zero-cost direct DMG with ad-hoc code signature, SHA-256 manifest, and EdDSA-signed Sparkle updates; optional Developer ID/notarization profile if membership is ever supplied

## 1. Product outcome

VERITY Native replaces the Electron, React, browser, and localhost-server stack with a genuine macOS application. SwiftUI renders every product surface. AppKit is used only for macOS capabilities that SwiftUI does not expose precisely enough, such as advanced window control or open-panel behavior. No `WKWebView`, embedded browser UI, Electron runtime, React bundle, or HTTP UI is permitted in the finished app.

The transition is complete only when the native app:

1. Provides every current study workflow and DISPATCH capability.
2. Reads and writes the existing Markdown vault without destructive conversion.
3. Preserves the assistant's propose-review-approve security boundary.
4. Behaves like a mature Mac app: menus, shortcuts, windows, settings, status item, accessibility, launch at login, updates, signing, and clean removal.
5. Passes the automated, compatibility, recovery, security, packaging, and release gates in this document.

## 2. Non-negotiable product invariants

- The vault remains the source of truth for study data and stays readable in Obsidian.
- Existing vaults open in both Electron VERITY 1.1.5 and VERITY Native during the beta period.
- The native beta must not rewrite a file merely because it opened or parsed it.
- Every write is path-confined to the selected vault, coordinated, atomic, and followed by read-back validation.
- A provider process never receives direct write authority over the vault.
- Assistant-proposed writes happen only after a visible, explicit user approval in VERITY.
- An Apply action is bound to the exact content and base state the user reviewed; stale proposals require re-review.
- An active timer survives app/window closure and ordinary crashes without double logging or silently losing time.
- User-owned uncommitted repository changes and user vault data are never overwritten during development or migration.
- The shipping app contains no development menus, debug servers, personal absolute paths, telemetry, or analytics.

## 3. Current compatibility contract

### 3.1 Workspaces

The native top command rack preserves the current mental model and order:

1. Rack — day schedule composition and adherence.
2. Chrono — bind, run, stop, log, discard, advance cursor, and complete homework.
3. Pending — add, edit, prioritize, complete, and delete homework.
4. Roster — course breakdown, syllabus state, and cursor progression.
5. Tally — weekly course and homework statistics.
6. DISPATCH — provider setup, chat/research sessions, attachments, proposals, review, and apply.

The first native release improves presentation and platform behavior without replacing this information architecture.

### 3.2 Vault paths and formats

The following existing paths and schemas are frozen compatibility interfaces:

- `Progress/Homework.md`: front matter plus `id`, `subject`, `task`, `due_date`, `est_minutes`, `priority_tag`, `status`, `created_at` table.
- `Progress/Course-Cursor.md`: `course`, `last_completed_topic`, `last_completed_blockType`, `date` table.
- `Progress/Schedule-YYYY-MM-DD.md`: `start_time`, `duration_min`, `ref_type`, `ref_label` table.
- `Progress/Time-Log.md`: append-oriented `date`, `ref_type`, `ref_label`, `course`, `topic`, `blockType`, `started_at`, `stopped_at`, `minutes` table.
- `Progress/Sessions/<uuid>.json`: current provider, mode, model, effort, course, provider continuation IDs, timestamps, messages, attachments, and proposals.
- `Progress/Sessions/<uuid>/attachments/`: session attachment payloads.
- `Boards/Syllabus-Checklist.md`: existing front matter, preamble, section headings, per-section headers, and syllabus rows.
- Existing course/block-library files consumed by the TypeScript parsers, including the special IOQM and ZCO sources.

Free-text Markdown cells continue replacing `|` with `❘` and newlines with spaces. `-` continues representing a missing nullable time-log field. Date-only values remain `YYYY-MM-DD`, schedule times remain `HH:mm`, and persisted instants remain ISO 8601 strings.

### 3.3 Behavior that must remain exact

- Homework urgency ordering, overdue handling, and priority tie-breaking.
- Schedule replacement by identical start time and stable ascending time ordering.
- Cursor validation against a real `(course, topic, blockType)` block before advancement.
- Topic-less courses and end-of-course behavior.
- Syllabus exact-match preference and single-unambiguous-prefix fallback.
- Time logging rounds to the nearest minute with a minimum of one minute.
- Weekly date boundaries and adherence states.
- One in-flight provider turn per session.
- Provider-specific continuation identifiers and output parsing.
- Attachments remain vault/session relative and path-confined.

## 4. Target architecture

### 4.1 Repository layout

`apps/macos` contains one Swift package-backed implementation with these modules:

- `VerityDomain`: value types, validation, clocks, dates, identifiers, scoring, adherence, statistics, and errors.
- `VerityVault`: Markdown parsing/rendering, coordinated filesystem access, repositories, vault discovery/scaffolding, file observation, snapshots, and compatibility checks.
- `VerityAI`: provider catalog, executable discovery, environment resolution, invocation construction, process supervision, output parsing, session orchestration, proposal extraction, and approval tokens.
- `VerityKit`: shared app state, timer service, commands, settings, update/login-item abstractions, logging, and dependency assembly.
- `VerityDesign`: Strip Board tokens and reusable native controls.
- `VERITY`: SwiftUI/AppKit application, scenes, feature views, menus, status item, onboarding, and settings.
- Dedicated Swift Testing targets for each non-UI module plus the deterministic integration/security harness. XCUITest remains an optional full-Xcode extension.

Domain, vault, and AI modules cannot import SwiftUI. Feature views call typed services, never filesystem or `Process` APIs directly.

### 4.2 State and concurrency

- UI and observable navigation state are `@MainActor`.
- Vault access is serialized through a `VaultStore` actor.
- Provider execution is serialized per session through an `AssistantSessionCoordinator` actor while allowing different sessions to run concurrently within a global limit.
- Timer ownership lives in one `StudyTimer` actor/service shared by all scenes.
- All long reads, writes, parsing, attachment work, and subprocess collection remain off the main actor.
- Cancellation propagates from views to tasks and provider processes.
- Every async state machine has explicit idle, loading/running, success, recoverable failure, and terminal failure states.

### 4.3 Filesystem safety

- Vault selection uses a native open panel and persists a security-scoped bookmark plus a display path.
- Stale bookmarks trigger a re-selection flow without deleting configuration.
- All vault-relative paths pass through a single resolver that rejects absolute paths, `..`, symlink escapes, NULs, and destinations outside the canonical vault root.
- Reads and writes use `NSFileCoordinator`; access occurs only inside the coordinator callback.
- Writes render to a sibling temporary file, synchronize, atomically replace the destination, and reparse the result.
- Before mutation, the repository compares a file fingerprint captured when the editor/proposal loaded. Changed files produce a conflict UI instead of last-writer-wins data loss.
- File watching invalidates caches and refreshes open views after external Obsidian edits.
- Parsing errors surface the file, section, and recovery action while keeping unaffected workspaces usable.

### 4.4 Native process execution

- The app is directly distributed with hardened runtime and is not App-Sandboxed because it must invoke user-installed CLI tools and allow those tools their normal authenticated configuration.
- Provider executables are resolved from explicitly checked standard locations plus the user's login-shell `PATH`; the resolved executable is displayed in Settings.
- `Process` receives an explicit executable URL, arguments, working directory, environment, closed standard input, bounded stdout/stderr collectors, timeout, cancellation, and termination escalation.
- No provider command is assembled through a shell string.
- Output limits are byte-based and produce a clear recoverable error.
- Termination captures exit code, signal reason, stdout diagnostics, stderr diagnostics, duration, and provider identifier without logging prompt or attachment content.

## 5. Native application experience

### 5.1 Main window

- A flat, full-width Strip Board preserves the six workspaces through the compact RACK/CHRONO/PENDING/ROSTER/TALLY/DISPATCH hardware tab rack; Command-1 through Command-6 provides native keyboard navigation.
- The board header contains VERITY/STUDY OPS identity, LED state, live timer, refresh, and clock/date instrumentation. Workspace actions stay on the board rather than in a generic floating toolbar.
- Window size, selected workspace, and non-sensitive presentation state restore across launches.
- Multiple duplicate main windows are not created accidentally; activating the app reveals and focuses the existing primary window.
- Closing the window keeps a running timer and optional menu-bar experience alive; Quit is explicit and handles active work safely.

### 5.2 Strip Board design system

- Preserve the dark board, cream paper, colored holder, engraved plate, status LED, stamp, and instrument-readout concepts.
- Implement semantic `Board`, `Paper`, `Ink`, `Etch`, `Success`, `Warning`, `Danger`, and course-accent tokens with increased-contrast variants.
- Use native system typography for controls and legibility; the stencil/monospaced display treatment is limited to branded headings and data readouts.
- Use SF Symbols by name for platform actions.
- Materials, shadows, motion, and sound are restrained and respect Reduce Motion, Reduce Transparency, Differentiate Without Color, and system accent/contrast settings.
- Components include strip row, strip holder, paper sheet, engraved plate, LED status, fault banner, empty state, loading state, keyboard hint, proposal card, timer readout, metric gauge, and command button styles.
- Every control has hover, pressed, focused, selected, disabled, loading, success, warning, and error behavior where applicable.

### 5.3 Application menus

- VERITY: About, Check for Updates, Settings, Services, Hide/Show, and Quit.
- File: Open/Change Vault, Reveal Vault in Finder, New Homework, New Schedule Slot, New DISPATCH Session, and Close Window.
- Edit: native Undo/Redo, Cut/Copy/Paste, Select All, Find, and spelling/substitution commands where text editing is active.
- Study: Start Selected, Stop and Log, Discard Timer, Advance Course Cursor, Mark Homework Complete, Today, Previous/Next Day, and Previous/Next Week.
- View: workspace navigation with Command-1 through Command-6, sidebar and toolbar controls, focus active item, and full screen.
- Window: standard minimize, zoom, bring-all-to-front, and primary-window behavior.
- Help: VERITY Help, Privacy and Assistant Safety, Open Logs, Report an Issue, and Release Notes.
- Commands use focused values so availability and titles follow the active workspace and selection.

### 5.4 Menu-bar cockpit

The `MenuBarExtra` uses native `.menu` semantics so it dismisses after commands and never strands a window-style popover. It remains available while the app runs and contains:

- Active target, elapsed time, and Stop and Log / Discard controls.
- Next schedule item and time-until-start.
- Most urgent open homework item.
- Quick Start for the next schedule item or selected recent target.
- Quick Add Homework using a compact native sheet/popover flow.
- Open VERITY, Check for Updates, Settings, launch-at-login state, and Quit.
- A monochrome template symbol; optional elapsed-time text is a user preference.

The cockpit derives from the same stores and timer actor as the main window; it never polls a localhost API or mirrors renderer state.

### 5.5 Feature requirements

#### Rack

- Day navigation, Today action, current-time marker, adherence state, selection, add/edit/delete, course/homework/fixed composition, manual browse, validation, and keyboard flow.
- Detect schedule collisions and show them before save without silently changing current compatible file semantics.

#### Chrono

- Bind from today's schedule, next course block, or homework; start, stop/log, retry failed logging, discard with confirmation, advance cursor, and complete homework.
- Persist start instant and immutable target snapshot before showing the timer as running.
- Prevent a second timer, negative elapsed time, duplicate time-log insertion, and accidental quit data loss.

#### Pending

- Current quick-add syntax remains accepted alongside a native form.
- Add, edit, priority selection, completion, deletion confirmation, urgency explanation, and keyboard selection.
- Completed items remain visible in a clearly separated state unless filtered.

#### Roster

- Course selection, ordered block breakdown, next-block marker, cursor advancement, syllabus status cycling, status legend, and evidence display.
- Ambiguous syllabus matches never write.

#### Tally

- Week navigation, course/homework totals, completion percentages, time totals, empty weeks, and accessible chart alternatives.
- Calculations use deterministic calendar/time-zone dependencies and are unit tested around week/year and daylight-saving boundaries.

#### DISPATCH

- Provider catalog, executable and authentication status, guided install/login, model/effort selection, Ask/Research modes, required course selection, session creation/list/open/delete, conversation continuation, attachments, sending, cancellation, and errors.
- Render user and assistant messages natively with selectable text and accessible proposal cards.
- Extract only valid fenced JSON proposal arrays; normal prose and malformed blocks remain ordinary message content with an explanation.
- Review shows relative path, old/new content, semantic or line diff, conflict status, and risk warnings.
- Apply One and Apply All require explicit action. Apply All preflights every destination and is all-or-nothing.
- Applied proposals are durably marked with content digest, timestamp, and resulting file fingerprint so double application is impossible.

### 5.6 Onboarding and settings

- Onboarding explains local-first storage, lets the user choose an existing vault or create a scaffold, validates it without mutation, previews compatibility issues, then persists access.
- Existing Electron configuration can suggest the former vault location but never auto-select it without confirmation.
- Settings sections: General, Vault, Appearance, Study, Menu Bar, Assistant Providers, Updates, Privacy, and Advanced Diagnostics.
- Destructive actions state exactly what is removed and never delete a vault without a separate confirmation containing its full path.

## 6. Security and privacy design

- No telemetry, analytics, hosted account, or VERITY cloud backend.
- Unified logging defaults to metadata only and redacts vault paths, prompts, message bodies, attachments, provider output, and file contents.
- A diagnostic export is user-initiated, previews included files, and redacts sensitive values.
- Attachment names and payload sizes are validated; oversized files fail before base64 or subprocess work.
- Symlink, traversal, stale-review, TOCTOU, malformed JSON, command-injection, output-flood, timeout, cancellation, concurrent-turn, and concurrent-write cases have dedicated tests.
- Claude denies direct write/edit/shell tools; Codex runs with a read-only sandbox; Antigravity receives no vault directory grant. These restrictions are tested against exact argument arrays.
- Only `VaultProposalApplier` can perform assistant-originated writes. The type requires a short-lived approval token created by the review UI for exact proposal digests.
- Secrets and provider credentials stay in provider-owned storage; VERITY never copies them into the vault or logs.

## 7. Updates, lifecycle, and distribution

- Use Sparkle 2 through Swift Package Manager with an EdDSA-signed appcast hosted alongside GitHub Releases.
- Support automatic background checking, manual Check for Updates, download progress, install-and-relaunch, Later, beta/stable channels, and visible error recovery.
- Use `SMAppService.mainApp` for launch at login and show the system authorization state.
- Use a single-instance primary-window policy and native activation/reopen behavior.
- Quit with an active timer presents Stop and Log, Keep Running in Menu Bar, Discard, and Cancel as context allows.
- The zero-cost build uses an ad-hoc signature, strict nested signature verification, DMG/ZIP SHA-256 manifests, and a Keychain-backed Sparkle EdDSA signature. Developer ID hardened runtime, notarization, and stapling are enabled only when paid Apple credentials are explicitly supplied.
- DMG contains VERITY.app, Applications link, and the standalone uninstaller. Update ZIP/appcast artifacts are generated from the same signed app.
- The uninstaller unregisters launch-at-login, removes app support/preferences/caches/logs when chosen, preserves or explicitly deletes the selected vault, and never removes provider tools.

## 8. Testing strategy

### 8.1 Unit tests — Swift Testing

- Every domain validator and enum decoding path.
- Markdown cell sanitation, table parsing, section extraction, embedded fields, rendering, and round trips.
- Homework scoring, cursor progression, schedule replacement/sorting, adherence, rollups, stats, and date boundaries.
- Provider invocation arrays and Claude/Codex/Antigravity output parsers using captured fixtures.
- Proposal extraction, content hashing, approval-token expiry, stale-review rejection, and apply state.
- Timer persistence, elapsed calculation, minimum-minute rounding, retry, discard, and duplicate-log prevention with an injected clock.

### 8.2 Golden compatibility tests

- Copy representative v1.1.5 vault fixtures into temporary directories.
- Parse them with TypeScript and Swift compatibility harnesses and compare normalized domain JSON.
- Apply the same mutation in TypeScript and Swift copies, then compare semantic Markdown tables and preserved front matter/preamble.
- Confirm Native open/close performs zero byte changes.
- Confirm Electron can reopen every Swift-mutated fixture.
- Keep malformed, partial, empty, legacy, unusual-Unicode, embedded-pipe, and large-vault fixtures.

### 8.3 Repository and integration tests

- Atomic replacement, coordinated read/write, simulated external edit, conflict detection, symlink escape rejection, permissions failure, disk-full/write failure, and read-back rollback behavior.
- Session persistence and attachments across restart.
- Fake provider executables for success, non-zero exit, malformed output, stderr-only failure, timeout, cancellation, flood, and concurrent sends.
- Approval-only enforcement tests must prove no other AI path can obtain a write-capable repository interface.

### 8.4 UI and accessibility tests — XCTest/XCUIAutomation

- First launch, choose/create vault, resume suggested vault, invalid vault, and lost-access recovery.
- Critical path for all six workspaces.
- Application menu commands, contextual enablement, keyboard shortcuts, focus order, default buttons, cancellation, and undo where supported.
- Menu-bar timer, next item, quick homework, main-window reopen, and launch-at-login status.
- DISPATCH provider setup, session flow, attachment, proposal diff, Apply One, atomic Apply All, stale proposal, and error recovery using fake providers.
- VoiceOver labels/values/actions, keyboard-only completion, reduced motion, increased contrast, and large accessibility text where macOS permits.

### 8.5 Performance and endurance

- Cold launch to usable shell, vault parse time, view switching, schedule load, stats calculation, large session rendering, and proposal diff performance have measured budgets.
- No main-thread filesystem or subprocess I/O, verified with Instruments/signposts.
- Eight-hour timer run, repeated window close/reopen, sleep/wake, time-zone change, midnight rollover, and 100 provider-session operations.
- Memory growth and orphan-process checks after cancellations and repeated provider turns.

### 8.6 Packaging and release validation

- Clean build from a fresh checkout with locked dependencies.
- Unit/integration/UI suites and code coverage report.
- Archive inspection proves no Electron, Chromium, Node server, React/web assets, localhost listener, debug entitlement, personal path, or secret is shipped.
- Verify `codesign --verify --deep --strict`, `spctl --assess`, notarization, staple, appcast signature, DMG contents, ZIP update, version, and clean-machine install.
- Test upgrade from latest Electron release, Native beta update, rollback using a vault backup, uninstall while keeping data, uninstall deleting data, and reinstall onboarding.

## 9. Delivery phases and gates

### Phase 0 — evidence and specification

Deliver this specification, a parity inventory, native architecture decision record, fixture manifest, and risk register. Gate: every current route/store/view/provider behavior is assigned a native owner and test.

### Phase 1 — native foundation

Deliver compilable modules, app lifecycle, dependency assembly, logging, design tokens, navigation shell, menus, settings shell, and menu-bar shell. Gate: native app launches without web technology and the core package test suite passes.

### Phase 2 — vault engine

Deliver models, parser/renderer parity, safe path resolver, coordinated atomic access, repositories, onboarding, bookmark/config persistence, scaffolding, watching, and compatibility harness. Gate: golden fixtures and no-op byte-stability pass.

### Phase 3 — study operations

Deliver Rack, Chrono, Pending, Roster, Tally, shared timer, commands, notifications, Dock badge, and menu-bar cockpit. Gate: study parity, recovery, keyboard, accessibility, and endurance suites pass.

### Phase 4 — DISPATCH

Deliver provider discovery/setup/login, safe subprocess engine, sessions, attachments, message UI, proposal extraction/diff, approval tokens, atomic application, cancellation, and provider fixtures. Gate: full parity plus security abuse suite passes.

### Phase 5 — product finish

Deliver final Strip Board polish, animations, localization-ready strings, help/privacy/release notes, diagnostics, updater, login item, crash-safe lifecycle, and performance tuning. Gate: design/accessibility/performance acceptance passes.

### Phase 6 — beta and replacement

Ship a separately identified Native beta, run it against copied and live vaults, collect explicit opt-in diagnostics only when the user exports them, close parity defects, and rehearse release/update/uninstall. Replace Electron only after all gates pass and retain a tested rollback build for one release cycle.

## 10. Definition of done

The transition is done only when all of the following are true:

- The product is visibly and technically native SwiftUI/AppKit with no web rendering/runtime.
- All six workspaces and both menu surfaces meet parity and acceptance criteria.
- Existing vaults remain compatible and byte-stable when unmodified.
- DISPATCH cannot write without exact user-reviewed approval.
- Automated unit, golden, integration, security, UI, accessibility, performance, endurance, and packaging suites pass.
- The app is archived, signed, notarized, stapled, packaged, update-tested, uninstall-tested, and documented.
- The release audit finds no secrets, personal paths, debug capability, orphan process, localhost listener, or forbidden web runtime.
- The Electron replacement decision is backed by a checked parity matrix and a successful rollback rehearsal.

## 11. External prerequisites

- Full Xcode must be installed and selected for app archive, UI automation, signing, and notarization. Command Line Tools alone are sufficient only for package-level development and tests.
- Developer ID Application credentials, notarization credentials, and a Sparkle EdDSA key are required for public release artifacts.
- Provider CLIs and authenticated test accounts are required for final live-provider smoke tests; deterministic fake-provider tests remain mandatory regardless.
