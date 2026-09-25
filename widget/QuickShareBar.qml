pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root

  moduleName: "omarchy-quickshare"
  ipcTarget: "omarchy-quickshare"
  manageIpc: false

  readonly property var quickshare: bar?.shell?.serviceFor("omarchy-quickshare")
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property color barIconColor: quickshare && quickshare.incoming
    ? urgent
    : (quickshare && quickshare.ready ? foreground : dim)

  readonly property var nearbyDevices: {
    var list = []
    if (!quickshare || !(quickshare.devices instanceof Array)) return list
    for (var i = 0; i < quickshare.devices.length; i++) {
      var d = quickshare.devices[i]
      if (d) list.push(d)
    }
    return list
  }

  readonly property var visibleTransfers: {
    if (!quickshare || !(quickshare.transfers instanceof Array)) return []
    return quickshare.transfers
  }

  readonly property bool payloadReady: quickshare && quickshare.payloadKind !== ""

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: quickshare && quickshare.hasActiveTransfer ? "󰁝" : (quickshare && quickshare.incoming ? "󰁅" : "󰄜")
    foreground: root.barIconColor
    slotSize: Style.bar.statusSlot

    tooltipText: {
      if (quickshare && quickshare.incoming) return "Quick Share: Incoming request (" + (quickshare.incoming.pin || "") + ")"
      if (quickshare && quickshare.hasActiveTransfer) return "Quick Share: Transferring files..."
      if (quickshare && quickshare.ready) return "Quick Share: Ready"
      return "Quick Share: Idle"
    }

    onPressed: function(btn) {
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height

        Column {
          id: contentColumn
          width: panelFlick.width
          spacing: Style.space(12)

          // 1. HERO HEADER (Like Image #1 with ToggleSwitch, NO "nearby N" badge)
          PanelHero {
            width: parent.width
            title: "Quick Share"
            meta: quickshare && quickshare.ready ? "RECEIVING" : "NOT RECEIVING"
            detail: ""
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: quickshare && quickshare.ready ? 1.0 : 0.45

            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                checked: quickshare && quickshare.ready
                onToggled: {
                  if (quickshare && quickshare.ready) quickshare.stopDaemon()
                  else if (quickshare) quickshare.startDaemon()
                }
              }
            }
          }

          // 2. DEVICE INFO ROWS (This device, Saving to)
          Column {
            width: parent.width
            spacing: Style.space(5)

            RowLayout {
              width: parent.width
              Text {
                text: "This device"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Item { Layout.fillWidth: true }
              Text {
                text: "tiago-omarchy"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
            }

            RowLayout {
              width: parent.width
              Text {
                text: "Saving to"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
              Item { Layout.fillWidth: true }
              Text {
                text: (Quickshell.env("HOME") || "") + "/Downloads"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          // 3. INCOMING REQUEST CARD (when someone sends a file)
          Column {
            visible: quickshare && quickshare.incoming !== null
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "INCOMING REQUEST"
              foreground: root.urgent
              fontFamily: root.fontFamily
            }

            BorderSurface {
              width: parent.width
              implicitHeight: incomingContent.implicitHeight + Style.space(24)
              color: Style.selectedFillFor(root.urgent, root.urgent)
              borderSpec: Border.flat(root.urgent, 1)
              radius: Style.cornerRadius

              Column {
                id: incomingContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                spacing: Style.space(8)

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)

                  Text {
                    text: "󰄜"
                    color: root.urgent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(2)

                    Text {
                      Layout.fillWidth: true
                      text: quickshare && quickshare.incoming ? String(quickshare.incoming.device || "Android device") : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: {
                        if (!quickshare || !quickshare.incoming) return ""
                        var inc = quickshare.incoming
                        var count = inc.files instanceof Array ? inc.files.length : 0
                        return count + (count === 1 ? " file" : " files") + " (" + quickshare.formatBytes(inc.total_bytes) + ")"
                      }
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // PIN Badge
                  Rectangle {
                    color: Qt.darker(root.urgent, 2.2)
                    border.color: root.urgent
                    border.width: 1
                    radius: Style.cornerRadius
                    implicitWidth: pinText.implicitWidth + Style.space(14)
                    implicitHeight: pinText.implicitHeight + Style.space(6)

                    Text {
                      id: pinText
                      anchors.centerIn: parent
                      text: quickshare && quickshare.incoming ? String(quickshare.incoming.pin || "") : ""
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.heading
                      font.bold: true
                    }
                  }
                }

                Row {
                  width: parent.width
                  spacing: Style.space(8)

                  DecisionButton {
                    width: (parent.width - parent.spacing) / 2
                    label: "Decline"
                    foreground: root.urgent
                    onClicked: {
                      if (quickshare && quickshare.incoming) {
                        quickshare.declineRequest(quickshare.incoming.id)
                      }
                    }
                  }

                  DecisionButton {
                    width: (parent.width - parent.spacing) / 2
                    label: "Accept"
                    foreground: root.foreground
                    filled: true
                    onClicked: {
                      if (quickshare && quickshare.incoming) {
                        quickshare.acceptRequest(quickshare.incoming.id)
                      }
                    }
                  }
                }
              }
            }
          }

          // 4. CHOOSE WHAT TO SHARE (Clean icons from Image #2)
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "CHOOSE WHAT TO SHARE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              ActionTile {
                width: (parent.width - parent.spacing * 2) / 3
                iconText: "󰈔"
                label: "Files"
                selected: root.payloadReady && quickshare.payloadKind === "files"
                onClicked: if (quickshare) quickshare.chooseFiles()
              }

              ActionTile {
                width: (parent.width - parent.spacing * 2) / 3
                iconText: "󰉋"
                label: "Folder"
                selected: root.payloadReady && quickshare.payloadKind === "folder"
                onClicked: if (quickshare) quickshare.chooseFolder()
              }

              ActionTile {
                width: (parent.width - parent.spacing * 2) / 3
                iconText: "󰅇"
                label: "Clipboard"
                selected: root.payloadReady && quickshare.payloadKind === "clipboard"
                onClicked: if (quickshare) quickshare.chooseClipboard()
              }
            }

            // Subtitle when no selection:
            Text {
              visible: !root.payloadReady
              text: "Pick files, a folder, or clipboard text first."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.horizontalCenter: parent.horizontalCenter
            }

            // Payload pill when selected:
            BorderSurface {
              visible: root.payloadReady
              width: parent.width
              implicitHeight: payloadRow.implicitHeight + Style.space(12)
              color: Style.selectedFillFor(root.foreground, Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)
              radius: Style.cornerRadius

              RowLayout {
                id: payloadRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.space(10)
                anchors.rightMargin: Style.space(8)
                spacing: Style.space(8)

                Text {
                  text: quickshare && quickshare.payloadKind === "folder" ? "󰉋" : (quickshare && quickshare.payloadKind === "clipboard" ? "󰅇" : "󰈔")
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                }

                Text {
                  Layout.fillWidth: true
                  text: quickshare ? quickshare.payloadLabel : ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  elide: Text.ElideMiddle
                }

                DecisionButton {
                  label: "✕"
                  implicitWidth: Style.space(28)
                  implicitHeight: Style.space(26)
                  foreground: root.dim
                  onClicked: if (quickshare) quickshare.clearPayload()
                }
              }
            }
          }

          PanelSeparator {
            foreground: root.foreground
          }

          // 5. NEARBY DEVICES (NO DEVICE IP!)
          Column {
            width: parent.width
            spacing: Style.space(8)

            PanelSectionHeader {
              text: "NEARBY DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.nearbyDevices.length === 0
              text: "No nearby devices found."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.horizontalCenter: parent.horizontalCenter
            }

            Repeater {
              model: root.nearbyDevices
              delegate: BorderSurface {
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: devRow.implicitHeight + Style.space(16)
                color: Style.hoverFillFor(root.foreground, Color.accent)
                radius: Style.cornerRadius

                RowLayout {
                  id: devRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(10)

                  Text {
                    text: modelData.rtype === "Desktop" || modelData.rtype === "Laptop" ? "󰍹" : "󰄜"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: String(modelData.name || modelData.id || "Android device")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      font.bold: true
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: "Quick Share device"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }
                  }

                  // Optional Send Button if payload selected
                  DecisionButton {
                    visible: root.payloadReady
                    label: "Send"
                    implicitHeight: Style.space(28)
                    implicitWidth: Style.space(64)
                    filled: true
                    foreground: root.foreground
                    onClicked: {
                      // Trigger send to device
                    }
                  }
                }
              }
            }

            Text {
              text: "Incoming files save to " + ((Quickshell.env("HOME") || "") + "/Downloads")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.horizontalCenter: parent.horizontalCenter
            }
          }

          // 6. RECEIVED HISTORY (like Image #1)
          Column {
            visible: quickshare && quickshare.recentReceived && quickshare.recentReceived.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSeparator {
              foreground: root.foreground
            }

            PanelSectionHeader {
              text: "RECEIVED"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: quickshare ? quickshare.recentReceived : []
              delegate: BorderSurface {
                required property var modelData
                required property int index
                width: parent.width
                implicitHeight: histRow.implicitHeight + Style.space(12)
                color: "transparent"
                radius: Style.cornerRadius

                RowLayout {
                  id: histRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    text: "󰈔"
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.name
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: modelData.time + (modelData.bytes ? " · " + quickshare.formatBytes(modelData.bytes) : "") + " · from " + modelData.device
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Action Tile Component (Image #2 style: Icon above text)
  component ActionTile: BorderSurface {
    id: tile

    property string iconText: ""
    property string label: ""
    property bool selected: false
    signal clicked()

    implicitHeight: Style.space(64)
    color: selected
      ? Style.selectedFillFor(root.foreground, Color.accent)
      : (tileMouse.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
    borderSpec: selected
      ? Border.controlSpec("selected", root.foreground, Color.accent)
      : Border.controlSpec(tileMouse.containsMouse ? "hover" : "normal", root.dim, Color.accent)
    radius: Style.cornerRadius

    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.iconText
        color: tile.selected ? Color.accent : root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.label
        color: tile.selected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: tile.selected
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.clicked()
    }
  }

  component DecisionButton: BorderSurface {
    id: decision

    property string label: ""
    property color foreground: root.foreground
    property bool filled: false
    signal clicked()

    implicitHeight: Style.space(34)
    color: filled
      ? (mouse.containsMouse ? Style.focusFillFor(foreground, Color.accent) : Style.selectedFillFor(foreground, Color.accent))
      : (mouse.containsMouse ? Style.hoverFillFor(foreground, Color.accent) : "transparent")
    borderSpec: Border.controlSpec(mouse.containsMouse ? "hover-cursor" : "normal", foreground, Color.accent)
    radius: Style.cornerRadius

    Text {
      anchors.centerIn: parent
      text: decision.label
      color: decision.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: decision.clicked()
    }
  }
}
