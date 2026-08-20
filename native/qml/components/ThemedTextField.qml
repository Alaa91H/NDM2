import QtQuick
import QtQuick.Controls

TextField {
    id: control

    property var theme: null
    property bool dark: true
    property string leadingGlyph: ""
    property string assistiveText: ""

    implicitHeight: theme ? theme.touchHeight : 40
    leftPadding: leadingGlyph.length > 0 ? 38 : (theme ? theme.spaceMd : 12)
    rightPadding: theme ? theme.spaceMd : 12
    topPadding: 8
    bottomPadding: 8
    selectByMouse: true
    color: theme ? theme.textPrimary : "#FFFFFF"
    placeholderTextColor: theme ? theme.textMuted : "#A6A6A6"
    font.pixelSize: theme ? theme.fontBody : 13
    Accessible.description: assistiveText

    Text {
        visible: control.leadingGlyph.length > 0
        anchors.left: parent.left
        anchors.leftMargin: control.theme ? control.theme.spaceMd : 12
        anchors.verticalCenter: parent.verticalCenter
        text: control.leadingGlyph
        color: control.activeFocus ? (control.theme ? control.theme.focus : "#60CDFF") : (control.theme ? control.theme.textMuted : "#A6A6A6")
        font.pixelSize: 15
        font.weight: Font.DemiBold
    }

    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 6
        color: {
            if (!control.enabled) return control.theme ? control.theme.surfaceSubtle : "#252525"
            if (control.activeFocus) return control.theme ? control.theme.surface : "#292929"
            return control.hovered ? (control.theme ? control.theme.controlHover : "#454545") : (control.theme ? control.theme.controlFill : "#363636")
        }
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.focus : "#60CDFF") : (control.hovered ? (control.theme ? control.theme.borderStrong : "#626262") : (control.theme ? control.theme.border : "#454545"))
        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on border.color { ColorAnimation { duration: 100 } }
    }
}
