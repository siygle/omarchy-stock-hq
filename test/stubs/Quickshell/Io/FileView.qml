import QtQuick

Item {
  property string path
  property bool watchChanges: false
  property bool printErrors: false
  property bool atomicWrites: false
  signal fileChanged
  signal loaded
  signal loadFailed
  function reload() {}
  function text() { return "" }
  function setText(value) {}
}
