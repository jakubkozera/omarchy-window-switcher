import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Hold Alt and press Tab to cycle, release Alt to switch. Typing (or Enter,
// a click, or the picker payload) keeps the overlay open instead.
Item {
  id: root

  property bool opened: false
  property bool loaded: false
  property bool sticky: false
  property bool releaseQueued: false
  property real earlyRelease: 0
  property int pendingSteps: 0
  property string filterText: ""
  property var allWindows: []
  property int selectedIndex: 0

  readonly property var windows: Model.filterWindows(allWindows, filterText)

  property color background: Commons.Color.menu.background
  property color foreground: Commons.Color.menu.text
  property color border: Commons.Color.menu.border
  property var borderSpec: Border.surfaceSpec("menu", "border", border, Math.max(1, Style.space(2)))
  property color scrim: Commons.Color.menu.scrim
  property color selectedBackground: Commons.Color.menu.selectedBackground
  property color selectedText: Commons.Color.menu.selectedText
  readonly property int cornerRadius: Style.cornerRadius
  property string fontFamily: Style.font.menuFamily
  property int contentMargin: Style.spacing.panelPadding
  property int contentSpacing: Style.spacing.md
  property int headerHeight: Math.max(Style.space(34), Style.font.title + Style.spacing.controlPaddingY * 2)
  property int footerHeight: Style.font.caption + Style.spacing.controlPaddingY * 2

  readonly property int cellWidth: Style.space(250)
  readonly property int previewHeight: Style.space(140)
  readonly property int labelHeight: Style.space(40)
  readonly property int cellHeight: previewHeight + labelHeight + Style.space(20)
  readonly property int maxColumns: Math.max(1, Math.floor((panel.width - Style.gapsOut * 2 - contentMargin * 2 - Style.space(8)) / cellWidth))
  readonly property int columns: Math.max(1, Math.min(windows.length, maxColumns))
  readonly property int rows: Math.max(1, Math.ceil(windows.length / columns))
  readonly property int gridHeight: Math.min(rows * cellHeight, Math.floor(panel.height * 0.7))

  function toplevelFor(address) {
    var wanted = String(address).replace(/^0x/, "")
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++)
      if (values[i].address === wanted) return values[i].wayland
    return null
  }

  function restoreWorkspaceId() {
    var monitor = Hyprland.focusedMonitor
    var workspace = monitor ? monitor.activeWorkspace : null
    return workspace && workspace.id > 0 ? workspace.id : 1
  }

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    var dir = payload.dir === -1 ? -1 : (payload.dir === 1 ? 1 : 0)

    if (root.opened) {
      root.step(dir || 1)
      return
    }

    root.opened = true
    root.loaded = false
    root.filterText = ""
    root.sticky = payload.picker === true
    root.pendingSteps = dir
    root.releaseQueued = !root.sticky && Date.now() - root.earlyRelease < 400
    Hyprland.refreshToplevels()
    snapshotProc.running = true
  }

  function close() {
    root.opened = false
    root.loaded = false
    root.releaseQueued = false
  }

  function step(delta) {
    if (!root.loaded) { root.pendingSteps += delta; return }
    root.selectedIndex = Model.wrap(root.selectedIndex + delta, root.windows.length)
    grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
  }

  function moveRows(delta) {
    var next = root.selectedIndex + delta * root.columns
    if (next < 0 || next >= root.windows.length) return
    root.selectedIndex = next
    grid.positionViewAtIndex(next, GridView.Contain)
  }

  function setFilter(text) {
    root.sticky = true
    root.filterText = text
    root.selectedIndex = 0
  }

  // Sent by a Hyprland release bind on Alt, so it works before the overlay owns the keyboard.
  function altReleased(arg) {
    if (!root.opened) { root.earlyRelease = Date.now(); return }
    if (root.sticky) return
    if (!root.loaded) { root.releaseQueued = true; return }
    root.commit()
  }

  function commit() {
    root.activate(root.windows[root.selectedIndex])
  }

  function activate(win) {
    root.close()
    if (win) Quickshell.execDetached(Model.activateCommand(win, root.restoreWorkspaceId()))
  }

  function closeWindow(win) {
    if (!win) return
    Quickshell.execDetached(Model.closeCommand(win))
    // Keep the overlay open for the next pick, even if Alt is still held.
    root.sticky = true
    root.allWindows = root.allWindows.filter(function(w) { return w.address !== win.address })
    if (root.allWindows.length === 0) { root.close(); return }
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.windows.length - 1))
  }

  function applySnapshot(text) {
    var snapshot = Model.parseSnapshot(text)
    if (!root.opened) return
    if (!snapshot.loaded) { root.close(); return }

    root.allWindows = snapshot.windows
    root.selectedIndex = Model.wrap(root.pendingSteps, root.windows.length)
    root.pendingSteps = 0
    root.loaded = true

    if (root.releaseQueued) root.commit()
  }

  Process {
    id: snapshotProc
    command: Model.SNAPSHOT_COMMAND
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applySnapshot(text)
    }
  }

  // Brings back the most recently minimized window.
  function restoreLast(arg) {
    if (!restoreProc.running) restoreProc.running = true
  }

  Process {
    id: restoreProc
    command: Model.SNAPSHOT_COMMAND
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parked = Model.minimizedWindows(Model.parseSnapshot(text).windows)
        if (parked.length > 0) root.activate(parked[0])
      }
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  PanelWindow {
    id: panel
    visible: root.opened && root.loaded
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-window-switcher"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    onVisibleChanged: if (visible) {
      pointerGate.reset()
      Qt.callLater(function() { keyCatcher.forceActiveFocus() })
    }

    Rectangle {
      anchors.fill: parent
      color: root.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    BorderSurface {
      id: card
      width: root.columns * root.cellWidth + root.contentMargin * 2 + Style.space(8)
      height: root.headerHeight + root.footerHeight + root.gridHeight + root.contentSpacing * 2 + root.contentMargin * 2 + Style.space(4)
      radius: root.cornerRadius
      anchors.centerIn: parent
      color: root.background
      borderSpec: root.borderSpec
      padding: root.contentMargin

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true

        Keys.priority: Keys.BeforeItem
        Keys.onReleased: function(event) {
          if (event.key === Qt.Key_Alt && !event.isAutoRepeat) {
            root.altReleased("")
            event.accepted = true
          }
        }
        Keys.onPressed: function(event) {
          var key = event.key
          if (key === Qt.Key_Escape) {
            if (root.filterText) root.setFilter("")
            else root.close()
          } else if (key === Qt.Key_Tab) {
            root.step(1)
          } else if (key === Qt.Key_Backtab) {
            root.step(-1)
          } else if (key === Qt.Key_Right) {
            root.step(1)
          } else if (key === Qt.Key_Left) {
            root.step(-1)
          } else if (key === Qt.Key_Down) {
            root.moveRows(1)
          } else if (key === Qt.Key_Up) {
            root.moveRows(-1)
          } else if (key === Qt.Key_Home) {
            root.selectedIndex = 0
            grid.positionViewAtIndex(0, GridView.Contain)
          } else if (key === Qt.Key_End) {
            root.selectedIndex = Math.max(0, root.windows.length - 1)
            grid.positionViewAtIndex(root.selectedIndex, GridView.Contain)
          } else if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            root.commit()
          } else if (key === Qt.Key_Delete) {
            root.closeWindow(root.windows[root.selectedIndex])
          } else if (Util.editsFilter(event, root.filterText)) {
            root.setFilter(Util.editedFilter(event, root.filterText))
          } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32
                     && event.text.charCodeAt(0) !== 127
                     && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
            root.setFilter(root.filterText + event.text)
          } else {
            return
          }
          event.accepted = true
        }
      }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        spacing: root.contentSpacing

        Item {
          width: parent.width
          height: root.headerHeight

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.right: countLabel.left
            anchors.rightMargin: root.contentSpacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.filterText || "Type to filter windows…"
            color: root.foreground
            opacity: root.filterText ? 1 : 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.heading
            elide: Text.ElideRight
          }

          Text {
            id: countLabel
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.windows.length === 1 ? "1 window" : root.windows.length + " windows"
            color: root.foreground
            opacity: 0.58
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        Item {
          width: parent.width
          height: root.gridHeight

          GridView {
            id: grid
            anchors.fill: parent
            model: root.windows
            cellWidth: root.cellWidth
            cellHeight: root.cellHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height

            delegate: Item {
              id: cell
              required property int index
              required property var modelData

              readonly property bool selected: index === root.selectedIndex
              readonly property var toplevel: modelData.minimized ? null : root.toplevelFor(modelData.address)

              width: GridView.view.cellWidth
              height: GridView.view.cellHeight

              Rectangle {
                anchors.fill: parent
                anchors.margins: Style.space(4)
                radius: root.cornerRadius
                color: cell.selected ? root.selectedBackground : "transparent"
                border.width: cell.selected ? 2 : 0
                border.color: Commons.Color.accent

                Column {
                  anchors.fill: parent
                  anchors.margins: Style.space(8)
                  spacing: Style.space(6)

                  Rectangle {
                    id: preview
                    width: parent.width
                    height: root.previewHeight
                    radius: Math.max(0, root.cornerRadius - 2)
                    color: Util.alpha(root.foreground, 0.08)
                    clip: true
                    opacity: cell.modelData.minimized ? 0.55 : 1

                    ScreencopyView {
                      id: capture
                      captureSource: cell.toplevel
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
                      appClass: cell.modelData.cls
                      visible: !capture.hasContent
                    }
                  }

                  Row {
                    width: parent.width
                    height: root.labelHeight
                    spacing: Style.space(8)

                    WindowIcon {
                      width: Style.space(28)
                      height: width
                      anchors.verticalCenter: parent.verticalCenter
                      appClass: cell.modelData.cls
                    }

                    Column {
                      width: parent.width - Style.space(36)
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: cell.modelData.title || cell.modelData.cls
                        color: cell.selected ? root.selectedText : root.foreground
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: cell.modelData.cls + "  ·  " + Model.workspaceLabel(cell.modelData)
                        color: root.foreground
                        opacity: 0.6
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPositionChanged: function(mouse) {
                    if (pointerGate.moved(cell, mouse)) root.selectedIndex = cell.index
                  }
                  onClicked: root.activate(cell.modelData)
                }

                Rectangle {
                  id: closeButton
                  width: Style.space(24)
                  height: width
                  radius: Math.min(root.cornerRadius, width / 2)
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: Style.space(12)
                  visible: cell.selected || cellHover.hovered || closeMouse.containsMouse
                  color: closeMouse.containsMouse ? Commons.Color.urgent : Util.alpha(root.background, 0.85)
                  border.width: 1
                  border.color: Util.alpha(root.foreground, 0.3)

                  Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "✕"
                    color: closeMouse.containsMouse ? Commons.Color.background : root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  MouseArea {
                    id: closeMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeWindow(cell.modelData)
                  }
                }

                HoverHandler { id: cellHover }
              }
            }
          }

          Text {
            visible: root.windows.length === 0
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: root.filterText ? "No windows match “" + root.filterText + "”" : "No windows"
            color: root.foreground
            opacity: 0.7
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
          }
        }

        Text {
          width: parent.width
          height: root.footerHeight
          textFormat: Text.PlainText
          text: "Tab / arrows  select   ·   type  filter   ·   Enter  switch   ·   Del / ✕  close   ·   Esc  cancel"
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          color: root.foreground
          opacity: 0.5
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
