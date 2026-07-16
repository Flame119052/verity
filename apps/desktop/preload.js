const { contextBridge, ipcRenderer } = require('electron');

// Minimal bridge: the renderer's timer state (apps/web/src/timer.tsx) is
// ephemeral React state that only main.js's process can't see directly —
// this is the one channel needed so the Tray's "quick glance" content can
// show whether a timer is currently running, without exposing anything
// broader than that single call.
contextBridge.exposeInMainWorld('verityNative', {
  reportTimerStatus: (status) => ipcRenderer.send('timer-status', status),
  openNativeRelease: () => ipcRenderer.send('open-native-release')
});
