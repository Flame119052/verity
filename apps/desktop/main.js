const { app, BrowserWindow, Menu, Tray, nativeImage, dialog } = require('electron');
const { autoUpdater } = require('electron-updater');
const { spawn, execSync } = require('child_process');
const path = require('path');
const fs = require('fs');
const os = require('os');
const http = require('http');

// Resolve paths that must land on the real filesystem (never inside an asar
// archive). When Electron packages main.js, __dirname points to the VIRTUAL
// path inside app.asar (e.g. ".../app.asar/"), which is NOT a real directory.
// spawn()'s `cwd` and the `serverEntry` argument both need real on-disk paths.
//
// In production:
//   process.resourcesPath  => .../VERITY.app/Contents/Resources   (real FS)
//   app.asar               => the packed bundle (JS source lives here)
//   app.asar.unpacked/     => files excluded from the asar via asarUnpack
//
// In dev (not packaged):
//   __dirname is the real on-disk directory, so we fall back to it directly.
function getResourcePath(...segments) {
  const base = app.isPackaged
    ? process.resourcesPath          // real Resources/ dir in production
    : path.join(__dirname, '..', '..', '..', 'apps', 'desktop'); // dev fallback
  return path.join(base, ...segments);
}

let serverProcess = null;
let mainWindow = null;
let tray = null;
let serverStatus = 'Starting…';
const PORT = 4477;

// A GUI app launched via Finder/Dock (not a terminal) gets macOS's minimal
// default PATH (from /etc/paths + /etc/paths.d — confirmed on a real machine
// to exclude ~/.local/bin and any nvm-managed Node install), NOT the user's
// full shell PATH. Since Claude/Codex/Antigravity's CLIs commonly live in
// exactly those excluded locations, the server (and the CLI-detection code
// it runs) would never find them without this — a well-known Electron/macOS
// gotcha. Resolve the real PATH the same way opening Terminal would, once,
// at startup, by asking the user's own login+interactive shell what its PATH
// is (this sources .zshrc/.zprofile/.bash_profile, wherever nvm/Homebrew/etc.
// actually add themselves).
function resolveFullPath() {
  const shell = process.env.SHELL || '/bin/zsh';
  try {
    const output = execSync(`${shell} -ilc 'echo "___PATH___$PATH"'`, {
      timeout: 10000,
      encoding: 'utf8'
    });
    // Interactive shells can print banners/MOTD before the echo runs — find
    // the marked line rather than assuming the last line is clean.
    const match = output.match(/___PATH___(.+)/);
    if (match && match[1].trim()) {
      return match[1].trim();
    }
  } catch (err) {
    console.error('Could not resolve full shell PATH, falling back to default:', err.message);
  }
  return process.env.PATH;
}

const RESOLVED_PATH = resolveFullPath();
console.log('Resolved PATH for server/CLI subprocesses:', RESOLVED_PATH);

function isServerAlreadyRunning(callback) {
  http.get(`http://localhost:${PORT}/api/health`, (res) => {
    callback(res.statusCode === 200);
  }).on('error', () => callback(false));
}

function waitForServer(callback, attempts = 30) {
  const checkServer = () => {
    http.get(`http://localhost:${PORT}/api/health`, (res) => {
      if (res.statusCode === 200) {
        callback();
      } else {
        if (attempts <= 0) {
          console.error('Server returned non-200 status');
          callback();
          return;
        }
        attempts--;
        setTimeout(checkServer, 500);
      }
    })
      .on('error', () => {
        if (attempts <= 0) {
          console.error('Server did not start in time');
          callback();
          return;
        }
        attempts--;
        setTimeout(checkServer, 500);
      });
  };
  checkServer();
}

function startServer() {
  // In production, server JS lives inside the asar but node_modules and
  // package.json are unpacked to app.asar.unpacked/ so they sit on the real
  // filesystem (required for native require() and ESM type detection).
  //
  // server/dist/index.js is an ES module (server tsconfig: "module": "ES2020").
  // Node recognises it as ESM only when it finds a sibling package.json that
  // contains "type": "module". That package.json is in app.asar.unpacked/server/
  // (added to asarUnpack in package.json build config), so we set the entry
  // point to the UNPACKED copy of index.js so Node's module resolution walks
  // up to the correct package.json.
  const serverEntry = app.isPackaged
    ? getResourcePath('app.asar.unpacked', 'server', 'dist', 'index.js')
    : path.join(__dirname, 'server', 'dist', 'index.js');

  // cwd MUST be a real directory. In production this is the unpacked server
  // directory; in dev it is the on-disk server directory.
  const serverCwd = app.isPackaged
    ? getResourcePath('app.asar.unpacked', 'server')
    : path.join(__dirname, 'server');

  console.log(`Starting server at: ${serverEntry}`);
  console.log(`Server cwd: ${serverCwd}`);

  // Validate paths exist before spawning to produce a meaningful error instead
  // of a cryptic ENOTDIR / ENOENT from the OS.
  if (!fs.existsSync(serverEntry)) {
    console.error(`[startServer] Server entry not found: ${serverEntry}`);
    console.error('The app may not have been built correctly. Run: npm run dist');
    return;
  }
  if (!fs.existsSync(serverCwd)) {
    console.error(`[startServer] Server cwd not found: ${serverCwd}`);
    console.error('Ensure asarUnpack includes server/node_modules and server/package.json');
    return;
  }

  serverProcess = spawn(process.execPath, [serverEntry], {
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', PATH: RESOLVED_PATH },
    stdio: 'pipe',
    cwd: serverCwd
  });

  serverProcess.stdout.on('data', (data) => {
    console.log(`[SERVER] ${data.toString().trim()}`);
  });

  serverProcess.stderr.on('data', (data) => {
    console.error(`[SERVER ERR] ${data.toString().trim()}`);
  });

  serverProcess.on('error', (err) => {
    console.error('Failed to start server:', err);
  });

  serverProcess.on('close', (code) => {
    console.log(`Server process exited with code ${code}`);
    if (!app.isQuitting) {
      setServerStatus('Stopped');
    }
  });
}

function setupAutoUpdater() {
  // Only set up auto-updater in packaged app, not in development
  if (!app.isPackaged) {
    console.log('[AUTO-UPDATER] Skipping update check in development mode');
    return;
  }

  console.log('[AUTO-UPDATER] Initializing auto-updater...');

  autoUpdater.on('error', (err) => {
    console.error('[AUTO-UPDATER] Error:', err);
  });

  autoUpdater.on('checking-for-update', () => {
    console.log('[AUTO-UPDATER] Checking for updates...');
  });

  autoUpdater.on('update-available', (info) => {
    console.log('[AUTO-UPDATER] Update available:', info.version);
  });

  autoUpdater.on('update-not-available', (info) => {
    console.log('[AUTO-UPDATER] No update available. Current version:', info.version);
  });

  autoUpdater.on('download-progress', (progress) => {
    console.log(`[AUTO-UPDATER] Download progress: ${Math.round(progress.percent)}%`);
  });

  autoUpdater.on('update-downloaded', (info) => {
    console.log('[AUTO-UPDATER] Update downloaded:', info.version);
    console.log('[AUTO-UPDATER] Will be installed on app quit');
  });

  // Check for updates and notify user
  autoUpdater.checkForUpdatesAndNotify();
}

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    icon: path.join(__dirname, 'assets', 'icon.png'),
    webPreferences: {
      contextIsolation: true,
      preload: undefined
    }
  });

  mainWindow.loadURL(`http://localhost:${PORT}`);

  // Open dev tools for debugging (remove in production)
  // mainWindow.webContents.openDevTools();

  mainWindow.on('close', (e) => {
    if (!app.isQuitting) {
      e.preventDefault();
      mainWindow.hide();
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

// Reads the hidden config's vaultPath (if any) — used only to know what
// "delete everything" would remove; never guesses a default path.
function readConfiguredVaultPath() {
  const configPath = path.join(os.homedir(), 'Library', 'Application Support', 'VERITY', 'config.json');
  try {
    const raw = fs.readFileSync(configPath, 'utf8');
    const parsed = JSON.parse(raw);
    return typeof parsed.vaultPath === 'string' ? parsed.vaultPath : null;
  } catch {
    return null;
  }
}

// Stops the server child and undoes the login-item registration — shared by
// both uninstall paths, since both remove the app itself.
function stopServerAndLoginItem() {
  if (serverProcess && !serverProcess.killed) {
    serverProcess.kill('SIGTERM');
  }
  app.setLoginItemSettings({ openAtLogin: false });
}

// Deletes the .app bundle itself. macOS allows removing a running executable's
// backing files (unlike Windows), but this must be the LAST thing done before
// quitting — nothing should run after it that depends on the bundle's own
// files still being present.
function deleteAppBundle() {
  // In dev mode, process.execPath points at Electron's OWN dev binary
  // (node_modules/electron/dist/Electron.app/...) — deleting that would wipe
  // the shared Electron install used for development, not "the app". Only
  // ever delete the bundle when actually running as a packaged app.
  if (!app.isPackaged) {
    console.warn('Skipping app bundle deletion — not running as a packaged app (dev mode).');
    return;
  }
  // process.execPath is .../VERITY.app/Contents/MacOS/VERITY — the bundle
  // root is three directories up from the executable.
  const bundlePath = path.resolve(path.dirname(process.execPath), '..', '..');
  if (bundlePath.endsWith('.app') && fs.existsSync(bundlePath)) {
    fs.rmSync(bundlePath, { recursive: true, force: true });
  }
}

function uninstallDeleteAppOnly() {
  stopServerAndLoginItem();
  try {
    deleteAppBundle();
  } catch (err) {
    console.error('Failed to delete app bundle:', err);
  }
  app.isQuitting = true;
  app.quit();
}

function uninstallDeleteEverything() {
  stopServerAndLoginItem();
  const vaultPath = readConfiguredVaultPath();
  const hiddenConfigDir = path.join(os.homedir(), 'Library', 'Application Support', 'VERITY');
  try {
    // Never touch the installed AI provider CLIs (claude/codex/agy) — those
    // are general-purpose tools the user may use outside VERITY entirely,
    // not this app's to remove.
    if (vaultPath && fs.existsSync(vaultPath)) {
      fs.rmSync(vaultPath, { recursive: true, force: true });
    }
    if (fs.existsSync(hiddenConfigDir)) {
      fs.rmSync(hiddenConfigDir, { recursive: true, force: true });
    }
    deleteAppBundle();
  } catch (err) {
    console.error('Failed during full uninstall:', err);
  }
  app.isQuitting = true;
  app.quit();
}

function showUninstallDialog() {
  const vaultPath = readConfiguredVaultPath();
  const choice = dialog.showMessageBoxSync({
    type: 'warning',
    title: 'Uninstall VERITY',
    message: 'How do you want to uninstall VERITY?',
    detail:
      (vaultPath ? `Your vault is at:\n${vaultPath}\n\n` : '') +
      'Removing the app never touches Claude/Codex/Antigravity — those are separate tools you may use elsewhere.',
    buttons: ['Delete app only, keep my data', 'Delete everything', 'Cancel'],
    defaultId: 2,
    cancelId: 2
  });

  if (choice === 0) {
    uninstallDeleteAppOnly();
    return;
  }
  if (choice === 1) {
    // A second, explicit confirmation for the irreversible path — a single
    // Yes/No isn't enough friction for permanently deleting real data.
    const confirmed = dialog.showMessageBoxSync({
      type: 'warning',
      title: 'Delete everything?',
      message: 'This permanently deletes your vault. This cannot be undone.',
      detail: vaultPath ? `This will delete:\n${vaultPath}\n\nand the app itself.` : 'This will delete the app itself.',
      buttons: ['Cancel', 'Yes, delete everything'],
      defaultId: 0,
      cancelId: 0
    });
    if (confirmed === 1) {
      uninstallDeleteEverything();
    }
  }
  // choice === 2 (Cancel): do nothing.
}

function quitApp() {
  app.isQuitting = true;
  if (serverProcess && !serverProcess.killed) {
    serverProcess.kill();
  }
  app.quit();
}

// Menu-bar (status-bar) icon — the always-on-service equivalent of the Dock
// icon. Reuses the existing app icon as a template image (macOS auto-tints
// template images to match light/dark menu bars) so no new asset is needed.
function buildTrayMenu() {
  return Menu.buildFromTemplate([
    { label: `Server: ${serverStatus}`, enabled: false },
    { type: 'separator' },
    {
      label: 'Open VERITY',
      click: () => {
        if (mainWindow) {
          mainWindow.show();
        } else {
          createWindow();
          setupAutoUpdater();
        }
      }
    },
    {
      label: 'Check for Updates',
      click: () => {
        if (app.isPackaged) {
          autoUpdater.checkForUpdatesAndNotify();
        }
      }
    },
    { type: 'separator' },
    { label: 'Uninstall VERITY…', click: () => showUninstallDialog() },
    { type: 'separator' },
    { label: 'Quit VERITY', click: () => quitApp() }
  ]);
}

function setServerStatus(status) {
  serverStatus = status;
  if (tray) {
    tray.setContextMenu(buildTrayMenu());
  }
}

function createTray() {
  const iconPath = path.join(__dirname, 'assets', 'icon.png');
  let image = nativeImage.createFromPath(iconPath);
  if (!image.isEmpty()) {
    image = image.resize({ width: 22, height: 22 });
    image.setTemplateImage(true);
  }
  tray = new Tray(image);
  tray.setToolTip('VERITY');
  tray.setContextMenu(buildTrayMenu());
  tray.on('click', () => {
    if (mainWindow) {
      mainWindow.show();
    } else {
      createWindow();
      setupAutoUpdater();
    }
  });
}

app.whenReady().then(() => {
  console.log('App ready, checking for an already-running server...');
  // A prior crash / force-quit can leave an orphaned server child still
  // holding the port (Electron's own cleanup hooks never ran). Rather than
  // spawning a second server that would just fail to bind, detect that case
  // and reuse the one already there.
  createTray();

  isServerAlreadyRunning((running) => {
    if (running) {
      console.log('Server already responding — reusing it, not spawning a new one.');
      setServerStatus('Running');
      createWindow();
      setupAutoUpdater();
      return;
    }
    console.log('No server running yet, starting one...');
    setServerStatus('Starting…');
    startServer();
    waitForServer(() => {
      console.log('Server ready, creating window...');
      setServerStatus('Running');
      createWindow();
      setupAutoUpdater();
    });
  });

  app.setLoginItemSettings({ openAtLogin: true });

  app.on('activate', () => {
    if (mainWindow) {
      mainWindow.show();
    } else {
      createWindow();
      setupAutoUpdater();
    }
  });

  const menu = Menu.buildFromTemplate([
    {
      label: 'VERITY',
      submenu: [
        {
          label: 'Uninstall VERITY…',
          click: () => showUninstallDialog()
        },
        { type: 'separator' },
        {
          label: 'Quit VERITY',
          accelerator: 'Cmd+Q',
          click: () => quitApp()
        }
      ]
    },
    {
      label: 'Edit',
      submenu: [
        { role: 'undo' },
        { role: 'redo' },
        { type: 'separator' },
        { role: 'cut' },
        { role: 'copy' },
        { role: 'paste' }
      ]
    },
    {
      label: 'View',
      submenu: [
        { role: 'reload' },
        { role: 'forceReload' },
        { role: 'toggleDevTools' }
      ]
    }
  ]);
  Menu.setApplicationMenu(menu);
});

app.on('window-all-closed', (e) => {
  // Don't quit; keep running for dock icon
  e.preventDefault();
});

app.on('before-quit', () => {
  app.isQuitting = true;
  if (serverProcess && !serverProcess.killed) {
    console.log('Killing server process...');
    serverProcess.kill('SIGTERM');
    // Give it 2 seconds to clean up, then force kill if needed
    setTimeout(() => {
      if (serverProcess && !serverProcess.killed) {
        serverProcess.kill('SIGKILL');
      }
    }, 2000);
  }
});
