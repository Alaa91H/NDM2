import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: control

    required property string label
    required property string glyph
    property bool selected: false
    property int count: 0
    property var theme: null

    implicitHeight: theme ? theme.touchHeight : 40
    leftPadding: theme ? theme.spaceSm : 8
    rightPadding: theme ? theme.spaceSm : 8
    focusPolicy: Qt.StrongFocus
    Accessible.name: label + (count > 0 ? qsTr(", %1 items").arg(count) : "")
    Accessible.description: selected ? qsTr("Current section") : qsTr("Open section")

    contentItem: RowLayout {
        spacing: control.theme ? control.theme.spaceSm : 8
        Rectangle { width: 3; height: 16; radius: 2; visible: control.selected; color: control.theme ? control.theme.accent : "#60CDFF" }
        Text { width: 20; text: control.glyph; color: control.selected ? (control.theme ? control.theme.accent : "#60CDFF") : (control.theme ? control.theme.textSecondary : "#D0D0D0"); font.pixelSize: 15; font.weight: control.selected ? Font.DemiBold : Font.Normal; horizontalAlignment: Text.AlignHCenter }
        Text { text: control.label; color: control.theme ? control.theme.textPrimary : "#FFFFFF"; font.pixelSize: control.theme ? control.theme.fontBody : 13; font.weight: control.selected ? Font.DemiBold : Font.Normal; elide: Text.ElideRight; Layout.fillWidth: true }
        Rectangle { visible: control.count > 0; width: Math.max(22, countText.implicitWidth + 10); height: 20; radius: 10; color: control.selected ? (control.theme ? control.theme.accent : "#60CDFF") : (control.theme ? control.theme.controlFill : "#363636"); Text { id: countText; anchors.centerIn: parent; text: control.count; color: control.selected ? "white" : (control.theme ? control.theme.textSecondary : "#D0D0D0"); font.pixelSize: 10; font.weight: Font.DemiBold } }
    }

    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 6
        border.width: control.activeFocus ? 2 : 0
        border.color: control.activeFocus ? (control.theme ? control.theme.focus : "#60CDFF") : "transparent"
        color: control.down ? (control.theme ? control.theme.surfacePressed : "#454545") : control.selected ? (control.theme ? control.theme.selection : "#1B5C7D") : control.hovered ? (control.theme ? control.theme.surfaceHover : "#3A3A3A") : "transparent"
        Behavior on color { ColorAnimation { duration: 100 } }
    }
}
