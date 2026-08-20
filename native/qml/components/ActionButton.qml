import QtQuick
import QtQuick.Controls

Button {
    id: control

    property string tone: "secondary" // primary, secondary, danger, quiet
    property bool dark: true
    property var theme: null
    property color accent: theme ? theme.accent : "#60CDFF"
    property color accentHover: theme ? theme.accentHover : "#8CDBFF"
    property color borderColor: theme ? theme.border : "#454545"
    property color textColor: theme ? theme.textPrimary : "#FFFFFF"

    implicitHeight: theme ? theme.controlHeight : 32
    implicitWidth: Math.max(84, contentItem.implicitWidth + leftPadding + rightPadding)
    leftPadding: theme ? theme.spaceMd : 12
    rightPadding: theme ? theme.spaceMd : 12
    focusPolicy: Qt.StrongFocus
    Accessible.name: text
    Accessible.role: Accessible.Button

    contentItem: Text {
        text: control.text
        color: {
            if (!control.enabled) return control.theme ? control.theme.textMuted : "#A6A6A6"
            return control.tone === "primary" || control.tone === "danger" ? "#FFFFFF" : control.textColor
        }
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.pixelSize: control.theme ? control.theme.fontBody : 13
        font.weight: Font.DemiBold
        elide: Text.ElideRight
    }

    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 6
        border.width: control.activeFocus ? 2 : (control.tone === "quiet" ? 0 : 1)
        border.color: control.activeFocus ? (control.theme ? control.theme.focus : control.accent) : control.tone === "quiet" ? "transparent" : control.borderColor
        color: {
            if (!control.enabled) return control.theme ? control.theme.surfaceSubtle : "#252525"
            if (control.tone === "primary") return control.down ? (control.theme ? control.theme.accentPressed : "#3AAAE0") : control.hovered ? control.accentHover : control.accent
            if (control.tone === "danger") return control.down ? (control.theme ? "#A42618" : "#A42618") : control.hovered ? (control.theme ? "#E16A76" : "#E16A76") : (control.theme ? control.theme.danger : "#C42B1C")
            if (control.tone === "quiet") return control.down ? (control.theme ? control.theme.surfacePressed : "#454545") : control.hovered ? (control.theme ? control.theme.surfaceHover : "#3A3A3A") : "transparent"
            return control.down ? (control.theme ? control.theme.controlPressed : "#505050") : control.hovered ? (control.theme ? control.theme.controlHover : "#454545") : (control.theme ? control.theme.controlFill : "#363636")
        }
        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on border.color { ColorAnimation { duration: 100 } }
    }
}
