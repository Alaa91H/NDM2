import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Button {
    id: control
    required property string label
    required property string glyph
    property bool selected: false
    property int count: 0
    implicitHeight: 42
    leftPadding: 12
    rightPadding: 10
    contentItem: RowLayout {
        spacing: 10
        Text { width: 18; text: control.glyph; color: control.selected ? "#E9F0FF" : "#90A0B8"; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter }
        Text { text: control.label; color: control.selected ? "#F3F7FF" : "#BAC5D8"; font.pixelSize: 13; font.weight: control.selected ? Font.DemiBold : Font.Normal }
        Item { width: 1; height: 1; Layout.fillWidth: true }
        Rectangle { visible: control.count > 0; width: Math.max(22, countText.implicitWidth + 10); height: 20; radius: 10; color: control.selected ? "#3B82F6" : "#293750"
            Text { id: countText; anchors.centerIn: parent; text: control.count; color: "#E7EEFF"; font.pixelSize: 11; font.weight: Font.DemiBold }
        }
    }
    background: Rectangle { radius: 9; color: control.down ? "#1E3353" : control.selected ? "#1D3152" : control.hovered ? "#17243B" : "transparent" }
}
