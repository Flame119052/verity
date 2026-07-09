# VERITY

VERITY is a private study planner for Mac.

It helps you plan your day, track homework, log study time, follow course progress, and build better study material with an optional AI assistant. Your study data stays in a folder on your own computer, stored as normal Markdown files that you can also open in Obsidian.

There are no accounts, no cloud dashboard, and no subscription service built into VERITY.

## What You Can Do

- See your study day in one place.
- Plan course blocks, homework, and fixed-time commitments.
- Start and stop study timers.
- Mark homework done.
- Track syllabus and course progress.
- Keep a history of study time.
- Use an optional AI assistant to research or draft course material.
- Keep everything in a plain local folder instead of a locked app database.

## Your Data

VERITY stores study data in an Obsidian vault folder that you choose during setup.

That folder contains normal Markdown files for things like courses, homework, schedules, time logs, and assistant sessions. You can back it up, sync it with your own tools, open it in Obsidian, or move it later.

VERITY also keeps a small app settings file on your Mac so it remembers which vault to open.

## Privacy And Security

VERITY is local-first.

- Your study files stay on your Mac.
- VERITY does not require an account.
- VERITY does not upload your vault to any VERITY service.
- VERITY does not include analytics or telemetry.
- The AI assistant is optional.

### What Stays Local

Your vault stays in the folder you choose. VERITY reads and writes normal files in that folder so it can show your schedule, homework, courses, time logs, and assistant history.

The app also stores a small local setting on your Mac that points to the selected vault. This is how VERITY remembers where your study data is after you reopen the app.

### What Can Leave Your Mac

Nothing is sent to an AI provider unless you use the AI assistant.

If you do use the assistant, the message you type, any selected context needed for that request, and any attachment you include may be sent to the AI provider you chose, such as Claude, Codex, or Antigravity. Those providers are separate services with their own accounts and policies.

VERITY itself does not run a hosted cloud account for your study data.

### How Assistant Edits Work

The assistant is designed around a review step.

1. You ask the assistant for help.
2. The assistant replies in the chat.
3. If it wants to change your vault, it must show proposed file changes first.
4. You review the proposal inside VERITY.
5. VERITY writes the change only when you press Apply.

The assistant is not meant to silently edit your study files in the background.

### Tool Access

VERITY uses command-line AI tools only when you choose to set them up.

The app limits those tools for this workflow:

- Claude is given read and research tools, while direct file-writing tools are blocked.
- Codex is run in a read-only sandbox for assistant turns.
- Antigravity is not given direct access to your vault folder.
- Proposed file changes still have to pass through VERITY's own Apply button.

This keeps the assistant useful for research and drafting while keeping final file changes under your control.

### Installing Provider Tools

If you choose to use Claude, Codex, or Antigravity, VERITY may help you install or open the setup flow for that tool.

Those tools are separate from VERITY. Removing VERITY does not remove your Claude, Codex, or Antigravity installation, because you may use those tools elsewhere.

## Installing On Mac

1. Go to the [Releases](../../releases) page.
2. Download the newest file ending in `.dmg`.
3. Open the downloaded file.
4. Drag `VERITY.app` into Applications.
5. Open VERITY from Applications.

The first time you open the app, macOS may say the developer cannot be verified. This happens because VERITY is not notarized through Apple's paid developer program yet.

To open it:

1. Right-click `VERITY.app`.
2. Choose Open.
3. Confirm Open when macOS asks again.

You should only need to do this once.

## First Setup

When VERITY opens for the first time, it will ask where to keep your study data.

You can either:

- choose an existing Obsidian vault, or
- let VERITY create a new study vault for you.

If you previously removed the app but kept your data, setup may offer to resume from the preserved vault.

## The Menu Bar Icon

VERITY also runs from the Mac menu bar.

Use the menu bar icon to:

- open VERITY,
- check update status,
- quit the app.

You do not need to keep the main window open all the time.

## Updates

VERITY checks GitHub Releases for newer versions.

When an update is available, the app can download it and apply it after you quit and reopen VERITY.

## Uninstalling

The installer DMG includes a separate file named `Uninstall VERITY.command`.

Use that uninstaller instead of deleting the app by hand. It can remove the app, stop old background processes, remove old launch/login entries, and clear VERITY's app settings.

You can choose:

- Keep Study Data: removes VERITY and its app settings, but keeps your study vault. Reinstalling VERITY opens onboarding and offers to resume from the saved vault when available.
- Delete Everything: removes VERITY, its app settings, and the vault VERITY was configured to use.

VERITY does not uninstall Claude, Codex, Antigravity, or other AI tools you may use outside the app.

If you are updating from an older VERITY build, the latest app may ask you to confirm your vault once during onboarding. This is intentional: it clears older setup residue while leaving your study files in place.

## AI Assistant

The assistant is for study help, course research, and drafting changes to your local course files.

It can work with supported command-line AI tools such as Claude, Codex, or Antigravity if you choose to set them up. VERITY will guide you through setup inside the app.

The important rule is simple: the assistant can propose changes, but you stay in control of what gets written.

## Who This Is For

VERITY is designed for students who want a serious local study command center without moving their planning into another online service.

It is especially useful if you already like Obsidian, Markdown, or keeping your schoolwork in files you can inspect and own.

## Current Status

VERITY is an early Mac app. It is usable, but still improving quickly.

For the newest installer, use the latest release on the [Releases](../../releases) page.
