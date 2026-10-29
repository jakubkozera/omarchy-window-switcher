import QtQuick
import Quickshell

Image {
  id: root

  property string appClass: ""

  readonly property var entry: appClass ? DesktopEntries.heuristicLookup(appClass) : null

  function themed(name) {
    if (!name) return ""
    if (name.charAt(0) === "/") return "file://" + name
    return Quickshell.iconPath(name, true)
  }

  source: themed(entry ? entry.icon : "")
    || themed(appClass.toLowerCase())
    || Quickshell.iconPath("application-x-executable", true)
  sourceSize: Qt.size(width * 2, height * 2)
  fillMode: Image.PreserveAspectFit
  asynchronous: true
  smooth: true
}
