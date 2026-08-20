import QtQuick
import QtQuick.Controls

Switch {
    id: control

    property var theme: null
    property bool dark: true

    spacing: theme ? theme.spaceSm : 8
    font.pixelSize: theme ? theme.fontBody : 12
    contentItem: Text {
        text: control.text
        color: control.enabled ? (control.theme ? control.theme.textPrimary : "#F0F5FF") : (control.theme ? control.theme.textMuted : "#71829B")
        verticalAlignment: Text.AlignVCenter
        leftPadding: control.indicator.width + control.spacing
        elide: Text.ElideRight
    }
    indicator: Rectangle {
        implicitWidth: 38
        implicitHeight: 22
        x: control.leftPadding
        y: parent.height / 2 - height / 2
        radius: height / 2
        color: control.checked ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.theme ? control.theme.borderStrong : "#365579")
        opacity: control.enabled ? 1 : .55
        Rectangle {
            width: 16
            height: 16
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            x: control.checked ? parent.width - width - 3 : 3
            color: "#FFFFFF"
            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        }
    }
}
