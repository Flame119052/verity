# VERITY Electron legacy policy

VERITY 1.x is a sunset compatibility edition. VERITY Native 2 is the recommended and actively developed macOS application.

## What remains available

- Every previously published 1.x GitHub release and its installer assets remain downloadable.
- Version 1.1.6 is the final Electron compatibility build.
- Existing Markdown vaults remain readable by both 1.1.6 and Native 2 without conversion.
- The legacy source stays in `apps/desktop`, `apps/web`, and `apps/server` so compatibility can be reproduced and parity-tested.

## What sunset means

- No new study features or UI redesigns will be developed for Electron.
- Security-critical compatibility fixes may be accepted, but Native is the default destination for fixes and releases.
- The legacy UI and menu-bar menu recommend VERITY Native and link to the latest Native release.
- Electron's updater channel ends at 1.1.6. The final channel metadata remains published so 1.1.5 installations can reach the retirement build without being offered an incompatible Native archive.

## Rollback boundary

Native stores its configuration separately and does not delete or replace Electron. To roll back, quit Native and open 1.1.6 against the same vault. Do not actively edit the same file from both applications at once.
