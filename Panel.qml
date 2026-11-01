pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "zmnatza.web-search"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property string barIcon: "󰍋"
  property string previousQuery: ""
  property bool busy: false

  property var engines: [
    { id: "google",       label: "Google",         prefix: "https://www.google.com/search?q=",          icon: 0xF1A0 },
    { id: "chatgpt",      label: "ChatGPT",        prefix: "https://chatgpt.com/?q=",                   icon: 0xEC81, verb: "Ask" },
    { id: "claude",       label: "Claude",         prefix: "https://claude.ai/new?q=",                  icon: 0xEC82, verb: "Ask" },
    { id: "bing",         label: "Bing",           prefix: "https://www.bing.com/search?q=",            icon: 0xF00A4 },
    { id: "duckduckgo",   label: "DuckDuckGo",     prefix: "https://duckduckgo.com/?q=",                icon: 0xF01E5 },
    { id: "github",       label: "GitHub",         prefix: "https://github.com/search?q=",              icon: 0xF09B },
    { id: "wikipedia",    label: "Wikipedia",      prefix: "https://en.wikipedia.org/w/index.php?search=", icon: 0xF266 },
    { id: "youtube",      label: "YouTube",        prefix: "https://www.youtube.com/results?search_query=", icon: 0xF167 },
    { id: "reddit",       label: "Reddit",         prefix: "https://www.reddit.com/search/?q=",         icon: 0xF1A1 },
    { id: "stackoverflow",label: "Stack Overflow", prefix: "https://stackoverflow.com/search?q=",        icon: 0xF16C, abbr: "Stack" }
  ]
  property string defaultEngine: "google"
  property string openShortcut: "SUPER + ALT + P"

  property int currentEngineIndex: -1
  readonly property var currentEngine: {
    if (currentEngineIndex >= 0 && currentEngineIndex < engines.length)
      return engines[currentEngineIndex]
    return engines[0]
  }

  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property color contentDim: Qt.darker(contentForeground, 1.55)
  readonly property color contentAccent: Color.accent
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family

  // The engine grid is a fixed five-across block: every tile shares one
  // width derived from the panel's inner width, so the two rows line up
  // no matter how the theme scales spacing or fonts.
  readonly property int engineColumns: 5
  readonly property int engineGap: Style.space(6)
  readonly property int engineTileHeight: Style.space(52)

  function indexOfEngine(id) {
    for (var i = 0; i < engines.length; i++)
      if (engines[i].id === id) return i
    return -1
  }

  function glyph(cp) {
    if (!isFinite(cp)) cp = 0xF002
    if (cp >= 0x10000) {
      var v = cp - 0x10000
      return String.fromCharCode(0xD800 + (v >> 10)) + String.fromCharCode(0xDC00 + (v & 0x3FF))
    }
    return String.fromCharCode(cp)
  }

  function shortcutLabel() {
    var tokens = String(root.openShortcut || "SUPER + ALT + P").split("+")
    var out = []
    for (var i = 0; i < tokens.length; i++) {
      var t = tokens[i].trim()
      var u = t.toUpperCase()
      if (u === "SUPER") out.push("Super")
      else if (u === "CTRL" || u === "CONTROL") out.push("Ctrl")
      else if (u === "ALT") out.push("Alt")
      else if (u === "SHIFT") out.push("Shift")
      else out.push(u === "SPACE" ? "Space" : t)
    }
    return out.join("+")
  }

  // Engine records injected by the bar widget may predate the optional
  // display fields, so every reader goes through a fallback.
  function engineLabel(engine) {
    return engine && engine.label ? engine.label : ""
  }

  function engineAbbr(engine) {
    return engine && engine.abbr ? engine.abbr : engineLabel(engine)
  }

  function engineVerb(engine) {
    return engine && engine.verb ? engine.verb : "Search"
  }

  function engineMeta(engine) {
    if (!engine) return ""
    return engineVerb(engine) === "Ask"
      ? "Asking " + engineLabel(engine)
      : "Searching with " + engineLabel(engine)
  }

  function enginePrompt(engine) {
    if (!engine) return "Search the web…"
    return engineVerb(engine) + " " + engineLabel(engine) + "…"
  }

  function shortcutFor(index) {
    if (index < 0 || index > 9) return ""
    return "Ctrl+" + (index === 9 ? "0" : (index + 1))
  }

  function resolveDefaultEngine() {
    var idx = indexOfEngine(root.defaultEngine)
    if (idx < 0) idx = indexOfEngine("google")
    if (idx < 0) idx = 0
    root.currentEngineIndex = idx
  }

  function selectEngine(index) {
    if (index >= 0 && index < engines.length) {
      root.currentEngineIndex = index
      queryField.forceActiveFocus()
    }
  }

  function open() {
    queryField.text = root.previousQuery
    queryField.selectAll()
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) queryField.forceActiveFocus()
    })
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function runSearch() {
    var raw = queryField.text.trim()
    if (root.busy) return
    if (raw.length === 0) {
      queryField.forceActiveFocus()
      return
    }

    root.previousQuery = raw
    var engine = root.currentEngine
    var url = (engine ? engine.prefix : "") + encodeURIComponent(raw)
    root.busy = true
    Quickshell.execDetached(["omarchy", "launch", "browser", url])
    root.busy = false
    root.close()
    queryField.text = ""
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: queryField
    centerOnBar: false
    contentWidth: panel.fittedContentWidth(Style.space(520))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      anchors.fill: parent
      blocked: queryField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(14)

        // The hero icon is the selected engine, not a generic magnifier —
        // the header then answers "where is this going?" at a glance.
        PanelHero {
          id: hero
          title: "Web Search"
          meta: root.engineMeta(root.currentEngine)
          detail: root.shortcutFor(root.currentEngineIndex)
          foreground: root.contentForeground
          fontFamily: root.contentFontFamily

          iconComponent: Component {
            Item {
              implicitWidth: Style.font.display
              implicitHeight: Style.font.display

              OpticalGlyph {
                anchors.fill: parent
                text: root.glyph(root.currentEngine ? root.currentEngine.icon : 0xF002)
                fontFamily: root.contentFontFamily
                fontSize: Style.font.display
                color: root.contentForeground
              }
            }
          }
        }

        TextField {
          id: queryField
          width: parent.width
          placeholderText: root.enginePrompt(root.currentEngine)
          maximumLength: 500
          foreground: root.contentForeground
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.subtitle
          verticalPadding: Style.space(9)
          // Reserve the gutters the leading magnifier and the trailing
          // submit affordance are drawn into.
          leftPadding: Style.space(34)
          rightPadding: Style.space(34)
          onAccepted: root.runSearch()
          Keys.onEscapePressed: root.close()

          Keys.onPressed: function(event) {
            if ((event.modifiers & Qt.ControlModifier) === 0) return
            var idx = -1
            if (event.key === Qt.Key_0) idx = 9
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) idx = event.key - Qt.Key_1
            if (idx >= 0 && idx < root.engines.length) {
              root.selectEngine(idx)
              event.accepted = true
            }
          }

          Text {
            textFormat: Text.PlainText
            x: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: root.barIcon
            color: queryField.activeFocus ? root.contentForeground : root.contentDim
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body

            Behavior on color {
              ColorAnimation { duration: 120 }
            }
          }

          Text {
            id: submitHint
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            text: "󰌑"
            color: root.contentForeground
            opacity: queryField.text.length > 0 ? 1.0 : 0.3
            font.family: root.contentFontFamily
            font.pixelSize: Style.font.body

            Behavior on opacity {
              NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
            }

            MouseArea {
              id: submitMouse
              anchors.fill: parent
              anchors.margins: -Style.space(6)
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.runSearch()
            }

            PanelToolTip {
              visible: submitMouse.containsMouse
              text: "Open the results"
              fontFamily: root.contentFontFamily
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: "SEARCH ENGINE"
            foreground: root.contentForeground
            fontFamily: root.contentFontFamily
          }

          Grid {
            id: engineGrid
            width: parent.width
            columns: root.engineColumns
            spacing: root.engineGap

            readonly property int tileWidth: Math.max(
              Style.space(28),
              Math.floor((width - root.engineGap * (root.engineColumns - 1)) / root.engineColumns))

            Repeater {
              model: root.engines

              delegate: CursorSurface {
                id: tile
                required property var modelData
                required property int index
                readonly property bool selected: index === root.currentEngineIndex
                property bool hovered: false

                width: engineGrid.tileWidth
                height: root.engineTileHeight
                foreground: root.contentForeground
                accent: root.contentAccent
                hasCursor: hovered
                current: selected
                // CursorSurface leaves idle rows transparent; the grid reads
                // better as a block of tiles, so idle keeps the normal fill.
                color: hovered ? fill : (selected ? currentFill : Style.normalFillFor(root.contentForeground, root.contentAccent))

                HoverHandler {
                  onHoveredChanged: tile.hovered = hovered
                  cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                  onTapped: root.selectEngine(tile.index)
                }

                Text {
                  textFormat: Text.PlainText
                  x: Style.space(6)
                  y: Style.space(5)
                  text: tile.index === 9 ? "0" : (tile.index + 1)
                  color: tile.selected ? root.contentForeground : root.contentDim
                  opacity: tile.selected ? 0.9 : 0.6
                  font.family: root.contentFontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }

                Column {
                  anchors.centerIn: parent
                  anchors.verticalCenterOffset: -Style.space(2)
                  spacing: Style.space(3)

                  OpticalGlyph {
                    anchors.horizontalCenter: parent.horizontalCenter
                    implicitWidth: Style.font.iconLarge
                    implicitHeight: Style.font.iconLarge
                    text: root.glyph(tile.modelData.icon)
                    fontFamily: root.contentFontFamily
                    fontSize: Style.font.iconLarge
                    color: tile.selected || tile.hovered ? root.contentForeground : root.contentDim
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.max(0, tile.width - Style.space(8))
                    text: root.engineAbbr(tile.modelData)
                    color: tile.selected || tile.hovered ? root.contentForeground : root.contentDim
                    font.family: root.contentFontFamily
                    font.pixelSize: Style.font.caption
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                  }
                }

                // Accent underline that grows in on the active engine, so the
                // selection survives a theme whose selected-fill is subtle.
                Rectangle {
                  anchors.horizontalCenter: parent.horizontalCenter
                  anchors.bottom: parent.bottom
                  anchors.bottomMargin: Style.space(6)
                  width: tile.selected ? Style.space(14) : 0
                  height: Math.max(1, Style.space(2))
                  radius: height / 2
                  color: root.contentAccent

                  Behavior on width {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                  }
                }

                PanelToolTip {
                  visible: tile.hovered
                  text: root.engineLabel(tile.modelData) + " · " + root.shortcutFor(tile.index)
                  fontFamily: root.contentFontFamily
                }
              }
            }
          }
        }

        PanelSeparator {
          foreground: root.contentForeground
        }

        // One row rather than a Flow or Grid: the gaps absorb whatever
        // width is left over, so the legend spreads across the panel and
        // never wraps or orphans a hint when the theme rescales fonts.
        Row {
          id: legend
          width: parent.width

          readonly property int hintsWidth: openHint.implicitWidth + enterHint.implicitWidth
            + engineHint.implicitWidth + escHint.implicitWidth

          spacing: Math.max(Style.space(8),
                            Math.floor((width - hintsWidth) / 3))

          KeyHint { id: openHint; keys: root.shortcutLabel(); label: "open anywhere" }
          KeyHint { id: enterHint; keys: "Enter"; label: "search" }
          KeyHint { id: engineHint; keys: "Ctrl+0–9"; label: "pick engine" }
          KeyHint { id: escHint; keys: "Esc"; label: "close" }
        }
      }
    }
  }

  // Keycap plus caption, the panel's footer legend. Row positioners own the
  // x axis only, so the caption matches the cap's height instead of
  // anchoring into the positioner.
  component KeyHint: Row {
    id: hint

    property string keys: ""
    property string label: ""

    spacing: Style.space(6)

    BorderSurface {
      id: cap
      implicitWidth: capText.implicitWidth + Style.space(12)
      implicitHeight: capText.implicitHeight + Style.space(6)
      color: Style.normalFillFor(root.contentForeground, root.contentAccent)
      borderSpec: Border.controlSpec("normal", root.contentForeground, root.contentAccent)
      radius: Style.cornerRadius

      Text {
        id: capText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: hint.keys
        color: root.contentForeground
        font.family: root.contentFontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    Text {
      textFormat: Text.PlainText
      height: cap.implicitHeight
      verticalAlignment: Text.AlignVCenter
      text: hint.label
      color: root.contentDim
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.caption
    }
  }

  onDefaultEngineChanged: resolveDefaultEngine()
  onEnginesChanged: resolveDefaultEngine()

  Component.onCompleted: {
    if (engines.length > 0) resolveDefaultEngine()
  }
}
