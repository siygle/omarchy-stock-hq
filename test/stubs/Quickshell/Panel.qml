import QtQuick

Item {
  id: shellPanel
  property string moduleName
  property bool manageIpc: false
  property bool opened: false
  property color barForeground: "#dddddd"
  property var bar: null
  property var settings: ({})
  property var controller: shellController

  QtObject {
    id: shellController
    function show() {}
    function hide() {}
  }

  function setting(name, fallback) { return fallback }
}
