# VERITY zero-cost macOS distribution

VERITY supports an honest no-subscription release profile. It provides the same native application and
Sparkle update integrity as the Developer ID profile, but it cannot claim Apple notarization.

## What is free and enabled

- Xcode, Swift, SwiftUI, AppKit, Swift Testing, and Instruments are free Apple developer tools.
- Every local build is ad-hoc code signed and its nested Sparkle helpers are verified with `codesign`.
- Release DMGs and update ZIPs are listed in `dist/SHA256SUMS` so downloads can be independently checked.
- Sparkle update archives are signed with VERITY's Ed25519 key. The private key remains in the login
  Keychain under account `app.verity.native`; only the public key is embedded in the app.
- The appcast is served over HTTPS from the repository. Sparkle's signature verifies that an archive came
  from the holder of VERITY's private update key.

## The Apple-imposed boundary

Apple reserves Developer ID certificates and notarization for the paid Apple Developer Program. An ad-hoc
signature and a Sparkle EdDSA signature do not turn into a Developer ID signature and must never be described
as notarized. On first launch after a web download, Gatekeeper may require the user to Control-click VERITY,
choose **Open**, then confirm **Open**, or use **System Settings → Privacy & Security → Open Anyway**. VERITY
does not ask users to disable Gatekeeper or strip quarantine attributes.

## Release procedure

```bash
apps/macos/scripts/release-gate.sh

SPARKLE_DOWNLOAD_URL_PREFIX="https://github.com/Flame119052/verity/releases/download/v2.0.2/" \
SPARKLE_KEY_ACCOUNT="app.verity.native" \
apps/macos/scripts/create-update-artifacts.sh
```

Copy the generated signed `appcast.xml` to the repository root, upload the exact ZIP and DMG produced by the
gate to the matching GitHub release, and publish both alongside `SHA256SUMS`. Before publishing, verify the
repository artifacts with the release gate and strict signing check:

```bash
apps/macos/scripts/release-gate.sh
codesign --verify --deep --strict apps/macos/dist/VERITY.app
```

After downloading `VERITY-Native.dmg`, `VERITY-2.0.2.zip`, and `SHA256SUMS` into one folder from the
release page, users can independently run `shasum -a 256 -c SHA256SUMS` there.

If a paid Developer ID identity becomes available later, the same scripts accept `SIGN_IDENTITY` and the DMG
script accepts `NOTARY_KEYCHAIN_PROFILE`; the free profile does not depend on either.
