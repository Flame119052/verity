# VERITY Native release audit

Every box is a release gate, not an aspiration. Record evidence beside each item for a public build.

## Product and compatibility

- [x] All six workspaces pass the parity walkthrough against a copied production vault. Evidence: final packaged-app accessibility and visual walkthrough of RACK, CHRONO, PENDING, ROSTER, TALLY, and DISPATCH, 2026-07-16.
- [x] Native open-and-close produces zero vault byte changes. Evidence: `verity-native-checks` byte snapshot check, 2026-07-16.
- [x] Native mutations reopen correctly in VERITY 1.x and Obsidian-compatible Markdown semantics. Evidence: bidirectional Swift/TypeScript mutation and reopen matrix, 2026-07-16.
- [x] New-vault scaffolding, manual selection, bookmark round trip, and clean-onboarding reset pass. Evidence: native harness plus packaged-app walkthrough; test fixture configuration removed after QA, 2026-07-16.
- [x] Active timer restart, log retry, discard, course completion, and homework completion pass. Evidence: native harness recovery/prepare/commit/discard/completion checks, 2026-07-16.
- [x] External edits invalidate reviewed fingerprints and stale editor/proposal writes are rejected. Evidence: coordinated fingerprint and reviewed-proposal checks, 2026-07-16.

## DISPATCH

- [x] Claude, Codex, and Antigravity status surfaces, automatic install commands, login/device-code commands, malformed-installer rejection, and provider-specific invocation paths are exercised with deterministic fixtures. Clean third-party accounts are deliberately not a release dependency. Evidence: provider unit/fake-install/subprocess checks plus packaged-app walkthrough, 2026-07-17.
- [x] Provider argument arrays match the read-only security contract. Evidence: Claude/Codex/Antigravity invocation checks, 2026-07-16.
- [x] Success, non-zero exit, malformed output, timeout, cancellation, and output flooding pass. Evidence: deterministic fake-process checks, 2026-07-16.
- [x] Attachments pass size, filename, binary, and provider-specific handling checks. Evidence: native harness, 2026-07-16.
- [x] Current/proposed review, stale review, token expiry, Apply One, and transactional Apply All pass. Evidence: native harness 60/60, 2026-07-16.
- [x] No source path outside `VaultProposalApplier` grants assistant-originated writes. Evidence: source boundary audit and approval-token harness, 2026-07-16.

## macOS quality

- [x] File, Edit, View, Study, Window, and Help menus are complete and context-sensitive. Evidence: final packaged-app menu accessibility walkthrough, 2026-07-16.
- [x] Menu-bar timer, Quick Start, urgent homework, open/settings, update, launch-at-login, and quit commands are wired to shared app state. A directly owned AppKit `NSStatusItem`/`NSMenu` rebuilds on open and dismisses synchronously after commands; the unstable SwiftUI status scene is no longer used. Evidence: source/lifecycle audit, native compilation, and packaged build, 2026-07-17.
- [x] Keyboard workspace switching, app menu commands, accessibility labels, and menu order pass in the packaged app. Evidence: accessibility-tree walkthrough and Command-1 navigation, 2026-07-16.
- [x] The six-section Settings control center, provider setup states, update controls, About details, application-menu uninstall command, and destructive confirmation pass visual and accessibility-tree inspection. Evidence: packaged 2.0.1 walkthrough, 2026-07-17.
- [ ] A second-Mac manual rehearsal of Full Keyboard Access, increased contrast, Reduce Motion, Reduce Transparency, and spoken VoiceOver remains a post-publish environment check.
- [ ] Light/dark policy, Dynamic Type equivalents, narrow window, long text, Unicode, empty, loading, and fault states pass.
- [ ] Launch at login registers, unregisters, and reports system denial correctly.
- [x] Window close/reopen and app reopen preserve shared state and recreate the board correctly. Evidence: packaged-app lifecycle walkthrough, 2026-07-16.
- [ ] Sleep/wake, wall-clock discontinuity, and multi-display movement remain second-Mac manual checks.

## Automated and endurance

- [x] Full Swift Testing suite passes under Xcode 27.0. Evidence: `apps/macos/scripts/test.sh`, 20/20 discovered tests including isolated fake CLI installers, 2026-07-17.
- [x] `swift run --package-path apps/macos verity-native-checks` passes. Evidence: 60/60, 2026-07-16.
- [x] `apps/macos/scripts/release-gate.sh` passes. Evidence: ad-hoc app, embedded and standalone uninstallers, DMG, ZIP, nested signatures, and forbidden-runtime scan, 2026-07-17.
- [x] GitHub Actions native and legacy-baseline jobs pass. Evidence: workflow run 29513990353 on release commit `b9f3775`, 2026-07-16.
- [x] Representative golden vaults pass Swift/TypeScript normalized comparison. Evidence: `compare-legacy-parity.sh`, 2026-07-16.
- [x] 5,000-row, large-session, 24-hour timer, repeated external-edit, and provider-flood tests pass. Evidence: native harness 60/60, 2026-07-16.
- [x] The full six-workspace walkthrough remains stable at approximately 99 MB RSS; no VERITY-owned leak graph or orphan harness/provider process was observed. Apple's AppIntents daemon reported framework-owned XPC cycles under the restricted `leaks` attachment. Evidence: packaged-app endurance pass and process audit, 2026-07-16.

## Distribution

- [x] Version/build are 2.0.2/20002 and native release notes are final for the recommended zero-cost release profile.
- [x] Secrets/personal-path scan is clean. Evidence: native release gate, 2026-07-16.
- [x] Zero-cost ad-hoc app and nested Sparkle helpers pass strict code-sign verification. Developer ID hardened runtime is intentionally unavailable without paid membership.
- [x] Notarization and stapling are accurately excluded from the zero-cost profile; the release does not claim either without paid Developer Program membership.
- [x] Gatekeeper limitations and the documented Control-click/Open Anyway first-launch flow are explicit; the app never disables Gatekeeper or strips quarantine.
- [x] Sparkle HTTPS appcast and EdDSA archive signature validate against the Keychain-backed VERITY key. Evidence: `sign_update --verify`, 2026-07-16.
- [x] DMG layout, Applications link, checksum verification, embedded-helper signature, in-app removal confirmation, and removal documentation pass. Evidence: final release gate, packaged UI walkthrough, and `SHA256SUMS`, 2026-07-17.
- [x] The packaged app contains no Electron, Node, HTML, JavaScript, localhost server, or development payload. Evidence: `find`, `strings`, and `otool` release gates, 2026-07-16.

## Zero-cost boundary and toolchain state

- Xcode 27.0 is installed at `/Applications/Xcode-beta.app`; `apps/macos/scripts/test.sh` discovers it even when global `xcode-select` remains on Command Line Tools.
- The Swift Testing suite is migrated away from the Command Line Tools-only XCTest failure and passes 20/20 under full Xcode.
- Sparkle's private Ed25519 key is stored in the login Keychain under `app.verity.native`; the public key and repository HTTPS feed are embedded in the app. The final update ZIP signature validates.
- The keychain intentionally has no Developer ID identity and no notarization profile because Apple restricts both to paid membership. The repository therefore ships an explicit zero-cost profile instead of fabricating those claims.
- GitHub Actions passes on the release commit. A second-Mac clean-download rehearsal remains a post-publish environment check; local source, compatibility, package, cryptographic, CI, and live UI gates pass.
