import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "jakubkozera.window-switcher"

  property var minimized: []

  readonly property int iconSize: Math.round(barSize * 0.6)
  readonly property int slotSize: iconSize + Style.space(12)

  visible: minimized.length > 0
  implicitWidth: vertical ? barSize : strip.implicitWidth
  implicitHeight: vertical ? strip.implicitHeight : barSize

  function restore(win) {
    var monitor = Hyprland.focusedMonitor
    var workspace = monitor ? monitor.activeWorkspace : null
    Quickshell.execDetached(Model.activateCommand(win, workspace && workspace.id > 0 ? workspace.id : 1))
  }

  function refresh() {
    if (!snapshotProc.running) snapshotProc.running = true
  }

  function toplevelFor(address) {
    var wanted = String(address).replace(/^0x/, "")
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++)
      if (values[i].address === wanted) return values[i].wayland
    return null
  }

  Component.onCompleted: refresh()

  Process {
    id: snapshotProc
    command: Model.SNAPSHOT_COMMAND
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var snapshot = Model.parseSnapshot(text)
        if (!snapshot.loaded) return
        var next = Model.minimizedWindows(snapshot.windows)
        if (JSON.stringify(next) !== JSON.stringify(root.minimized)) root.minimized = next
      }
    }
  }

  Timer {
    id: refreshDebounce
    interval: 120
    onTriggered: root.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (/^(openwindow|closewindow|movewindow)/.test(event.name)) refreshDebounce.restart()
    }
  }

  Grid {
    id: strip
    anchors.centerIn: parent
    columns: root.vertical ? 1 : Math.max(1, root.minimized.length)
    spacing: 0

    Repeater {
      model: root.minimized

      Item {
        id: slot
        required property var modelData

        width: root.slotSize
        height: root.vertical ? root.slotSize : root.barSize

        Rectangle {
          anchors.centerIn: parent
          width: root.slotSize - Style.space(4)
          height: width
          radius: Style.cornerRadius
          color: mouse.containsMouse ? Style.hoverFill : "transparent"
        }

        WindowIcon {
          anchors.centerIn: parent
          width: root.iconSize
          height: width
          appClass: slot.modelData.cls
          opacity: 0.85
        }

        MouseArea {
          id: mouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.MiddleButton
          cursorShape: Qt.PointingHandCursor
          onEntered: {
            console.log("switcher-preview: entered", slot.modelData.title)
            hoverDelay.restart()
          }
          onExited: {
            hoverDelay.stop()
            previewPopup.open = false
          }
          onClicked: function(event) {
            hoverDelay.stop()
            previewPopup.open = false
            if (event.button === Qt.MiddleButton) Quickshell.execDetached(Model.closeCommand(slot.modelData))
            else root.restore(slot.modelData)
          }
        }

        Timer {
          id: hoverDelay
          interval: 400
          onTriggered: {
            console.log("switcher-preview: timer", slot.modelData.title)
            Hyprland.refreshToplevels()
            previewPopup.open = true
          }
        }

        PopupCard {
          id: previewPopup
          anchorItem: slot
          bar: root.bar
          triggerMode: "hover"
          open: false
          contentWidth: fittedContentWidth(Style.space(260))
          contentHeight: fittedContentHeight(previewContent.implicitHeight)

          Column {
            id: previewContent
            width: parent.width
            spacing: Style.space(8)

            Rectangle {
              width: parent.width
              height: Style.space(140)
              radius: Style.cornerRadius
              color: Util.alpha(Commons.Color.popups.text, 0.08)
              clip: true

              ScreencopyView {
                id: capture
                captureSource: previewPopup.open ? root.toplevelFor(slot.modelData.address) : null
                live: true
                anchors.centerIn: parent
                readonly property real aspect: sourceSize.height > 0 ? sourceSize.width / sourceSize.height : 1
                width: Math.min(parent.width, parent.height * aspect)
                height: width / Math.max(aspect, 0.01)
                visible: hasContent
              }

              WindowIcon {
                anchors.centerIn: parent
                width: Style.space(48)
                height: width
                appClass: slot.modelData.cls
                visible: !capture.hasContent
              }
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: slot.modelData.title || slot.modelData.cls
              color: Commons.Color.popups.text
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
        }
      }
    }
  }
}
