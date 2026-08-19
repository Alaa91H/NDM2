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
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Label { text: qsTr("Core diagnostics"); color: root.textColor; font.pixelSize: 20; font.weight: Font.DemiBold }
                Label { text: qsTr("Live session statistics and daemon log records."); color: root.muted; font.pixelSize: 11 }
            }
            Button { text: qsTr("Refresh"); onClicked: taskController.refreshAll() }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: [
                    [qsTr("Active"), taskController.statistics.activeDownloads || 0],
                    [qsTr("Completed"), taskController.statistics.totalCompleted || 0],
                    [qsTr("Failed"), taskController.statistics.totalFailed || 0],
                    [qsTr("Downloaded"), Math.round((taskController.statistics.totalDownloadedBytes || 0) / 1048576) + " MB"]
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 72
                    radius: 10
                    color: Qt.rgba(1, 1, 1, .035)
                    border.color: Qt.rgba(1, 1, 1, .08)
                    ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 4
                        Label { text: modelData[0]; color: root.muted; font.pixelSize: 10 }
                        Label { text: modelData[1]; color: root.textColor; font.pixelSize: 16; font.weight: Font.DemiBold }
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 12
            color: root.surface
            border.color: "#233653"
            ListView {
                id: logList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                model: taskController.logs
                visible: count > 0
                delegate: Rectangle {
                    required property var modelData
                    width: logList.width
                    height: logText.implicitHeight + 20
                    color: "transparent"
                    Label {
                        id: logText
                        anchors.fill: parent
                        anchors.margins: 10
                        text: (modelData.timestamp || "") + "  " + (modelData.level || "INFO") + "  " + (modelData.message || "")
                        color: modelData.level === "ERROR" ? "#FF8794" : modelData.level === "WARN" ? "#FFBE69" : "#B4C2D7"
                        wrapMode: Text.Wrap
                        font.family: "monospace"
                        font.pixelSize: 11
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
            Label { anchors.centerIn: parent; visible: logList.count === 0; text: qsTr("No daemon logs were returned."); color: root.muted; font.pixelSize: 13 }
        }
    }
}
