import QtQuick
import QtQuick.Controls

TextArea {
    id: control

    property var theme: null
    property bool dark: true
    property bool monospace: false

    padding: 10
    selectByMouse: true
    wrapMode: TextEdit.WrapAnywhere
    color: theme ? theme.textPrimary : "#F0F5FF"
    placeholderTextColor: theme ? theme.textMuted : "#71829B"
    font.pixelSize: theme ? theme.fontCaption : 11
    font.family: monospace ? (theme ? theme.fontMono : "monospace") : font.family

    background: Rectangle {
        radius: theme ? theme.radiusSm : 7
        color: control.readOnly ? (control.theme ? control.theme.surfaceSubtle : "#0E192B") : (control.theme ? control.theme.surfaceRaised : "#172741")
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.theme ? control.theme.border : "#243651")
    }
}
