import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Compact appearance page opened from the gear. Text fields exist only while
// this page is loaded (the panel Loader gates that).
Column {
  id: page

  property var stocks: null

  // The page Loader destroys this item when the panel closes or another page
  // is shown. Clear the keyboard grab here; Quickshell 0.3.1's Loader has no
  // unloaded signal.
  Component.onDestruction: if (stocks) stocks.editing = false

  spacing: Style.space(8)
  width: parent ? parent.width : implicitWidth

  Row {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(8)

    Chip {
      stocks: page.stocks
      text: "‹ List"
      onClicked: page.stocks.showList()
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Settings"
      textFormat: Text.PlainText
      color: page.stocks.textColor
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.subtitle
      font.bold: true
    }
  }

  Flow {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(6)

    Text {
      text: "Theme"
      textFormat: Text.PlainText
      color: page.stocks.mutedForeground
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
    }
    Rectangle {
      width: page.stocks.fonts.body + 6
      height: page.stocks.fonts.body + 6
      radius: 3
      color: page.stocks.surfaceColor
      border.color: page.stocks.textColor
      border.width: 1
      visible: page.stocks.hasTheme
    }
    Rectangle {
      width: page.stocks.fonts.body + 6
      height: page.stocks.fonts.body + 6
      radius: 3
      color: page.stocks.upColor
      visible: page.stocks.hasTheme
    }
    Rectangle {
      width: page.stocks.fonts.body + 6
      height: page.stocks.fonts.body + 6
      radius: 3
      color: page.stocks.downColor
      visible: page.stocks.hasTheme
    }
    Text {
      text: page.stocks.themeStatus
      textFormat: Text.PlainText
      color: page.stocks.textColor
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
      elide: Text.ElideRight
      width: Math.min(implicitWidth, page.width - Style.space(160))
    }
  }

  Flow {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(4)

    Text {
      text: "Font"
      textFormat: Text.PlainText
      color: page.stocks.mutedForeground
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
    }

    Repeater {
      model: Model.FONT_FAMILY_PRESETS

      Chip {
        required property var modelData
        stocks: page.stocks
        text: modelData.label
        fontSize: page.stocks.fonts.caption
        selected: !page.stocks.customFontOpen && page.stocks.fontFamilySetting === modelData.id
        onClicked: page.stocks.selectFontFamily(modelData.id)
      }
    }

    Chip {
      stocks: page.stocks
      text: "Custom"
      fontSize: page.stocks.fonts.caption
      selected: page.stocks.customFontOpen
      onClicked: page.stocks.selectFontFamily("custom")
    }

    Loader {
      id: customFontLoader
      active: Model.customFontFieldLive(page.stocks.opened, page.stocks.view, page.stocks.customFontOpen)
      visible: active
      width: active ? Style.space(180) : 0
      height: item ? item.implicitHeight : 0
      sourceComponent: customFontField
    }
  }

  Flow {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(4)

    Text {
      text: "Size"
      textFormat: Text.PlainText
      color: page.stocks.mutedForeground
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
    }

    Repeater {
      model: page.sizeSteps

      Chip {
        required property int modelData
        stocks: page.stocks
        text: String(modelData)
        fontSize: modelData
        selected: page.stocks.fontSize === modelData
        onClicked: page.stocks.selectFontSize(modelData)
      }
    }
  }

  Row {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(6)

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "Refresh every"
      textFormat: Text.PlainText
      color: page.stocks.mutedForeground
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
    }
    Loader {
      id: refreshLoader
      active: Model.settingsFieldLive(page.stocks.opened, page.stocks.view, true)
      visible: active
      width: Style.space(48)
      height: item ? item.implicitHeight : 0
      sourceComponent: refreshField
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "minutes ⏎"
      textFormat: Text.PlainText
      color: page.stocks.mutedForeground
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
    }
  }

  Flow {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    spacing: Style.space(4)

    Text {
      text: "Watchlists"
      textFormat: Text.PlainText
      color: page.stocks.mutedForeground
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
    }
    Chip {
      stocks: page.stocks
      text: "Export"
      onClicked: page.stocks.requestExportWatchlists()
    }
    Chip {
      stocks: page.stocks
      text: "Import"
      onClicked: page.stocks.requestImportWatchlists()
    }
    Chip {
      stocks: page.stocks
      text: "Open JSON ↗"
      onClicked: page.stocks.openWatchlistsFile()
    }
  }

  Text {
    x: Style.space(8)
    width: parent.width - Style.space(16)
    textFormat: Text.PlainText
    text: page.stocks.fileDialogMessage !== "" ? page.stocks.fileDialogMessage : page.stocks.watchlistsPath
    elide: Text.ElideMiddle
    color: page.stocks.mutedForeground
    font.family: page.stocks.fontFamily
    font.pixelSize: page.stocks.fonts.caption
  }

  readonly property var sizeSteps: {
    var out = []
    for (var n = Model.FONT_SIZE_MIN; n <= Model.FONT_SIZE_MAX; n++) out.push(n)
    return out
  }

  Component {
    id: customFontField
    TextField {
      width: customFontLoader.width
      text: page.stocks.fontFamilySetting
      placeholderText: "Family name ⏎"
      foreground: page.stocks.textColor
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
      verticalPadding: Style.space(2)
      onTextChanged: if (text.length > 80) text = text.slice(0, 80)
      onActiveFocusChanged: page.stocks.editing = activeFocus
      onAccepted: {
        page.stocks.selectFontFamily(text)
        page.stocks.releaseInput()
      }
      Keys.onEscapePressed: page.stocks.releaseInput()
    }
  }

  Component {
    id: refreshField
    TextField {
      width: refreshLoader.width
      text: String(page.stocks.refreshMinutes)
      foreground: page.stocks.textColor
      font.family: page.stocks.fontFamily
      font.pixelSize: page.stocks.fonts.caption
      verticalPadding: Style.space(2)
      onActiveFocusChanged: page.stocks.editing = activeFocus
      onAccepted: {
        page.stocks.saveRefreshMinutes(text)
        page.stocks.releaseInput()
      }
      Keys.onEscapePressed: page.stocks.releaseInput()
    }
  }
}
