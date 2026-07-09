const { app, BrowserWindow, Menu, Tray, nativeImage, dialog, ipcMain } = require('electron');
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

// Reports success/failure to the callback (rather than always calling it
// unconditionally once attempts run out) so the caller can distinguish "the
// server came up" from "it never did" — previously both cases proceeded
// identically to createWindow(), silently opening a window against a server
// that was never actually there, with no error shown anywhere and the Tray
// stuck on "Starting…" forever.
function waitForServer(callback, attempts = 30) {
  const checkServer = () => {
    http.get(`http://localhost:${PORT}/api/health`, (res) => {
      if (res.statusCode === 200) {
        callback(true);
      } else {
        if (attempts <= 0) {
          console.error('Server returned non-200 status');
          callback(false);
          return;
        }
        attempts--;
        setTimeout(checkServer, 500);
      }
    })
      .on('error', () => {
        if (attempts <= 0) {
          console.error('Server did not start in time');
          callback(false);
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
    // Native macOS chrome: inset traffic lights over a blurred title-bar
    // region, rather than a plain default-chrome window that just happens to
    // load a page — the app's own content (the Strip Board board/paper
    // theme) is unchanged below the title-bar area.
    titleBarStyle: 'hiddenInset',
    trafficLightPosition: { x: 16, y: 16 },
    vibrancy: 'under-window',
    backgroundColor: '#0d0f12', // matches --board, avoids a white flash pre-paint
    webPreferences: {
      contextIsolation: true,
      preload: path.join(__dirname, 'preload.js')
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

function appBundleForExecutable(executablePath) {
  const match = executablePath.match(/^(.*?\.app)(?:\/|$)/);
  return match ? match[1] : null;
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
  const bundlePaths = new Set();
  const runningBundle = appBundleForExecutable(process.execPath);
  if (runningBundle) bundlePaths.add(runningBundle);
  bundlePaths.add('/Applications/VERITY.app');
  bundlePaths.add(path.join(os.homedir(), 'Applications', 'VERITY.app'));

  for (const bundlePath of bundlePaths) {
    if (bundlePath.endsWith('.app') && fs.existsSync(bundlePath)) {
      fs.rmSync(bundlePath, { recursive: true, force: true });
    }
  }
}

function removeIfExists(targetPath) {
  if (targetPath && fs.existsSync(targetPath)) {
    fs.rmSync(targetPath, { recursive: true, force: true });
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
  // Electron's OWN default userData directory (~/Library/Application
  // Support/verity-desktop, derived from package.json's "name") is separate
  // from the app's own hidden config dir above — it holds Chromium's local
  // storage/session/cache. Must be read via app.getPath() while the app
  // instance is still alive (it can't be recomputed after quit). Previously
  // never deleted at all, so "delete everything" wasn't actually everything —
  // a reinstall could still find stale renderer-side state left behind.
  const userDataDir = app.getPath('userData');
  try {
    // Never touch the installed AI provider CLIs (claude/codex/agy) — those
    // are general-purpose tools the user may use outside VERITY entirely,
    // not this app's to remove.
    removeIfExists(vaultPath);
    removeIfExists(hiddenConfigDir);
    removeIfExists(userDataDir);
    removeIfExists(path.join(os.homedir(), 'Library', 'Caches', 'verity-desktop'));
    removeIfExists(path.join(os.homedir(), 'Library', 'Caches', 'verity-desktop-updater'));
    removeIfExists(path.join(os.homedir(), 'Library', 'Logs', 'verity-desktop'));
    removeIfExists(path.join(os.homedir(), 'Library', 'Saved Application State', 'com.krish.verity.savedState'));
    removeIfExists(path.join(os.homedir(), 'Library', 'Preferences', 'com.krish.verity.plist'));
    // Must be last — nothing below this line may depend on the bundle's own
    // files still being present.
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

// Quick-glance Tray content: "next up" comes from polling the already-running
// server directly (main.js already talks to it for health checks, no new
// dependency), while "currently studying" is renderer-only state (the timer
// lives in apps/web/src/timer.tsx's React state, invisible to this process)
// reported over the one IPC channel preload.js exposes.
let nextUpLabel = null;
let timerStatus = null; // { label: string, minutes: number } | null

function fetchJson(urlPath) {
  return new Promise((resolve) => {
    http
      .get(`http://localhost:${PORT}${urlPath}`, (res) => {
        let data = '';
        res.on('data', (chunk) => (data += chunk));
        res.on('end', () => {
          try {
            resolve(JSON.parse(data));
          } catch {
            resolve(null);
          }
        });
      })
      .on('error', () => resolve(null));
  });
}

async function refreshQuickGlance() {
  const today = new Date().toISOString().split('T')[0];
  const [homeworkRes, scheduleRes] = await Promise.all([
    fetchJson('/api/homework'),
    fetchJson(`/api/schedule/${today}`)
  ]);

  const openHomework = (homeworkRes?.homework ?? []).filter((h) => h.status === 'open');
  if (app.dock && typeof app.dock.setBadge === 'function') {
    app.dock.setBadge(openHomework.length > 0 ? String(openHomework.length) : '');
  }

  const nowMin = (() => {
    const d = new Date();
    return d.getHours() * 60 + d.getMinutes();
  })();
  const slots = scheduleRes?.schedule ?? [];
  const upcoming = slots
    .map((s) => ({ ...s, startMin: hhmmToMinutes(s.start_time) }))
    .filter((s) => s.startMin > nowMin)
    .sort((a, b) => a.startMin - b.startMin)[0];

  if (upcoming) {
    nextUpLabel = `Next: ${upcoming.start_time} · ${upcoming.ref_label}`;
  } else if (openHomework.length > 0) {
    const sorted = [...openHomework].sort((a, b) => a.due_date.localeCompare(b.due_date));
    nextUpLabel = `Due soon: ${sorted[0].subject} — ${sorted[0].task}`;
  } else {
    nextUpLabel = null;
  }

  refreshTray();
}

function hhmmToMinutes(hhmm) {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

ipcMain.on('timer-status', (_event, status) => {
  timerStatus = status && status.running ? { label: status.label, minutes: status.minutes } : null;
  refreshTray();
});

// Menu-bar (status-bar) icon — the always-on-service equivalent of the Dock
// icon. Reuses the existing app icon as a template image (macOS auto-tints
// template images to match light/dark menu bars) so no new asset is needed.
function buildTrayMenu() {
  const quickGlanceRows = [];
  if (timerStatus) {
    quickGlanceRows.push({ label: `● Studying: ${timerStatus.label} · ${timerStatus.minutes}m`, enabled: false });
  }
  if (nextUpLabel) {
    quickGlanceRows.push({ label: nextUpLabel, enabled: false });
  }
  if (quickGlanceRows.length > 0) {
    quickGlanceRows.push({ type: 'separator' });
  }

  return Menu.buildFromTemplate([
    { label: `Server: ${serverStatus}`, enabled: false },
    ...quickGlanceRows,
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

function refreshTray() {
  if (tray) {
    tray.setContextMenu(buildTrayMenu());
  }
}

function setServerStatus(status) {
  serverStatus = status;
  refreshTray();
}

let quickGlancePollTimer = null;

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

  refreshQuickGlance();
  quickGlancePollTimer = setInterval(refreshQuickGlance, 60_000);
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
      refreshQuickGlance(); // don't wait up to 60s for the first poll now that we know it'll succeed
      createWindow();
      setupAutoUpdater();
      return;
    }
    console.log('No server running yet, starting one...');
    setServerStatus('Starting…');
    startServer();
    waitForServer((started) => {
      if (!started) {
        console.error('Server failed to start within the expected time.');
        setServerStatus('Failed to start');
        dialog.showErrorBox(
          'VERITY failed to start',
          'The background service did not respond in time. Try quitting and reopening VERITY. If this keeps happening, check Console.app for "VERITY" log output.'
        );
        return;
      }
      console.log('Server ready, creating window...');
      setServerStatus('Running');
      refreshQuickGlance();
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
