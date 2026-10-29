.pragma library

// Hyprland has no minimize, so a minimized window is parked on this special
// workspace. Nothing but this plugin shows it.
var MINIMIZED = "special:minimized"

var ADDRESS = /^0x[0-9a-f]+$/i

// Prints `hyprctl -j clients` on line one and `hyprctl -j activewindow` on line two.
var SNAPSHOT_COMMAND = ["bash", "-c", "hyprctl -j clients | tr -d '\\n'; echo; hyprctl -j activewindow | tr -d '\\n'; echo"]

function parseSnapshot(text) {
  var lines = String(text || "").split("\n")
  var clients
  try { clients = JSON.parse(lines[0]) } catch (e) { return { loaded: false, windows: [] } }
  if (!Array.isArray(clients)) return { loaded: false, windows: [] }

  var active = ""
  try { active = String(JSON.parse(lines[1] || "{}").address || "") } catch (e) {}

  var windows = []
  for (var i = 0; i < clients.length; i++) {
    var c = clients[i]
    if (!c || !c.mapped || !ADDRESS.test(String(c.address))) continue
    var title = String(c.title || "")
    var cls = String(c.class || c.initialClass || "")
    if (!cls && !title) continue
    var workspace = c.workspace ? String(c.workspace.name || "") : ""
    windows.push({
      address: String(c.address),
      cls: cls,
      title: title,
      workspace: workspace,
      minimized: workspace === MINIMIZED,
      active: String(c.address) === active,
      focusId: typeof c.focusHistoryID === "number" ? c.focusHistoryID : 9999
    })
  }

  // Most recently used first, like Alt+Tab elsewhere; minimized ones trail so
  // the first hop always lands on something visible.
  windows.sort(function(a, b) {
    if (a.active !== b.active) return a.active ? -1 : 1
    if (a.minimized !== b.minimized) return a.minimized ? 1 : -1
    return a.focusId - b.focusId
  })
  return { loaded: true, windows: windows }
}

function minimizedWindows(windows) {
  return windows.filter(function(w) { return w.minimized })
}

function workspaceLabel(win) {
  if (win.minimized) return "Minimized"
  if (win.workspace.indexOf("special:") === 0) return win.workspace.slice(8)
  return "Workspace " + win.workspace
}

// Every whitespace-separated word has to occur in the class, title or place.
function filterWindows(windows, query) {
  var words = String(query || "").toLowerCase().split(/\s+/).filter(function(w) { return w.length > 0 })
  if (words.length === 0) return windows
  return windows.filter(function(w) {
    var haystack = (w.cls + " " + w.title + " " + workspaceLabel(w)).toLowerCase()
    for (var i = 0; i < words.length; i++)
      if (haystack.indexOf(words[i]) < 0) return false
    return true
  })
}

function wrap(index, count) {
  if (count <= 0) return 0
  return ((index % count) + count) % count
}

function focusDispatch(address) {
  return 'hl.dsp.focus({ window = "address:' + address + '" })'
}

function moveDispatch(address, workspace) {
  return 'hl.dsp.window.move({ workspace = "' + workspace + '", follow = false, window = "address:' + address + '" })'
}

function closeDispatch(address) {
  return 'hl.dsp.window.close({ window = "address:' + address + '" })'
}

// Addresses come from hyprctl and are checked on parse; workspace is a number
// or "special:..." taken from the same source.
function dispatchCommand(dispatches) {
  var script = dispatches.map(function(_, i) { return 'hyprctl dispatch "$' + (i + 1) + '"' }).join(" && ")
  return ["bash", "-c", script, "_"].concat(dispatches)
}

function activateCommand(win, workspaceId) {
  if (win.minimized)
    return dispatchCommand([moveDispatch(win.address, String(workspaceId)), focusDispatch(win.address)])
  return dispatchCommand([focusDispatch(win.address)])
}

function closeCommand(win) {
  return dispatchCommand([closeDispatch(win.address)])
}
