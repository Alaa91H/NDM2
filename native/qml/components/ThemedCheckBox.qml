import QtQuick
import QtQuick.Controls

CheckBox {
    id: control

    property var theme: null
    property bool dark: theme ? theme.dark : true

    spacing: theme ? theme.spaceSm : 8
    implicitHeight: theme ? theme.controlHeight : 32
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    Accessible.role: Accessible.CheckBox

    indicator: Rectangle {
        implicitWidth: 18
        implicitHeight: 18
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        radius: control.theme ? control.theme.radiusXs : 4
        color: control.checked ? (control.theme ? control.theme.accent : "#60CDFF") : (control.hovered ? (control.theme ? control.theme.controlHover : "#454545") : (control.theme ? control.theme.controlFill : "#363636"))
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.focus : "#60CDFF") : (control.checked ? "transparent" : (control.theme ? control.theme.borderStrong : "#626262"))
        Text { anchors.centerIn: parent; visible: control.checked; text: "✓"; color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold }
        Behavior on color { ColorAnimation { duration: 100 } }
    }
    contentItem: Text {
        text: control.text
        color: control.enabled ? (control.theme ? control.theme.textPrimary : "#FFFFFF") : (control.theme ? control.theme.textMuted : "#A6A6A6")
        font.pixelSize: control.theme ? control.theme.fontBody : 13
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
        elide: Text.ElideRight
    }
}
