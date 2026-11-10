import QtQuick

Rectangle {
  property color foreground: "white"
  implicitHeight: 1
  height: 1
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.2)
}
