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
        spacing: 16
        RowLayout { Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 3; Label { text: qsTr("Core diagnostics"); color: root.textColor; font.pixelSize: 20; font.weight: Font.DemiBold } Label { text: qsTr("Live NOVA health, engine metadata, logs and selected task trace."); color: root.muted; font.pixelSize: 11 } }
            ComboBox { id: levelSelector; model: ["trace", "debug", "info", "warn", "error"]; currentIndex: Math.max(0, model.indexOf(taskController.logLevel)); onActivated: taskController.setLogLevel(currentText) }
            Button { text: qsTr("Refresh"); onClicked: taskController.refreshAll() }
        }
        GridLayout { Layout.fillWidth: true; columns: 4; columnSpacing: 12; rowSpacing: 12
            Repeater { model: [[qsTr("Core"), taskController.health.status || (taskController.connected ? qsTr("Online") : qsTr("Offline"))], [qsTr("Version"), taskController.health.version || "—"], [qsTr("Active"), taskController.statistics.activeDownloads || 0], [qsTr("Queue"), taskController.queueEntries.length], [qsTr("Bandwidth"), (taskController.bandwidth.globalLimitKbps || taskController.bandwidth.global_limit_kbps || 0) + " KB/s"], [qsTr("Profile"), taskController.activeProfile || "—"], [qsTr("Completed"), taskController.statistics.totalCompleted || 0], [qsTr("Failed"), taskController.statistics.totalFailed || 0]]
                delegate: Rectangle { required property var modelData; Layout.fillWidth: true; Layout.preferredHeight: 68; radius: 10; color: Qt.rgba(1,1,1,.035); border.color: Qt.rgba(1,1,1,.08); ColumnLayout { anchors.fill: parent; anchors.margins: 11; spacing: 3; Label { text: modelData[0]; color: root.muted; font.pixelSize: 10 } Label { Layout.fillWidth: true; text: modelData[1]; color: root.textColor; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight } } }
            }
        }
        SplitView { Layout.fillWidth: true; Layout.fillHeight: true; orientation: Qt.Horizontal
            Rectangle { SplitView.preferredWidth: parent.width * .58; color: root.surface; radius: 12; border.color: "#233653"
                ListView { id: logList; anchors.fill: parent; anchors.margins: 8; clip: true; model: taskController.logs
                    delegate: Label { required property var modelData; width: logList.width; padding: 9; text: (modelData.timestamp || "") + "  " + (modelData.level || "INFO") + "  " + (modelData.message || ""); color: modelData.level === "ERROR" ? "#FF8794" : modelData.level === "WARN" ? "#FFBE69" : "#B4C2D7"; wrapMode: Text.Wrap; font.family: "monospace"; font.pixelSize: 10 }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            }
            Rectangle { SplitView.preferredWidth: parent.width * .42; color: root.surface; radius: 12; border.color: "#233653"
                ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 8
                    Label { text: qsTr("Selected task trace"); color: root.textColor; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Label { Layout.fillWidth: true; text: taskController.selectedDownload.name || qsTr("Select a task in the library to request its Core trace."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 10 }
                    TextArea { Layout.fillWidth: true; Layout.fillHeight: true; readOnly: true; selectByMouse: true; text: Object.keys(taskController.taskTrace).length > 0 ? JSON.stringify(taskController.taskTrace, null, 2) : qsTr("No task trace was returned by the Core."); wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 10 }
                }
            }
        }
    }
}
