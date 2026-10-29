import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
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
          onEntered: if (root.bar) root.bar.showTooltip(slot, slot.modelData.title || slot.modelData.cls)
          onExited: if (root.bar) root.bar.hideTooltip(slot)
          onClicked: function(event) {
            if (root.bar) root.bar.hideTooltip(slot)
            if (event.button === Qt.MiddleButton) Quickshell.execDetached(Model.closeCommand(slot.modelData))
            else root.restore(slot.modelData)
          }
        }
      }
    }
  }
}
