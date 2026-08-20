import QtQuick
import QtQuick.Controls

Button {
    id: control

    property string glyph: ""
    property string accessibleLabel: text
    property string tone: "neutral" // neutral, accent, danger
    property bool dark: true
    property var theme: null

    implicitWidth: theme ? theme.controlHeight : 32
    implicitHeight: theme ? theme.controlHeight : 32
    padding: 0
    focusPolicy: Qt.StrongFocus
    Accessible.name: accessibleLabel
    Accessible.role: Accessible.Button
    ToolTip.text: accessibleLabel
    ToolTip.visible: hovered && accessibleLabel.length > 0
    ToolTip.delay: 500

    contentItem: Text {
        text: control.glyph || control.text
        color: {
            if (!control.enabled) return control.theme ? control.theme.textMuted : "#A6A6A6"
            if (control.tone === "accent") return "#FFFFFF"
            if (control.tone === "danger") return control.theme ? control.theme.danger : "#C42B1C"
            return control.theme ? control.theme.textPrimary : "#FFFFFF"
        }
        font.pixelSize: 16
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 6
        color: {
            if (!control.enabled) return "transparent"
            if (control.tone === "accent") return control.down ? (control.theme ? control.theme.accentPressed : "#3AAAE0") : control.hovered ? (control.theme ? control.theme.accentHover : "#8CDBFF") : (control.theme ? control.theme.accent : "#60CDFF")
            if (control.tone === "danger") return control.down ? (control.theme ? control.theme.dangerSoft : "#4C252A") : control.hovered ? (control.theme ? control.theme.dangerSoft : "#4C252A") : "transparent"
            return control.down ? (control.theme ? control.theme.surfacePressed : "#454545") : control.hovered ? (control.theme ? control.theme.surfaceHover : "#3A3A3A") : "transparent"
        }
        border.width: control.activeFocus ? 2 : 0
        border.color: control.activeFocus ? (control.theme ? control.theme.focus : "#60CDFF") : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }
}
