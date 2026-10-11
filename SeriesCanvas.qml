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
  // Technical overlays (detail chart): a moving-average line and dashed
  // support / resistance levels.
  property var overlaySeries: []
  property color overlayColor: "gray"
  property var supportValue: null
  property var resistanceValue: null
  property color supportColor: "green"
  property color resistanceColor: "red"

  onSeriesChanged: requestPaint()
  onLineColorChanged: requestPaint()
  onReferenceValueChanged: requestPaint()
  onOverlaySeriesChanged: requestPaint()
  onSupportValueChanged: requestPaint()
  onResistanceValueChanged: requestPaint()
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

    function drawHorizontal(value, color) {
      var y = Model.valueToY(value, Model.seriesBounds(canvas.series), canvas.height, canvas.pad)
      if (y === null) return
      ctx.strokeStyle = Qt.rgba(color.r, color.g, color.b, 0.45)
      ctx.lineWidth = 1
      ctx.setLineDash([4, 4])
      ctx.beginPath()
      ctx.moveTo(pts[0].x, y)
      ctx.lineTo(pts[pts.length - 1].x, y)
      ctx.stroke()
      ctx.setLineDash([])
    }

    drawHorizontal(canvas.supportValue, canvas.supportColor)
    drawHorizontal(canvas.resistanceValue, canvas.resistanceColor)

    ctx.strokeStyle = canvas.lineColor
    ctx.lineWidth = canvas.lineWidth
    ctx.lineJoin = "round"
    ctx.lineCap = "round"
    ctx.beginPath()
    ctx.moveTo(pts[0].x, pts[0].y)
    for (var i = 1; i < pts.length; i++) ctx.lineTo(pts[i].x, pts[i].y)
    ctx.stroke()

    // Overlay shares the main series' time and value axes.
    var overlay = canvas.overlaySeries || []
    if (overlay.length >= 2) {
      var bounds = Model.seriesBounds(canvas.series)
      var t0 = canvas.series[0].t
      var span = canvas.series[canvas.series.length - 1].t - t0
      var innerW = canvas.width - canvas.pad * 2
      ctx.strokeStyle = Qt.rgba(canvas.overlayColor.r, canvas.overlayColor.g, canvas.overlayColor.b, 0.9)
      ctx.lineWidth = 1.1
      ctx.setLineDash([2, 2])
      ctx.beginPath()
      var started = false
      for (var o = 0; o < overlay.length; o++) {
        var y = Model.valueToY(overlay[o].c, bounds, canvas.height, canvas.pad)
        if (y === null) continue
        var x = span > 0 ? canvas.pad + ((overlay[o].t - t0) / span) * innerW : canvas.pad
        if (!started) { ctx.moveTo(x, y); started = true }
        else ctx.lineTo(x, y)
      }
      if (started) ctx.stroke()
      ctx.setLineDash([])
    }
  }
}
