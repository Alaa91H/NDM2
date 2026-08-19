import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    signal addRequested()

    function numberValue(source, key, fallback) { return source && source[key] !== undefined ? source[key] : fallback }
    ColumnLayout {
        anchors.fill: parent
        spacing: 16
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 3
                Label { text: qsTr("Core queue"); color: root.textColor; font.pixelSize: 20; font.weight: Font.DemiBold }
                Label { text: qsTr("The daemon remains the source of truth for ordering, limits and scheduling."); color: root.muted; font.pixelSize: 11 }
            }
            Button { text: qsTr("Refresh"); onClicked: taskController.refreshAll() }
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: [
                    [qsTr("Active"), root.numberValue(taskController.queueSummary, "activeCount", root.numberValue(taskController.queueSummary, "active_count", 0))],
                    [qsTr("Entries"), taskController.queueEntries.length],
                    [qsTr("Bandwidth"), root.numberValue(taskController.queueSummary, "totalBandwidthKbps", root.numberValue(taskController.queueSummary, "total_bandwidth_kbps", 0)) + " KB/s"],
                    [qsTr("Next"), root.numberValue(taskController.queueSummary, "nextToStart", root.numberValue(taskController.queueSummary, "next_to_start", "—")) || "—"]
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 74
                    radius: 10
                    color: Qt.rgba(1, 1, 1, .035)
                    border.color: Qt.rgba(1, 1, 1, .08)
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 4
                        Label { text: modelData[0]; color: root.muted; font.pixelSize: 10 }
                        Label { Layout.fillWidth: true; text: modelData[1]; color: root.textColor; font.pixelSize: 15; font.weight: Font.DemiBold; elide: Text.ElideRight }
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
                id: queueList
                anchors.fill: parent
                anchors.margins: 8
                clip: true
                model: taskController.queueEntries
                visible: count > 0
                delegate: Rectangle {
                    required property var modelData
                    width: queueList.width
                    height: 66
                    radius: 9
                    color: queueMouse.containsMouse ? "#192A45" : "transparent"
                    MouseArea { id: queueMouse; anchors.fill: parent; hoverEnabled: true }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 12
                        Label { Layout.preferredWidth: 32; text: index + 1; color: "#73AFFF"; font.pixelSize: 13; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Label { Layout.fillWidth: true; text: modelData.taskId || modelData.task_id || modelData.id || qsTr("Core queue entry"); color: root.textColor; elide: Text.ElideMiddle; font.pixelSize: 13; font.weight: Font.Medium }
                            Label { Layout.fillWidth: true; text: modelData.priority || modelData.status || qsTr("Reported by the core"); color: root.muted; elide: Text.ElideRight; font.pixelSize: 11 }
                        }
                        Button { text: qsTr("Select"); onClicked: { taskController.selectedId = modelData.taskId || modelData.task_id || modelData.id || "" } }
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
            EmptyState {
                anchors.fill: parent
                visible: queueList.count === 0
                title: qsTr("The core queue is empty")
                subtitle: qsTr("No client-side queue has been created. Add a download to let NOVA report the real queue state.")
                onActionRequested: root.addRequested()
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 88
            radius: 10
            color: Qt.rgba(1, 1, 1, .03)
            border.color: Qt.rgba(1, 1, 1, .08)
            RowLayout {
                anchors.fill: parent
                anchors.margins: 14
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3
                    Label { text: qsTr("Queue ordering"); color: root.textColor; font.weight: Font.DemiBold; font.pixelSize: 12 }
                    Label { Layout.fillWidth: true; text: qsTr("NDM2 exposes the live queue and priority bridge. Drag-and-drop is intentionally withheld until a confirmed daemon ordering route is available."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 10 }
                }
                ComboBox {
                    id: priorityBox
                    model: [qsTr("Critical"), qsTr("High"), qsTr("Normal"), qsTr("Low"), qsTr("Background")]
                    currentIndex: 2
                    Layout.preferredWidth: 130
                }
                Button { text: qsTr("Set priority"); enabled: taskController.selectedId.length > 0; onClicked: taskController.setSelectedPriority(priorityBox.currentIndex) }
            }
        }
    }
}
