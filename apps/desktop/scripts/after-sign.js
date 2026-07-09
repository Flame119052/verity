// afterSign.js — electron-builder afterSign hook
//
// Called by electron-builder after packaging (even when code signing is
// skipped). Applies a deep ad-hoc codesign to the .app bundle so the app is
// coherently signed without an Apple Developer certificate.
//
// Why:
//   The bundled Electron binary carries its own Apple-issued signature covering
//   specific resource hashes. After electron-builder repackages it with a new
//   app.asar, the original signature becomes invalid. macOS Gatekeeper on
//   another machine reads this broken signature and shows the hard, unbypassable
//   "the app is damaged and can't be opened" error.
//
//   Ad-hoc signing (identity "-") replaces the broken signature with a fresh,
//   self-consistent one. Recipients will see "unidentified developer" instead
//   (right-click → Open to bypass) — a fully recoverable prompt.
//
// Pattern: same approach used by open-source macOS Electron apps distributed
// without Apple Developer accounts.

const { execSync } = require('child_process');
const path = require('path');
const fs = require('fs');

exports.default = async function afterSign(context) {
  // Only applies to macOS builds
  if (context.electronPlatformName !== 'darwin') {
    return;
  }

  const appName = context.packager.appInfo.productName + '.app';
  const appPath = path.join(context.appOutDir, appName);

  if (!fs.existsSync(appPath)) {
    console.warn(`[afterSign] App not found at ${appPath}, skipping ad-hoc sign`);
    return;
  }

  console.log(`[afterSign] Applying ad-hoc code signature to: ${appPath}`);

  try {
    // Strip any existing quarantine/extended attributes first
    execSync(`xattr -cr "${appPath}"`, { stdio: 'pipe' });

    // Deep ad-hoc sign: --force replaces any existing (broken) signature,
    // --deep recurses into all nested bundles (frameworks, helpers, etc.)
    execSync(`codesign --force --deep --sign "-" "${appPath}"`, {
      stdio: 'inherit'
    });

    // Verify the resulting signature is structurally valid
    execSync(`codesign --verify --verbose=1 "${appPath}"`, { stdio: 'pipe' });

    console.log('[afterSign] ✓ Ad-hoc signature applied and verified');
    console.log('[afterSign] Recipients: right-click VERITY.app → Open to bypass "unidentified developer" prompt');
  } catch (err) {
    console.error('[afterSign] Warning: ad-hoc signing failed:', err.message);
    console.error('[afterSign] The app may show "damaged" on other Macs.');
    console.error('[afterSign] Manual fix: codesign --force --deep --sign "-" VERITY.app');
  }
};
