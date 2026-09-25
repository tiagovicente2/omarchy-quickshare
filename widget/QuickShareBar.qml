import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy-quickshare"

  readonly property var quickshare: bar?.shell?.serviceFor("omarchy-quickshare")
  readonly property bool ready: quickshare ? quickshare.ready : false
  readonly property int deviceCount: quickshare ? quickshare.onlineDeviceCount : 0
  readonly property bool hasTransfer: quickshare ? quickshare.hasActiveTransfer : false
  readonly property bool hasIncoming: quickshare && quickshare.incoming !== null

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.hasTransfer ? "󰁝" : (root.hasIncoming ? "󰁅" : "󰄜")
    foreground: root.hasIncoming
      ? (root.bar ? root.bar.urgent : Color.urgent)
      : (root.hasTransfer
          ? (root.bar ? root.bar.accent : Color.accent)
          : (root.ready ? (root.bar ? root.bar.barForeground : Color.foreground) : Qt.darker(Color.foreground, 1.8)))
    slotSize: Style.bar.statusSlot

    tooltipText: {
      if (root.hasIncoming) return "Quick Share: Incoming file request"
      if (root.hasTransfer) return "Quick Share: Transferring files..."
      if (root.ready) return "Quick Share: Ready (" + root.deviceCount + " devices nearby)"
      return "Quick Share: Offline"
    }

    onPressed: function(b) {
      if (!root.bar) return
      // Toggle Quick Share panel or file share action
      if (quickshare && quickshare.startDaemon && !root.ready) {
        quickshare.startDaemon()
      }
    }
  }
}
