const { app, BrowserWindow, Menu } = require('electron');
const { autoUpdater } = require('electron-updater');
const { spawn, execSync } = require('child_process');
const path = require('path');
const http = require('http');

let serverProcess = null;
let mainWindow = null;
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
  const serverEntry = path.join(__dirname, 'server', 'dist', 'index.js');
  console.log(`Starting server at: ${serverEntry}`);

  serverProcess = spawn(process.execPath, [serverEntry], {
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1', PATH: RESOLVED_PATH },
    stdio: 'pipe',
    cwd: path.join(__dirname, 'server')
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

app.whenReady().then(() => {
  console.log('App ready, checking for an already-running server...');
  // A prior crash / force-quit can leave an orphaned server child still
  // holding the port (Electron's own cleanup hooks never ran). Rather than
  // spawning a second server that would just fail to bind, detect that case
  // and reuse the one already there.
  isServerAlreadyRunning((running) => {
    if (running) {
      console.log('Server already responding — reusing it, not spawning a new one.');
      createWindow();
      setupAutoUpdater();
      return;
    }
    console.log('No server running yet, starting one...');
    startServer();
    waitForServer(() => {
      console.log('Server ready, creating window...');
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
          label: 'Quit VERITY',
          accelerator: 'Cmd+Q',
          click: () => {
            app.isQuitting = true;
            if (serverProcess && !serverProcess.killed) {
              serverProcess.kill();
            }
            app.quit();
          }
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
