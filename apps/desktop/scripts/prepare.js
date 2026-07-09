#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const desktopDir = path.join(__dirname, '..');
const serverSrcDir = path.join(__dirname, '../../server');
const webSrcDir = path.join(__dirname, '../../web');
const rootDir = path.join(__dirname, '../../../');

const serverDestDir = path.join(desktopDir, 'server');
// Nested under dist/ to match the relative path apps/server/src/index.ts
// resolves from its own compiled location (path.resolve(__dirname, '../../web/dist/...')),
// which is the same relative shape as the source-tree dev layout (apps/web/dist/
// sitting next to apps/server/dist/). Keeping this identical between dev and
// packaged builds avoids the two layouts silently diverging again.
const webDestDir = path.join(desktopDir, 'web', 'dist');

function removeDir(dir) {
  if (fs.existsSync(dir)) {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function copyDir(src, dest, exclude = []) {
  if (!fs.existsSync(src)) {
    console.warn(`Source not found: ${src}`);
    return;
  }

  fs.mkdirSync(dest, { recursive: true });

  const files = fs.readdirSync(src);
  files.forEach((file) => {
    if (exclude.includes(file)) return;

    const srcFile = path.join(src, file);
    const destFile = path.join(dest, file);
    const stat = fs.statSync(srcFile);

    if (stat.isDirectory()) {
      copyDir(srcFile, destFile, exclude);
    } else {
      fs.copyFileSync(srcFile, destFile);
    }
  });
}

async function main() {
  try {
    console.log('Staging server and web builds for Electron app...');

    // Clear old builds
    console.log('Clearing old staged builds...');
    removeDir(serverDestDir);
    removeDir(path.join(desktopDir, 'web'));

    // Verify builds exist
    const serverDistDir = path.join(serverSrcDir, 'dist');
    const webDistDir = path.join(webSrcDir, 'dist');

    if (!fs.existsSync(serverDistDir)) {
      console.error(`ERROR: Server build not found at ${serverDistDir}`);
      console.error('Run: npm run build');
      process.exit(1);
    }

    if (!fs.existsSync(webDistDir)) {
      console.error(`ERROR: Web build not found at ${webDistDir}`);
      console.error('Run: npm run build');
      process.exit(1);
    }

    // Copy server build (dist directory)
    console.log(`Copying server build from ${serverDistDir}...`);
    fs.mkdirSync(serverDestDir, { recursive: true });
    copyDir(serverDistDir, path.join(serverDestDir, 'dist'));

    // Copy server package.json so Node.js sees "type": "module" next to
    // dist/index.js at runtime. Without this, Node treats the ESM output as
    // CommonJS and throws ERR_REQUIRE_ESM. This file is added to asarUnpack
    // in the electron-builder config so it lands on the real filesystem
    // alongside the unpacked node_modules.
    const serverPkgSrc = path.join(serverSrcDir, 'package.json');
    const serverPkgDest = path.join(serverDestDir, 'package.json');
    if (fs.existsSync(serverPkgSrc)) {
      console.log('Copying server package.json...');
      fs.copyFileSync(serverPkgSrc, serverPkgDest);
    } else {
      console.warn('Warning: server package.json not found — ESM resolution may fail at runtime.');
    }

    // Note: server node_modules are no longer copied here because the server build
    // script uses esbuild to bundle all dependencies (express, dotenv, uuid) 
    // directly into dist/index.js. This avoids any issues with nested node_modules 
    // being excluded by electron-builder or failing to resolve inside the asar.

    // Copy web build
    console.log(`Copying web build from ${webDistDir}...`);
    copyDir(webDistDir, webDestDir);

    console.log('✓ Staging complete!');
    console.log(`Server: ${serverDestDir}`);
    console.log(`Web: ${webDestDir}`);
  } catch (error) {
    console.error('Error during staging:', error.message);
    process.exit(1);
  }
}

main();
