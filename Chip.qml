import QtQuick
import qs.Commons

// Small toggle-looking button used for range chips, the currency switch,
// sort headers and agent presets. Colors come from the owning Panel.
Rectangle {
  id: chip

  property var stocks: null
  property string text: ""
  property bool selected: false
  property bool active: true
  property int fontSize: Style.font.caption
  signal clicked(int button)

  readonly property color foreground: chip.stocks ? chip.stocks.barForeground : Color.foreground

  width: chipText.implicitWidth + Style.space(12)
  height: chipText.implicitHeight + Style.space(6)
  radius: Style.cornerRadius
  opacity: chip.active ? 1 : 0.45
  color: chip.selected
    ? Style.selectedFillFor(chip.foreground, Color.accent)
    : (chipMouse.containsMouse && chip.active ? Style.hoverFillFor(chip.foreground, Color.accent) : "transparent")

  Text {
    id: chipText
    anchors.centerIn: parent
    text: chip.text
    color: chip.selected ? chip.foreground : (chip.stocks ? chip.stocks.mutedForeground : chip.foreground)
    font.family: chip.stocks ? chip.stocks.fontFamily : Style.font.family
    font.pixelSize: chip.fontSize
    font.bold: chip.selected
  }

  MouseArea {
    id: chipMouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: chip.active ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: function(mouse) { if (chip.active) chip.clicked(mouse.button) }
  }
}
