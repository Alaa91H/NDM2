import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string title: qsTr("Nothing here yet")
    property string subtitle: qsTr("New downloads from the real NOVA core will appear here.")
    signal actionRequested()
    ColumnLayout {
        anchors.centerIn: parent; width: 420; spacing: 12
        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 68; height: 68; radius: 20; color: "#17243B"
            Text { anchors.centerIn: parent; text: "↓"; color: "#5B9CFF"; font.pixelSize: 34; font.weight: Font.Light }
        }
        Label { Layout.fillWidth: true; text: root.title; horizontalAlignment: Text.AlignHCenter; color: "#F3F7FF"; font.pixelSize: 20; font.weight: Font.DemiBold }
        Label { Layout.fillWidth: true; text: root.subtitle; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: "#8D9AB0"; font.pixelSize: 13; lineHeight: 1.35 }
        Button { Layout.alignment: Qt.AlignHCenter; text: qsTr("Add download"); onClicked: root.actionRequested(); contentItem: Text { text: parent.text; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.weight: Font.DemiBold } background: Rectangle { radius: 8; color: parent.hovered ? "#4F92FF" : "#3278E8" } }
    }
}
