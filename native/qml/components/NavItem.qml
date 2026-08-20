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
    implicitHeight: 42
    leftPadding: 12
    rightPadding: 10
    focusPolicy: Qt.StrongFocus
    Accessible.name: label + (count > 0 ? qsTr(", %1 items").arg(count) : "")
    Accessible.description: selected ? qsTr("Current section") : qsTr("Open section")
    contentItem: RowLayout {
        spacing: control.theme ? control.theme.spaceSm : 8
        Text { width: 18; text: control.glyph; color: control.selected ? (control.theme ? control.theme.textPrimary : "#E9F0FF") : (control.theme ? control.theme.textSecondary : "#90A0B8"); font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter }
        Text { text: control.label; color: control.selected ? (control.theme ? control.theme.textPrimary : "#F3F7FF") : (control.theme ? control.theme.textSecondary : "#BAC5D8"); font.pixelSize: 13; font.weight: control.selected ? Font.DemiBold : Font.Normal }
        Item { width: 1; height: 1; Layout.fillWidth: true }
        Rectangle { visible: control.count > 0; width: Math.max(22, countText.implicitWidth + 10); height: 20; radius: 10; color: control.selected ? (control.theme ? control.theme.accent : "#3B82F6") : (control.theme ? control.theme.surfaceSubtle : "#293750")
            Text { id: countText; anchors.centerIn: parent; text: control.count; color: control.theme ? control.theme.textPrimary : "#E7EEFF"; font.pixelSize: 10; font.weight: Font.DemiBold }
        }
    }
    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 9
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : "transparent"
        color: control.down ? (control.theme ? control.theme.accentSoft : "#1E3353") : control.selected ? (control.theme ? control.theme.selection : "#1D3152") : control.hovered ? (control.theme ? control.theme.surfaceSubtle : "#17243B") : "transparent"
    }
}
