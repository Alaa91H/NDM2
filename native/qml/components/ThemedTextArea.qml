import QtQuick
import QtQuick.Controls

TextArea {
    id: control

    property var theme: null
    property bool dark: true
    property bool monospace: false

    padding: theme ? theme.spaceMd : 12
    selectByMouse: true
    wrapMode: TextEdit.WrapAnywhere
    color: theme ? theme.textPrimary : "#FFFFFF"
    placeholderTextColor: theme ? theme.textMuted : "#A6A6A6"
    font.pixelSize: theme ? theme.fontCaption : 12
    font.family: monospace ? (theme ? theme.fontMono : "monospace") : ""

    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 6
        color: control.readOnly ? (control.theme ? control.theme.surfaceSubtle : "#252525") : (control.hovered ? (control.theme ? control.theme.controlHover : "#454545") : (control.theme ? control.theme.controlFill : "#363636"))
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.focus : "#60CDFF") : (control.theme ? control.theme.border : "#454545")
        Behavior on color { ColorAnimation { duration: 100 } }
    }
}
