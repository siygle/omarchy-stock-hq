import QtQuick

Item {
  property bool blocked: false
  signal closeRequested
  signal activateRequested
  signal moveRequested(real dx, real dy)
  signal tabRequested(int direction)
  signal textKey(string text, int modifiers)
}
