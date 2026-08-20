import QtQuick
import QtQuick.Controls

Button {
    id: control

    property string glyph: ""
    property string accessibleLabel: text
    property string tone: "neutral" // neutral, accent, danger
    property bool dark: true
    property var theme: null

    implicitWidth: 34
    implicitHeight: 34
    padding: 0
    focusPolicy: Qt.StrongFocus
    Accessible.name: accessibleLabel
    ToolTip.text: accessibleLabel
    ToolTip.visible: hovered && accessibleLabel.length > 0

    contentItem: Text {
        text: control.glyph || control.text
        color: {
            if (!control.enabled)
                return control.theme ? control.theme.textMuted : "#71829B"
            if (control.tone === "accent")
                return "#FFFFFF"
            if (control.tone === "danger")
                return control.theme ? control.theme.danger : "#FF8493"
            return control.theme ? control.theme.textSecondary : "#9AABC3"
        }
        font.pixelSize: 16
        font.weight: Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }

    background: Rectangle {
        radius: theme ? theme.radiusSm : 8
        color: {
            if (!control.enabled)
                return "transparent"
            if (control.tone === "accent")
                return control.down ? (control.theme ? control.theme.accentHover : "#3D7FDD") : (control.theme ? control.theme.accent : "#5C9EFF")
            if (control.tone === "danger")
                return control.down ? (control.theme ? control.theme.dangerSoft : "#452431") : control.hovered ? (control.theme ? control.theme.dangerSoft : "#452431") : "transparent"
            return control.down ? (control.theme ? control.theme.selection : "#193A67") : control.hovered ? (control.theme ? control.theme.surfaceSubtle : "#0E192B") : "transparent"
        }
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : control.hovered && control.tone !== "accent" ? (control.theme ? control.theme.border : "#243651") : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
    }
}
