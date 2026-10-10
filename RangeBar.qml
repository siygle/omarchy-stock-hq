import QtQuick
import "Model.js" as Model

// Where `value` sits between `low` and `high`: a thin track, a tick for the
// optional reference (previous close) and a dot for the value.
Item {
  id: bar

  property var value: null
  property var low: null
  property var high: null
  property var reference: null
  property color trackColor: "gray"
  property color dotColor: "white"

  readonly property var position: Model.rangePosition(value, low, high)
  readonly property var referencePosition: reference === null || reference === undefined
    ? null : Model.rangePosition(reference, low, high)
  readonly property real dotSize: Math.max(5, Math.round(height * 0.55))

  implicitHeight: 10

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    x: bar.dotSize / 2
    width: Math.max(0, bar.width - bar.dotSize)
    height: 2
    radius: 1
    color: bar.trackColor
    visible: bar.position !== null
  }

  Rectangle {
    visible: bar.referencePosition !== null
    anchors.verticalCenter: parent.verticalCenter
    x: bar.dotSize / 2 + (bar.width - bar.dotSize) * (bar.referencePosition || 0) - width / 2
    width: 1
    height: bar.height
    color: bar.trackColor
  }

  Rectangle {
    visible: bar.position !== null
    anchors.verticalCenter: parent.verticalCenter
    x: (bar.width - bar.dotSize) * (bar.position || 0)
    width: bar.dotSize
    height: bar.dotSize
    radius: bar.dotSize / 2
    color: bar.dotColor
  }
}
