import QtQuick
import "Model.js" as Model

// Sparkline / chart line. Pure geometry comes from Model so the paint
// handler only strokes the path.
Canvas {
  id: canvas
  property var series: []
  property color lineColor: "white"
  property real lineWidth: 1.5
  property real pad: 2
  property bool fill: false
  property var referenceValue: null

  onSeriesChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onReferenceValueChanged: requestPaint()
  onWidthChanged: requestPaint()
  onHeightChanged: requestPaint()

  onPaint: {
    var ctx = getContext("2d")
    ctx.reset()
    var pts = Model.seriesPoints(canvas.series, canvas.width, canvas.height, canvas.pad)
    if (pts.length < 2) return

    if (canvas.fill) {
      var gradient = ctx.createLinearGradient(0, 0, 0, canvas.height)
      gradient.addColorStop(0, Qt.rgba(canvas.lineColor.r, canvas.lineColor.g, canvas.lineColor.b, 0.28))
      gradient.addColorStop(1, Qt.rgba(canvas.lineColor.r, canvas.lineColor.g, canvas.lineColor.b, 0.0))
      ctx.fillStyle = gradient
      ctx.beginPath()
      ctx.moveTo(pts[0].x, canvas.height)
      for (var f = 0; f < pts.length; f++) ctx.lineTo(pts[f].x, pts[f].y)
      ctx.lineTo(pts[pts.length - 1].x, canvas.height)
      ctx.closePath()
      ctx.fill()
    }

    var refY = Model.valueToY(canvas.referenceValue, Model.seriesBounds(canvas.series), canvas.height, canvas.pad)
    if (refY !== null) {
      ctx.strokeStyle = Qt.rgba(canvas.lineColor.r, canvas.lineColor.g, canvas.lineColor.b, 0.35)
      ctx.lineWidth = 1
      ctx.setLineDash([3, 3])
      ctx.beginPath()
      ctx.moveTo(pts[0].x, refY)
      ctx.lineTo(pts[pts.length - 1].x, refY)
      ctx.stroke()
      ctx.setLineDash([])
    }

    ctx.strokeStyle = canvas.lineColor
    ctx.lineWidth = canvas.lineWidth
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.beginPath()
    ctx.moveTo(pts[0].x, pts[0].y)
    for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
    ctx.stroke()
  }
}
