import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    property var theme: null
    signal addRequested()
    function numberValue(source, key, fallback) { return source && source[key] !== undefined ? source[key] : fallback }
    function queueState() { return taskController.queueEntries.length > 0 ? "active" : "idle" }
    ColumnLayout {
        anchors.fill: parent
        spacing: theme ? theme.spaceMd : 16
        SectionHeader { title: qsTr("Core queue"); subtitle: qsTr("NOVA remains the source of truth for ordering, limits and scheduling."); actionText: qsTr("Refresh"); theme: root.theme; onActionRequested: taskController.refreshAll() }
        RowLayout {
            Layout.fillWidth: true
            spacing: theme ? theme.spaceSm : 12
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
                    Layout.preferredHeight: 78
                    radius: theme ? theme.radiusMd : 10
                    color: theme ? theme.surfaceSubtle : Qt.rgba(1, 1, 1, .035)
                    border.color: theme ? theme.border : Qt.rgba(1, 1, 1, .08)
                    ColumnLayout { anchors.fill: parent; anchors.margins: theme ? theme.spaceMd : 12; spacing: 4
                        Label { text: modelData[0]; color: root.muted; font.pixelSize: theme ? theme.fontMeta : 10 }
                        Label { Layout.fillWidth: true; text: modelData[1]; color: root.textColor; font.pixelSize: theme ? theme.fontBodyLarge : 15; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: theme ? theme.radiusLg : 12
            color: root.surface
            border.color: theme ? theme.border : "#233653"
            ListView {
                id: queueList
                anchors.fill: parent
                anchors.margins: theme ? theme.spaceSm : 8
                clip: true
                model: taskController.queueEntries
                visible: count > 0
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: queueList.width
                    height: 68
                    radius: theme ? theme.radiusSm : 9
                    color: queueMouse.containsMouse ? (theme ? theme.surfaceSubtle : "#192A45") : "transparent"
                    MouseArea { id: queueMouse; anchors.fill: parent; hoverEnabled: true; onClicked: taskController.setSelectedId(modelData.taskId || modelData.task_id || modelData.id || "") }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: theme ? theme.spaceMd : 14
                        anchors.rightMargin: theme ? theme.spaceMd : 14
                        spacing: theme ? theme.spaceMd : 12
                        Rectangle { Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14; color: theme ? theme.accentSoft : "#1D3458"; Label { anchors.centerIn: parent; text: index + 1; color: theme ? theme.information : "#73AFFF"; font.pixelSize: theme ? theme.fontCaption : 13; font.weight: Font.DemiBold } }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Label { Layout.fillWidth: true; text: modelData.taskId || modelData.task_id || modelData.id || qsTr("Core queue entry"); color: root.textColor; elide: Text.ElideMiddle; font.pixelSize: theme ? theme.fontBody : 13; font.weight: Font.Medium }
                            Label { Layout.fillWidth: true; text: modelData.priority || modelData.status || qsTr("Reported by the Core"); color: root.muted; elide: Text.ElideRight; font.pixelSize: theme ? theme.fontCaption : 11 }
                        }
                        StatusBadge { status: modelData.status || root.queueState(); labelOverride: modelData.status || qsTr("In queue"); dark: settingsService.dark; theme: root.theme }
                        ActionButton { text: qsTr("Select"); tone: "quiet"; dark: settingsService.dark; theme: root.theme; onClicked: taskController.setSelectedId(modelData.taskId || modelData.task_id || modelData.id || "") }
                    }
                }
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
            }
            EmptyState { anchors.fill: parent; visible: queueList.count === 0; title: taskController.connected ? qsTr("The Core queue is empty") : qsTr("Waiting for NOVA Core"); subtitle: taskController.connected ? qsTr("Add a download to let NOVA report the real queue state.") : taskController.lastError; state: taskController.connected ? "empty" : "offline"; actionText: taskController.connected ? qsTr("Add download") : qsTr("Refresh connection"); theme: root.theme; onActionRequested: taskController.connected ? root.addRequested() : taskController.refreshAll() }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 92
            radius: theme ? theme.radiusMd : 10
            color: theme ? theme.surfaceSubtle : Qt.rgba(1, 1, 1, .03)
            border.color: theme ? theme.border : Qt.rgba(1, 1, 1, .08)
            RowLayout { anchors.fill: parent; anchors.margins: theme ? theme.spaceMd : 14; spacing: theme ? theme.spaceMd : 12
                ColumnLayout { Layout.fillWidth: true; spacing: 3
                    Label { text: qsTr("Queue priority"); color: root.textColor; font.weight: Font.DemiBold; font.pixelSize: theme ? theme.fontBody : 12 }
                    Label { Layout.fillWidth: true; text: qsTr("Reordering is withheld until NOVA exposes a confirmed ordering route. Priority is sent through the existing Core bridge."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: theme ? theme.fontCaption : 10 }
                }
                ComboBox { id: priorityBox; model: [qsTr("Critical"), qsTr("High"), qsTr("Normal"), qsTr("Low"), qsTr("Background")]; currentIndex: 2; Layout.preferredWidth: 130; Accessible.name: qsTr("Queue priority") }
                ActionButton { text: qsTr("Set priority"); tone: "secondary"; dark: settingsService.dark; theme: root.theme; enabled: taskController.selectedId.length > 0; onClicked: taskController.setSelectedPriority(priorityBox.currentIndex) }
            }
        }
    }
}
