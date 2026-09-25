import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string sourceDir: {
    if (manifest && manifest.__sourceDir) return String(manifest.__sourceDir)
    var here = String(Qt.resolvedUrl(".."))
    if (here.indexOf("file://") === 0) here = here.substring(7)
    try { here = decodeURIComponent(here) } catch (e) {}
    return here.replace(/\/+$/, "")
  }
  readonly property string controllerPath: sourceDir === "" ? "" : sourceDir + "/bin/quickshare-controller"

  property bool ready: false
  property string phase: "starting"
  property string lastError: ""
  property var devices: []
  property var incoming: null
  property var transfers: []

  readonly property int onlineDeviceCount: devices ? devices.length : 0
  readonly property bool hasActiveTransfer: {
    for (var i = 0; i < transfers.length; i++) {
      var state = String(transfers[i] && transfers[i].state || "")
      if (state === "transferring" || state === "preparing") return true
    }
    return false
  }

  function startDaemon() {
    if (controllerPath === "" || daemonProcess.running) return
    ready = false
    phase = "starting"
    daemonProcess.command = ["setpriv", "--pdeathsig", "TERM", controllerPath, "daemon"]
    daemonProcess.running = true
  }

  function stopDaemon() {
    if (daemonProcess.running) {
      daemonProcess.running = false
    }
    ready = false
    phase = "stopped"
  }

  Process {
    id: daemonProcess
    running: false

    stdout: SplitParser {
      split: "\n"
      onRead: text => {
        var line = text.trim()
        if (line.length === 0) return
        try {
          var msg = JSON.parse(line)
          if (msg.event === "ready") {
            root.ready = true
            root.phase = "running"
          } else if (msg.event === "devices") {
            root.devices = msg.data || []
          } else if (msg.event === "incoming") {
            root.incoming = msg.data || null
          } else if (msg.event === "transfers") {
            root.transfers = msg.data || []
          }
        } catch (e) {
          // non-JSON stdout or parse error
        }
      }
    }

    onExited: (code, status) => {
      root.ready = false
      root.phase = "stopped"
    }
  }

  Component.onCompleted: {
    startDaemon()
  }

  Component.onDestruction: {
    stopDaemon()
  }
}
