import QtQuick
import QtQuick.Controls

TextField {
    id: control

    property var theme: null
    property bool dark: true
    property string leadingGlyph: ""
    property string assistiveText: ""

    implicitHeight: 38
    leftPadding: leadingGlyph.length > 0 ? 34 : 12
    rightPadding: 12
    topPadding: 8
    bottomPadding: 8
    selectByMouse: true
    color: theme ? theme.textPrimary : "#F0F5FF"
    placeholderTextColor: theme ? theme.textMuted : "#71829B"
    font.pixelSize: theme ? theme.fontBody : 12
    Accessible.description: assistiveText

    Text {
        visible: control.leadingGlyph.length > 0
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        text: control.leadingGlyph
        color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.theme ? control.theme.textMuted : "#71829B")
        font.pixelSize: 14
        font.weight: Font.DemiBold
    }

    background: Rectangle {
        radius: theme ? theme.radiusSm : 7
        color: control.enabled ? (control.theme ? control.theme.surfaceSubtle : "#0E192B") : (control.dark ? "#111B2B" : "#EDF1F6")
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.hovered ? (control.theme ? control.theme.borderStrong : "#365579") : (control.theme ? control.theme.border : "#243651"))
        Behavior on border.color { ColorAnimation { duration: 120 } }
    }
}
