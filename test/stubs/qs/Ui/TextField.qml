import QtQuick
import QtQuick.Controls as Controls

// Omarchy's qs.Ui.TextField adds the padding and color properties the shell
// theme uses. Stock Qt Quick Controls does not have them.
Controls.TextField {
  property int verticalPadding: 0
  property color foreground: color
}
