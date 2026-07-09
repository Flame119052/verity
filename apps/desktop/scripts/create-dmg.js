#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const desktopDir = path.join(__dirname, '..');
const appPath = path.join(desktopDir, 'dist-electron/VERITY-darwin-arm64/VERITY.app');
const dmgPath = path.join(desktopDir, 'dist-electron/VERITY.dmg');
const tmpPath = path.join(desktopDir, '.dmg-tmp');

if (!fs.existsSync(appPath)) {
  console.error(`ERROR: App not found at ${appPath}`);
  console.error('Run: npm run dist');
  process.exit(1);
}

try {
  console.log('Creating DMG...');

  // ── Step 1: Strip quarantine from the app before packaging.
  // When the .app was created during `npm run dist` on this machine it may have
  // inherited a quarantine attribute. Stripping it here ensures the DMG doesn't
  // carry quarantine metadata from the build machine into the recipient's system.
  console.log('Stripping quarantine attribute from app...');
  execSync(`xattr -cr "${appPath}"`, { stdio: 'pipe' });

  // ── Step 2: Ad-hoc re-sign the entire bundle (deep + force).
  // electron-builder with `identity: "-"` already signs during the dist step,
  // but if this script is run manually after editing the app directory the
  // signature must be refreshed. Ad-hoc signing ("-") creates a self-consistent
  // signature without requiring an Apple Developer certificate.
  // Recipients will see "unidentified developer" (right-click → Open to bypass)
  // instead of the unrecoverable "damaged app" error caused by a broken/missing
  // signature.
  console.log('Ad-hoc signing app bundle (--force --deep --sign "-")...');
  execSync(`codesign --force --deep --sign "-" "${appPath}"`, { stdio: 'pipe' });

  // Verify the signature is valid before packaging
  console.log('Verifying app signature...');
  execSync(`codesign --verify --verbose=1 "${appPath}"`, { stdio: 'pipe' });
  console.log('✓ App signature valid');

  // ── Step 3: Create temporary staging directory for DMG contents
  fs.mkdirSync(tmpPath, { recursive: true });

  // Copy signed app to temp directory
  console.log('Copying signed app to staging directory...');
  execSync(`cp -r "${appPath}" "${path.join(tmpPath, 'VERITY.app')}"`);

  // Create symlink to Applications (standard drag-to-install UX)
  console.log('Creating Applications symlink...');
  execSync(`ln -s /Applications "${path.join(tmpPath, 'Applications')}"`);

  // Remove old DMG if it exists
  if (fs.existsSync(dmgPath)) {
    fs.rmSync(dmgPath, { force: true });
  }

  // ── Step 4: Build the DMG image
  console.log('Building DMG image...');
  execSync(`hdiutil create -volname "VERITY" -srcfolder "${tmpPath}" -ov -format UDZO "${dmgPath}"`, {
    stdio: 'pipe'
  });

  // Cleanup staging directory
  console.log('Cleaning up staging directory...');
  fs.rmSync(tmpPath, { recursive: true, force: true });

  console.log(`✓ DMG created: ${dmgPath}`);

  // ── Step 5: Verify the DMG itself
  console.log('Verifying DMG integrity...');
  execSync(`hdiutil verify "${dmgPath}"`, { stdio: 'pipe' });
  console.log('✓ DMG verification passed');

  console.log('');
  console.log('Distribution note:');
  console.log('  This DMG is ad-hoc signed (no Apple Developer certificate).');
  console.log('  Recipients will see an "unidentified developer" prompt on first launch.');
  console.log('  To open: right-click VERITY.app → Open, then click Open in the dialog.');
  console.log('  Or recipients can run: xattr -d com.apple.quarantine VERITY.dmg');
  console.log('  They will NOT see the hard "damaged app" error.');

} catch (error) {
  console.error('Error creating DMG:', error.message);
  // Cleanup on error
  if (fs.existsSync(tmpPath)) {
    fs.rmSync(tmpPath, { recursive: true, force: true });
  }
  process.exit(1);
}
