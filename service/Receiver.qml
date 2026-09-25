import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  readonly property string sourceDir: {
    var home = Quickshell.env("HOME") || ""
    if (home !== "") return home + "/.config/omarchy/plugins/omarchy-quickshare"
    if (manifest && manifest.__sourceDir) return String(manifest.__sourceDir)
    return ""
  }
  readonly property string controllerPath: sourceDir === "" ? "" : sourceDir + "/bin/quickshare-controller"

  property bool ready: false
  property string phase: "starting"
  property string lastError: ""
  property var devices: []
  property var incoming: null
  property var transfers: []
  property var recentReceived: []

  property string payloadKind: ""
  property var selectedPaths: []
  property string payloadLabel: ""
  property string _chooserMode: ""

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
    var headline = "Quick Share · PIN " + (pin !== "" ? pin : "----")
    var body = sender + " wants to send " + count + (count === 1 ? " file" : " files") + " (" + formatBytes(request.total_bytes) + "). Click to Accept."

    Quickshell.execDetached([
      "omarchy-notification-send",
      "--app-name", "Quick Share",
      "--urgency", "critical",
      "-g", "󰄜",
      "--exec", "omarchy-shell -q shell summon omarchy-quickshare",
      headline,
      body
    ])
  }

  function acceptRequest(id) {
    if (!id) return
    Quickshell.execDetached([controllerPath, "accept", "--request-id", String(id)])
    if (incoming) {
      var list = recentReceived ? recentReceived.slice(0) : []
      var files = incoming.files instanceof Array && incoming.files.length > 0 ? incoming.files : ["Received file"]
      var sender = String(incoming.device || "Android device")
      var bytes = incoming.total_bytes
      for (var i = 0; i < files.length; i++) {
        list.unshift({
          name: String(files[i]),
          device: sender,
          bytes: bytes,
          time: "Just now"
        })
      }
      recentReceived = list.slice(0, 10)
    }
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

  function chooseFiles() {
    startChooser("files")
  }

  function chooseFolder() {
    startChooser("folder")
  }

  function startChooser(mode) {
    if (chooserProcess.running) return
    _chooserMode = mode
    chooserProcess.command = mode === "folder"
      ? ["omarchy-file-select", "--title", "Share a folder via Quick Share", "--directory"]
      : ["omarchy-file-select", "--title", "Share files via Quick Share", "--multiple"]
    chooserProcess.running = true
  }

  function chooseClipboard() {
    payloadKind = "clipboard"
    selectedPaths = []
    payloadLabel = "Clipboard content"
  }

  function clearPayload() {
    payloadKind = ""
    selectedPaths = []
    payloadLabel = ""
  }

  function finishChooser(exitCode) {
    if (exitCode !== 0) return
    var text = String(chooserStdout.text || "").replace(/\r/g, "").trim()
    if (text === "") return
    var paths = text.split("\n")
    if (paths.length === 0) return
    payloadKind = _chooserMode === "folder" ? "folder" : "files"
    selectedPaths = paths
    if (_chooserMode === "folder") {
      var parts = paths[0].split("/")
      payloadLabel = "Folder: " + (parts.length > 0 ? parts[parts.length - 1] : paths[0])
    } else {
      payloadLabel = paths.length === 1 ? paths[0].split("/").pop() : paths.length + " files selected"
    }
    Quickshell.execDetached(["omarchy-shell", "-q", "shell", "summon", "omarchy-quickshare"])
  }

  Process {
    id: chooserProcess
    running: false
    stdout: StdioCollector {
      id: chooserStdout
      waitForEnd: true
    }
    onExited: (code, status) => {
      finishChooser(code)
    }
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
