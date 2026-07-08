#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

const desktopDir = path.join(__dirname, '..');
const serverSrcDir = path.join(__dirname, '../../server');
const webSrcDir = path.join(__dirname, '../../web');
const rootDir = path.join(__dirname, '../../../');

const serverDestDir = path.join(desktopDir, 'server');
const webDestDir = path.join(desktopDir, 'web');

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
    removeDir(webDestDir);

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

    // Copy server node_modules (try local first, then root monorepo)
    console.log('Copying server node_modules...');
    let serverNodeModulesSrc = path.join(serverSrcDir, 'node_modules');

    // If not in server, try root monorepo node_modules
    if (!fs.existsSync(serverNodeModulesSrc)) {
      serverNodeModulesSrc = path.join(rootDir, 'node_modules');
    }

    if (fs.existsSync(serverNodeModulesSrc)) {
      const serverNodeModulesDest = path.join(serverDestDir, 'node_modules');
      // Only copy production dependencies: express, dotenv, uuid
      const prodDeps = ['express', 'dotenv', 'uuid'];
      fs.mkdirSync(serverNodeModulesDest, { recursive: true });

      prodDeps.forEach((dep) => {
        const depSrc = path.join(serverNodeModulesSrc, dep);
        if (fs.existsSync(depSrc)) {
          console.log(`  Copying ${dep}...`);
          copyDir(depSrc, path.join(serverNodeModulesDest, dep));
        }
      });

      // Also copy .bin if it exists
      const binSrc = path.join(serverNodeModulesSrc, '.bin');
      if (fs.existsSync(binSrc)) {
        copyDir(binSrc, path.join(serverNodeModulesDest, '.bin'));
      }
    } else {
      console.warn('Warning: node_modules not found. Server dependencies may not be available at runtime.');
    }

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
