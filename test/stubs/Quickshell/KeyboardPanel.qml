import QtQuick

Item {
  property var anchorItem
  property var owner
  property var bar
  property bool open: false
  property var focusTarget
  property real contentWidth: 0
  property real contentHeight: 0
  property real availableCardHeight: 800
  property real verticalContentInset: 0
  function fittedContentWidth(fallback) { return fallback }
  function fittedContentHeight(fallback) { return fallback }
}
