import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

Item {
    id: root

    property var    pluginApi:      null
    property bool   running:        false
    property string status:         "stopped"
    property bool   pendingRestart: false

    // ─── Settings ───
    readonly property bool cfgEnabled:    pluginApi?.pluginSettings?.enabled    ?? true
    readonly property int  cfgDebounceMs: pluginApi?.pluginSettings?.debounceMs ?? 100

    readonly property string scriptPath:     (pluginApi?.pluginDir ?? "")     + "/auto-center.py"
    readonly property string configFilePath: (pluginApi?.pluginDir ?? "/tmp") + "/runtime-config.json"

    // ─── Settings changed handlers ───
    onCfgEnabledChanged: {
        if (cfgEnabled) {
            startDaemon();
        } else {
            pendingRestart = false;
            stopDaemon();
        }
    }

    onCfgDebounceMsChanged: {
        if (running) hotReloadConfig();
    }

    Component.onCompleted: {
        if (cfgEnabled) startDaemon();
    }

    Component.onDestruction: {
        pendingRestart = false;
        stopDaemon();
    }

    // ─── Daemon lifecycle ───
    function startDaemon() {
        if (running) return;
        daemonProcess.running = true;
    }

    function stopDaemon() {
        if (!running) return;
        daemonProcess.signal(15); // SIGTERM
    }

    function restartDaemon() {
        pendingRestart = true;
        stopDaemon();
    }

    function hotReloadConfig() {
        const config = JSON.stringify({
            debounceMs: cfgDebounceMs
        });
        configWriter.command = [
            "bash", "-c",
            "cat > " + configFilePath + " << 'PIEOF'\n" + config + "\nPIEOF"
        ];
        configWriter.running = true;
    }

    // ─── Settings helpers ───
    function setEnabled(value) {
        if (!pluginApi?.pluginSettings) return;
        pluginApi.pluginSettings.enabled = value;
        pluginApi.saveSettings();
    }

    function setDebounceMs(value) {
        if (value < 50 || value > 2000) return;
        if (!pluginApi?.pluginSettings) return;
        pluginApi.pluginSettings.debounceMs = value;
        pluginApi.saveSettings();
    }

    function toggle() {
        setEnabled(!root.cfgEnabled);
    }

    // ─── Config writer (writes runtime config, sends SIGUSR1) ───
    readonly property Process configWriter: Process {
        running: false

        onExited: {
            if (root.running) {
                root.daemonProcess.signal(10); // SIGUSR1
            }
        }
    }

    // ─── Daemon process ───
    readonly property Process daemonProcess: Process {
        command: [
            "python3", root.scriptPath,
            "--debounce", String(root.cfgDebounceMs / 1000.0),
            "--config-file", root.configFilePath
        ]

        running: false

        onStarted: {
            root.running = true;
            root.status = "running";
        }

        onExited: (exitCode, exitStatus) => {
            root.running = false;

            if (root.pendingRestart) {
                root.pendingRestart = false;
                root.status = "starting";
                root.startDaemon();
                return;
            }

            if (exitCode === 0 || exitStatus === Process.CrashExit) {
                root.status = "stopped";
            } else {
                root.status = "error";
                if (root.cfgEnabled) {
                    restartTimer.start();
                }
            }
        }

        stderr: StdioCollector {
            onStreamFinished: {
                const msg = text.trim();
                if (msg) {
                    Logger.w("auto-center", msg);
                }
            }
        }
    }

    // ─── Auto-restart timer ───
    readonly property Timer restartTimer: Timer {
        interval: 2000
        repeat: false
        onTriggered: {
            if (root.cfgEnabled && !root.running) {
                root.startDaemon();
            }
        }
    }

    // ─── IPC handler for CLI control ───
    IpcHandler {
        target: "plugin:niri-auto-center"

        function toggle() {
            if (pluginApi?.pluginSettings) {
                pluginApi.pluginSettings.enabled = !root.cfgEnabled;
                pluginApi.saveSettings();
            }
        }

        function status() {
            return {
                running: root.running,
                enabled: root.cfgEnabled,
                status: root.status
            };
        }
    }
}
