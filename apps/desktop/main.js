const { app, BrowserWindow, Menu } = require('electron');
const { spawn } = require('child_process');
const path = require('path');
const http = require('http');

let serverProcess = null;
let mainWindow = null;
const PORT = 4477;

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
    env: { ...process.env, ELECTRON_RUN_AS_NODE: '1' },
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
      return;
    }
    console.log('No server running yet, starting one...');
    startServer();
    waitForServer(() => {
      console.log('Server ready, creating window...');
      createWindow();
    });
  });

  app.setLoginItemSettings({ openAtLogin: true });

  app.on('activate', () => {
    if (mainWindow) {
      mainWindow.show();
    } else {
      createWindow();
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
