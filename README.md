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

## Privacy

VERITY is local-first.

- Your study files stay on your Mac.
- VERITY does not require an account.
- VERITY does not upload your vault to its own server.
- VERITY does not include analytics or telemetry.
- The AI assistant is optional.

If you use the AI assistant, the text you send to the selected AI provider may be sent to that provider so it can answer. The assistant cannot silently rewrite your vault. When it wants to change files, VERITY shows the proposed changes first and only writes them after you approve.

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
- quit the app,
- uninstall VERITY.

You do not need to keep the main window open all the time.

## Updates

VERITY checks GitHub Releases for newer versions.

When an update is available, the app can download it and apply it after you quit and reopen VERITY.

## Uninstalling

VERITY includes an uninstall option in the menu bar.

You can choose:

- Delete the app only and keep your study data.
- Delete everything, including the vault VERITY is configured to use.

If you keep your study data, reinstalling VERITY should still show onboarding so you can confirm whether to resume from the preserved vault.

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
