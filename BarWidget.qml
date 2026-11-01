import QtQuick
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "zmnatza.web-search"

  readonly property string barIcon: setting("icon", "󰍋")
  readonly property string defaultEngine: setting("defaultEngine", "google")
  readonly property string openShortcut: setting("openShortcut", "SUPER + ALT + P")

  readonly property var builtinEngines: [
    { id: "google",       label: "Google",         prefix: "https://www.google.com/search?q=",          icon: 0xF1A0 },
    { id: "chatgpt",      label: "ChatGPT",        prefix: "https://chatgpt.com/?q=",                   icon: 0xEC81, verb: "Ask" },
    { id: "claude",       label: "Claude",         prefix: "https://claude.ai/new?q=",                  icon: 0xEC82, verb: "Ask" },
    { id: "bing",         label: "Bing",           prefix: "https://www.bing.com/search?q=",            icon: 0xF00A4 },
    { id: "duckduckgo",   label: "DuckDuckGo",     prefix: "https://duckduckgo.com/?q=",               icon: 0xF01E5 },
    { id: "github",       label: "GitHub",         prefix: "https://github.com/search?q=",              icon: 0xF09B },
    { id: "wikipedia",    label: "Wikipedia",      prefix: "https://en.wikipedia.org/w/index.php?search=", icon: 0xF266 },
    { id: "youtube",      label: "YouTube",        prefix: "https://www.youtube.com/results?search_query=", icon: 0xF167 },
    { id: "reddit",       label: "Reddit",         prefix: "https://www.reddit.com/search/?q=",         icon: 0xF1A1 },
    { id: "stackoverflow",label: "Stack Overflow", prefix: "https://stackoverflow.com/search?q=",        icon: 0xF16C, abbr: "Stack" }
  ]

  // Arrays from shell.json reach the widget as Qt list objects, for which
  // Array.isArray() is false, so copy any list-like value into a real array.
  function toArray(v) {
    var out = []
    if (v === undefined || v === null || typeof v === "string") return out
    var n = Number(v.length)
    if (!isFinite(n)) return out
    for (var i = 0; i < n; i++) out.push(v[i])
    return out
  }

  // shell.json can customize the list per widget entry:
  //   "extraEngines":  [{ "id", "label", "prefix", "icon"?, "verb"?, "after"? }]
  //   "hiddenEngines": ["engine-id", ...]
  // "icon" is a Nerd Font glyph or a code point; "after" inserts the engine
  // after that engine id (default: appended). Extra engines with an existing
  // id replace the built-in one.
  readonly property var engines: {
    var hidden = setting("hiddenEngines", [])
    var extras = setting("extraEngines", [])
    var list = []
    for (var i = 0; i < builtinEngines.length; i++) list.push(builtinEngines[i])
    hidden = toArray(hidden)
    extras = toArray(extras)
    for (var e = 0; e < extras.length; e++) {
      var x = extras[e]
      if (!x || !x.id || !x.label || !x.prefix) continue
      var icon = x.icon
      if (typeof icon === "string" && icon.length > 0) icon = icon.codePointAt(0)
      var entry = { id: String(x.id), label: String(x.label), prefix: String(x.prefix),
                    icon: isFinite(icon) && icon !== undefined ? Number(icon) : 0xF002 }
      if (x.verb) entry.verb = String(x.verb)
      if (x.abbr) entry.abbr = String(x.abbr)
      var existing = -1
      for (var j = 0; j < list.length; j++) if (list[j].id === entry.id) existing = j
      if (existing >= 0) list.splice(existing, 1)
      var at = list.length
      if (x.after) {
        for (var k = 0; k < list.length; k++) if (list[k].id === x.after) at = k + 1
      }
      list.splice(at, 0, entry)
    }
    return list.filter(function(en) { return hidden.indexOf(en.id) < 0 })
  }

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.engines = root.engines
    panelLoader.item.defaultEngine = root.defaultEngine
    panelLoader.item.openShortcut = root.openShortcut
    panelLoader.item.barIcon = root.barIcon
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    tooltipText: "Web search — click to enter a query"
    horizontalMargin: 8.75
    verticalPadding: 8.75

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}
