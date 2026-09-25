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

  property var _notifiedRequests: ({})

  function formatBytes(value) {
    var bytes = Number(value || 0)
    if (!isFinite(bytes) || bytes < 0) bytes = 0
    var units = ["B", "KB", "MB", "GB", "TB"]
    var index = 0
    while (bytes >= 1024 && index < units.length - 1) {
      bytes /= 1024
      index++
    }
    var precision = index === 0 ? 0 : (bytes >= 10 ? 1 : 2)
    return bytes.toFixed(precision) + " " + units[index]
  }

  function notifyIncoming(request) {
    var id = String(request.id || "")
    if (id === "" || _notifiedRequests[id]) return
    var next = ({})
    for (var key in _notifiedRequests) next[key] = _notifiedRequests[key]
    next[id] = true
    _notifiedRequests = next

    var sender = String(request.device || "Android device")
    var pin = String(request.pin || "")
    var count = request.files instanceof Array ? request.files.length : 0
    var body = "PIN: " + pin + " · " + count + (count === 1 ? " file" : " files") + " (" + formatBytes(request.total_bytes) + ") from " + sender

    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Quick Share",
      "--urgency", "critical",
      "--glyph", "󰄜",
      "--exec", "omarchy-shell -q shell summon omarchy-quickshare",
      "Incoming Quick Share Request",
      body
    ])
  }

  function acceptRequest(id) {
    if (!id) return
    Quickshell.execDetached([controllerPath, "accept", "--request-id", String(id)])
    incoming = null
  }

  function declineRequest(id) {
    if (!id) return
    Quickshell.execDetached([controllerPath, "decline", "--request-id", String(id)])
    incoming = null
  }

  function cancelTransfer(id) {
    if (!id) return
    Quickshell.execDetached([controllerPath, "cancel", "--transfer-id", String(id)])
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
            if (root.incoming) {
              root.notifyIncoming(root.incoming)
            }
          } else if (msg.event === "progress") {
            var transfer = msg.data
            var list = []
            var found = false
            for (var i = 0; i < root.transfers.length; i++) {
              if (root.transfers[i].id === transfer.id) {
                list.push(transfer)
                found = true
              } else {
                list.push(root.transfers[i])
              }
            }
            if (!found) list.push(transfer)
            root.transfers = list
          } else if (msg.event === "transfers") {
            root.transfers = msg.data || []
            if (root.transfers.length === 0) {
              root.incoming = null
            }
          }
        } catch (e) {
          // ignore non-JSON debug lines
        }
      }
    }

    stderr: SplitParser {
      split: "\n"
      onRead: text => {
        // Rust stderr debug logging
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
