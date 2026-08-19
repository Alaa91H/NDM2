import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout { Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 2; Label { text: qsTr("Browser integration"); color: root.textColor; font.pixelSize: 20; font.weight: Font.DemiBold } Label { text: qsTr("Uses the preserved NOVA browser-extension and native-messaging bridge; NDM2 opens no new network endpoint."); color: root.muted; font.pixelSize: 11; wrapMode: Text.Wrap } }
            Button { text: qsTr("Refresh status"); onClicked: taskController.refreshAll() }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 156; radius: 12; color: root.surface; border.color: "#233653"
            GridLayout { anchors.fill: parent; anchors.margins: 18; columns: 2; columnSpacing: 30; rowSpacing: 14
                Repeater { model: [[qsTr("Bridge status"), taskController.browserHealth.status || taskController.browserHealth.ok || qsTr("Unavailable")], [qsTr("Native messaging"), taskController.browserHealth.nativeMessaging || taskController.browserHealth.native_messaging || "—"], [qsTr("Extension version"), taskController.browserHealth.version || "—"], [qsTr("Core endpoint"), taskController.endpoint || "loopback"]]
                    delegate: ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 3; Label { text: modelData[0]; color: root.muted; font.pixelSize: 10 } Label { Layout.fillWidth: true; text: modelData[1]; color: root.textColor; font.pixelSize: 13; elide: Text.ElideRight } }
                }
            }
        }
        Label { Layout.fillWidth: true; text: qsTr("Browser configuration, installation and authentication remain owned by the existing secured NOVA extension/native-messaging flow. A live browser-handoff test requires installed browser profiles and is recorded as a manual release test."); wrapMode: Text.Wrap; color: root.muted; font.pixelSize: 11 }
    }
}
