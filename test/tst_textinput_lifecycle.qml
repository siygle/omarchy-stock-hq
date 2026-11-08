import QtQuick
import QtQuick.Controls
import QtTest
import "../Model.js" as Model

// Same gates as Panel.qml / QuoteTable.qml. Counts live TextField objects,
// which is what subscribes to the clipboard, after the panel and page change.
TestCase {
  id: harness
  name: "TextInputLifecycle"
  when: windowShown
  visible: true
  width: 320
  height: 240

  property bool opened: false
  property string page: "list"
  property bool settingsOpen: false

  function fieldNames(item, out) {
    if (!item) return
    if (item.echoMode !== undefined && item.objectName)
      out.push(item.objectName)
    var kids = item.children
    for (var i = 0; i < kids.length; i++)
      fieldNames(kids[i], out)
  }

  function names() {
    var out = []
    fieldNames(host, out)
    out.sort()
    return out.join(",")
  }

  Item {
    id: host
    anchors.fill: parent

    Loader {
      active: Model.listPageLive(harness.opened, harness.page)
      sourceComponent: listPage
    }
    Loader {
      active: Model.detailPageLive(harness.opened, harness.page)
      sourceComponent: detailPage
    }
  }

  Component {
    id: listPage
    Item {
      TextField { objectName: "listName" }
      TextField { objectName: "addSymbols" }
      Loader {
        active: Model.settingsFieldLive(harness.opened, harness.page, harness.settingsOpen)
        sourceComponent: refreshField
      }
    }
  }

  Component {
    id: refreshField
    TextField { objectName: "refreshMinutes" }
  }

  Component {
    id: detailPage
    Item {
      TextField { objectName: "agentPrompt" }
    }
  }

  function test_closedPanelHasNoTextFields() {
    opened = false
    page = "list"
    settingsOpen = true
    compare(names(), "")
  }

  function test_openListPageKeepsVisibleEditorsOnly() {
    opened = true
    page = "list"
    settingsOpen = false
    compare(names(), "addSymbols,listName")
  }

  function test_settingsFieldAppearsAndIsDestroyed() {
    opened = true
    page = "list"
    settingsOpen = true
    compare(names(), "addSymbols,listName,refreshMinutes")
    settingsOpen = false
    compare(names(), "addSymbols,listName")
  }

  function test_detailPageDestroysListFields() {
    opened = true
    page = "list"
    settingsOpen = true
    compare(names(), "addSymbols,listName,refreshMinutes")
    page = "detail"
    compare(names(), "agentPrompt")
  }

  function test_closingPanelDestroysTheActivePage() {
    opened = true
    page = "detail"
    compare(names(), "agentPrompt")
    opened = false
    compare(names(), "")
    page = "list"
    settingsOpen = true
    compare(names(), "")
  }
}
