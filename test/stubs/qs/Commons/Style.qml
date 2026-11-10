pragma Singleton
import QtQuick

QtObject {
  property var font: ({
    family: "monospace",
    caption: 12,
    bodySmall: 13,
    body: 14,
    subtitle: 16,
    display: 22
  })
  property var spacing: ({ controlPaddingY: 4 })
  property int cornerRadius: 6
  function space(n) { return n }
  function selectedFillFor(fg, accent) { return Qt.rgba(accent.r, accent.g, accent.b, 0.28) }
  function hoverFillFor(fg, accent) { return Qt.rgba(fg.r, fg.g, fg.b, 0.12) }
}
