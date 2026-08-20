import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    property var theme: null
    property bool dark: theme ? theme.dark : true
    spacing: 8
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    indicator: Rectangle {
        implicitWidth: 17
        implicitHeight: 17
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        radius: 4
        color: control.checked ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.theme ? control.theme.surfaceRaised : "#152238")
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.theme ? control.theme.borderStrong : "#365579")
        Text { anchors.centerIn: parent; visible: control.checked; text: "✓"; color: "white"; font.pixelSize: 11; font.weight: Font.DemiBold }
    }
    contentItem: Text {
        text: control.text
        color: control.enabled ? (control.theme ? control.theme.textPrimary : "#F0F5FF") : (control.dark ? "#61718A" : "#99A4B5")
        font: control.font
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
        elide: Text.ElideRight
    }
}
