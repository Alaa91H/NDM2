import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property string title: qsTr("Nothing here yet")
    property string subtitle: qsTr("New downloads from the real NOVA Core will appear here.")
    property string state: "empty"
    property string actionText: qsTr("Add download")
    property bool showAction: true
    property var theme: null
    signal actionRequested()
    function glyph() { return state === "loading" ? "…" : state === "error" ? "!" : state === "offline" ? "×" : "↓" }
    function tone() { return state === "error" || state === "offline" ? "danger" : "primary" }
    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(440, parent ? parent.width - 48 : 440)
        spacing: theme ? theme.spaceMd : 12
        Rectangle { Layout.alignment: Qt.AlignHCenter; width: 68; height: 68; radius: theme ? theme.radiusLg : 20; color: root.state === "error" || root.state === "offline" ? (theme ? theme.dangerSoft : "#351F30") : (theme ? theme.accentSoft : "#17243B")
            Text { anchors.centerIn: parent; text: root.glyph(); color: root.state === "error" || root.state === "offline" ? (theme ? theme.danger : "#FF8794") : (theme ? theme.accent : "#5B9CFF"); font.pixelSize: 34; font.weight: Font.DemiBold }
        }
        Label { Layout.fillWidth: true; text: root.title; horizontalAlignment: Text.AlignHCenter; color: theme ? theme.textPrimary : "#F3F7FF"; font.pixelSize: theme ? theme.fontSection : 20; font.weight: Font.DemiBold; Accessible.name: text }
        Label { Layout.fillWidth: true; text: root.subtitle; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter; color: theme ? theme.textSecondary : "#8D9AB0"; font.pixelSize: theme ? theme.fontBody : 13; lineHeight: 1.35 }
        ActionButton { visible: root.showAction && root.actionText.length > 0; Layout.alignment: Qt.AlignHCenter; text: root.actionText; tone: root.tone(); dark: theme ? theme.dark : true; theme: root.theme; Accessible.name: root.actionText; onClicked: root.actionRequested() }
    }
}
