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
  
  // Create temporary directory for DMG contents
  fs.mkdirSync(tmpPath, { recursive: true });
  
  // Copy app to temp directory
  console.log('Copying app to temporary directory...');
  execSync(`cp -r "${appPath}" "${path.join(tmpPath, 'VERITY.app')}"`);
  
  // Create symlink to Applications
  console.log('Creating Applications symlink...');
  execSync(`ln -s /Applications "${path.join(tmpPath, 'Applications')}"`);
  
  // Remove old DMG if it exists
  if (fs.existsSync(dmgPath)) {
    fs.rmSync(dmgPath, { force: true });
  }
  
  // Create DMG using hdiutil
  console.log('Building DMG image...');
  execSync(`hdiutil create -volname "VERITY" -srcfolder "${tmpPath}" -ov -format UDZO "${dmgPath}"`, {
    stdio: 'pipe'
  });
  
  // Cleanup
  console.log('Cleaning up...');
  fs.rmSync(tmpPath, { recursive: true, force: true });
  
  console.log(`✓ DMG created: ${dmgPath}`);
  
  // Verify DMG
  console.log('Verifying DMG...');
  execSync(`hdiutil verify "${dmgPath}"`, {
    stdio: 'pipe'
  });
  console.log('✓ DMG verification passed');
  
} catch (error) {
  console.error('Error creating DMG:', error.message);
  // Cleanup on error
  if (fs.existsSync(tmpPath)) {
    fs.rmSync(tmpPath, { recursive: true, force: true });
  }
  process.exit(1);
}
