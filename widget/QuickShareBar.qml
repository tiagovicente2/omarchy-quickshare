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
      if (quickshare && quickshare.ready) return "Quick Share: Ready (" + root.nearbyDevices.length + " nearby)"
      return "Quick Share: Starting..."
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
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(560))

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

          PanelHero {
            width: parent.width
            title: "Quick Share"
            meta: quickshare && quickshare.ready ? "RECEIVER READY" : (quickshare ? String(quickshare.phase || "STARTING").toUpperCase() : "STARTING")
            detail: quickshare ? root.nearbyDevices.length + " NEARBY" : "0 NEARBY"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: quickshare && quickshare.ready ? 1.0 : 0.48
          }

          // 1. INCOMING REQUEST CARD
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

          // 2. ACTIVE TRANSFERS
          Column {
            visible: root.visibleTransfers.length > 0
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "TRANSFERS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.visibleTransfers
              delegate: BorderSurface {
                width: parent.width
                implicitHeight: transferRow.implicitHeight + Style.space(16)
                color: Style.hoverFillFor(root.foreground, Color.accent)
                radius: Style.cornerRadius

                RowLayout {
                  id: transferRow
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(12)
                  anchors.rightMargin: Style.space(12)
                  spacing: Style.space(8)

                  Text {
                    text: "󰇚"
                    color: Color.accent
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(3)

                    Text {
                      Layout.fillWidth: true
                      text: modelData.id ? "Transfer " + modelData.id : "Transferring..."
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideMiddle
                    }

                    Rectangle {
                      Layout.fillWidth: true
                      height: Style.space(4)
                      radius: height / 2
                      color: Qt.darker(root.foreground, 2.2)

                      Rectangle {
                        height: parent.height
                        radius: parent.radius
                        color: Color.accent
                        width: modelData.total > 0 ? parent.width * Math.min(1.0, modelData.transferred / modelData.total) : 0
                      }
                    }
                  }

                  DecisionButton {
                    label: "Cancel"
                    implicitHeight: Style.space(28)
                    implicitWidth: Style.space(70)
                    foreground: root.urgent
                    onClicked: {
                      if (quickshare) quickshare.cancelTransfer(modelData.id)
                    }
                  }
                }
              }
            }
          }

          // 3. NEARBY DEVICES
          Column {
            width: parent.width
            spacing: Style.space(6)

            PanelSectionHeader {
              text: "NEARBY DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              visible: root.nearbyDevices.length === 0
              text: "Looking for nearby Quick Share devices..."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.horizontalCenter: parent.horizontalCenter
            }

            Repeater {
              model: root.nearbyDevices
              delegate: BorderSurface {
                width: parent.width
                implicitHeight: devRow.implicitHeight + Style.space(14)
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
                    text: "󰄜"
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.heading
                  }

                  ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Style.space(1)

                    Text {
                      Layout.fillWidth: true
                      text: String(modelData.name || modelData.id || "Unknown device")
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                    }

                    Text {
                      Layout.fillWidth: true
                      text: modelData.ip ? modelData.ip : "Nearby"
                      color: root.dim
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
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

  component DecisionButton: BorderSurface {
    id: decision

    property string label: ""
    property color foreground: root.foreground
    property bool filled: false
    signal clicked()

    implicitHeight: Style.space(36)
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
      font.pixelSize: Style.font.body
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
