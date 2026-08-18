import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar entry for the Stocks widget: a text pill that mirrors the panel's
// cycling label. Panel plumbing follows omarchy.weather / omarchy.clock so
// `omarchy-shell shell summon|hide|toggle io.github.al1gat0r.stocks` route
// here through the bar's open/close/opened contract.
BarWidget {
  id: root
  moduleName: "io.github.al1gat0r.stocks"

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
  }

  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
  }

  function togglePanel() {
    if (panelLoader.item && panelLoader.item.toggle) panelLoader.item.toggle()
  }

  function nextSymbol() {
    if (panelLoader.item && panelLoader.item.stepSymbol) panelLoader.item.stepSymbol(1)
  }

  function prevSymbol() {
    if (panelLoader.item && panelLoader.item.stepSymbol) panelLoader.item.stepSymbol(-1)
  }

  // Shape contract for shell.summon/hide/toggle routing (the bar requires
  // open/close/opened on the bar-widget root).
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item && panelLoader.item.open) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item && panelLoader.item.close) panelLoader.item.close()
  }

  // Forwarded so this widget can stand in for the panel as the bar's popout
  // identity (Bar.requestPopout prefers closeForPopoutSwitch over close).
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property string pillText: panelLoader.item
    ? (root.vertical ? panelLoader.item.verticalText : panelLoader.item.label)
    : ""

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
    target: "io.github.al1gat0r.stocks"

    function refresh(): void { root.broadcast("refresh") }
    function next(): void { root.broadcast("nextSymbol") }
    function prev(): void { root.broadcast("prevSymbol") }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.togglePanel() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.pillText
    // Theme "urgent" color while the shown symbol is down; plain otherwise.
    active: panelLoader.item ? panelLoader.item.currentIsDown === true : false
    // The panel is the detail view, so no tooltip (as with omarchy.weather).
    tooltipText: ""

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else if (b === Qt.RightButton) root.nextSymbol()
      else root.togglePanel()
    }

    onWheelMoved: function(delta) {
      if (delta > 0) root.prevSymbol()
      else if (delta < 0) root.nextSymbol()
    }
  }
}
