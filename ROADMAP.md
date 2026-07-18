# VERITY Roadmap

VERITY Native 2.0.2 is the recommended product: a shipped SwiftUI/AppKit macOS app with
the six study workspaces, native lifecycle and update support, compatibility-tested
Markdown storage, and an approval-gated DISPATCH assistant. This roadmap is a
post-release plan, not a list of unfinished native-migration work.

## 1. Complete the real-world release validation

Before adding broad product surface, finish the remaining environment-dependent checks
recorded in [the Native release audit](docs/NATIVE_RELEASE_AUDIT.md):

- Rehearse clean download, first launch, update, and uninstall on a second Mac.
- Exercise Full Keyboard Access, VoiceOver, increased contrast, Reduce Motion, and Reduce
  Transparency.
- Verify narrow-window, long-text, Unicode, loading, empty, and failure states.
- Verify launch-at-login registration, removal, and system-denial handling.
- Rehearse sleep/wake, wall-clock changes, and multi-display movement with an active timer.

Treat any failure as a focused reliability fix with a regression test or repeatable manual
check. Do not reopen the completed Electron-to-Native transition merely to add visual polish.

## 2. Professional-grade DISPATCH research and Course Forge

DISPATCH already has a strong safety boundary: providers are read-only and vault changes
remain explicit, reviewed proposals. Its next step is evidence quality, research orchestration,
and a tailored course-design system—not broader write authority. The detailed delivery contract is
[DISPATCH professional research plan](docs/DISPATCH_PROFESSIONAL_RESEARCH_PLAN.md).

The outcome is a research run that can:

- state its scope and source policy before collecting material;
- preserve a durable, inspectable source ledger and claim-level citations;
- distinguish verified facts, corroborated conclusions, and open questions;
- run long work in resumable, cancellable stages with clear progress and limits; and
- turn courses, syllabi, grades, timelines, available study time, resource recommendations,
  and custom instructions into an evidence-backed, feasible Course Blueprint; and
- produce a reviewable proposal whose claims and sources survive alongside the proposed
  Markdown change.

## 3. Generic curriculum and vault model

The current block-library parser, scaffolder, theme accents, syllabus path, fixtures, and
research prompt still contain Boards/Competition/IOQM/ZCO-specific assumptions. Replace
those with a user-defined curriculum model while retaining read compatibility with existing
VERITY and Obsidian vaults.

Deliver this as a migration-safe capability:

- Discover course libraries and syllabus files from a versioned vault manifest instead of
  fixed filenames and headings.
- Let a user create and edit course groups, courses, topics, block types, and block fields.
- Scaffold a neutral starter vault; never overwrite or convert an existing vault merely on
  open.
- Let DISPATCH receive the selected course's actual schema and source files rather than a
  hard-coded research instruction.
- Add golden fixtures for legacy personal vaults and generic user-created vaults, plus
  no-op, mutation, and malformed-schema compatibility tests.

This is the foundation of Course Forge, not a separate cosmetic project: it makes VERITY useful
without asking a new student to fit the original curriculum.

## 4. Multi-vault profiles and controlled customization

Once the vault has a generic manifest, add profiles for separate students or test vaults.
Keep the selected vault explicit, security-scoped, and isolated. Then consider configurable
appearance, optional prompt presets, and user-owned study defaults. All customization must
remain local-first and must never weaken vault-path confinement or proposal approval.

## Explicitly deferred

- Cross-platform ports: Native is intentionally macOS-first; Windows/Linux is a separate
  product and support commitment, not a packaging flag.
- Apple Developer ID signing and notarization: enable only when paid credentials are supplied;
  keep the current zero-cost distribution profile honest until then.
- Cloud accounts, telemetry, analytics, or a hosted VERITY backend: none are planned.
