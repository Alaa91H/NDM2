import QtQuick
import QtQuick.Controls

Button {
    id: control
    property string tone: "secondary" // primary, secondary, danger, quiet
    property bool dark: true
    property var theme: null
    property color accent: theme ? theme.accent : "#5C9EFF"
    property color accentHover: theme ? theme.accentHover : "#78B1FF"
    property color borderColor: theme ? theme.border : "#243651"
    property color textColor: theme ? theme.textPrimary : "#F0F5FF"
    implicitHeight: 34
    leftPadding: 12
    rightPadding: 12
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    contentItem: Text {
        text: control.text
        color: control.tone === "primary" || control.tone === "danger" ? "#FFFFFF" : control.enabled ? control.textColor : control.dark ? "#61718A" : "#99A4B5"
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: 12
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }
    background: Rectangle {
        radius: 8
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? control.accent : control.tone === "quiet" ? "transparent" : control.borderColor
        color: {
            if (!control.enabled) return control.dark ? "#172235" : "#EEF2F7"
            if (control.tone === "primary") return control.down ? "#2D73D7" : control.hovered ? control.accentHover : control.accent
            if (control.tone === "danger") return control.down ? "#B92F45" : control.hovered ? "#E25269" : "#D93850"
            if (control.tone === "quiet") return control.down ? (control.dark ? "#203452" : "#DCEBFF") : control.hovered ? (control.dark ? "#1A2B45" : "#E6F0FF") : "transparent"
            return control.down ? (control.dark ? "#1B2B43" : "#E8EEF6") : control.hovered ? (control.dark ? "#1A2A42" : "#F3F7FB") : control.dark ? "#152238" : "#FFFFFF"
        }
    }
}
