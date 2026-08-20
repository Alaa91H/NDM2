import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root

    property color surface: "#292929"
    property color textColor: "#FFFFFF"
    property color muted: "#A6A6A6"
    property var theme: null
    signal addRequested()

    function numberValue(source, key, fallback) { return source && source[key] !== undefined ? source[key] : fallback }
    function queueState() { return taskController.queueEntries.length > 0 ? "active" : "idle" }

    ColumnLayout {
        anchors.fill: parent
        spacing: theme ? theme.spaceLg : 16

        SectionHeader { title: qsTr("Core queue"); subtitle: qsTr("Ordering, limits and scheduling remain controlled by NOVA Core."); actionText: qsTr("Refresh"); theme: root.theme; onActionRequested: taskController.refreshAll() }

        GridLayout {
            Layout.fillWidth: true
            columns: width < 720 ? 2 : 4
            columnSpacing: theme ? theme.spaceSm : 8
            rowSpacing: theme ? theme.spaceSm : 8
            Repeater {
                model: [
                    [qsTr("Active"), root.numberValue(taskController.queueSummary, "activeCount", root.numberValue(taskController.queueSummary, "active_count", 0)), "↓"],
                    [qsTr("Entries"), taskController.queueEntries.length, "≡"],
                    [qsTr("Bandwidth"), root.numberValue(taskController.queueSummary, "totalBandwidthKbps", root.numberValue(taskController.queueSummary, "total_bandwidth_kbps", 0)) + " KB/s", "↯"],
                    [qsTr("Next"), root.numberValue(taskController.queueSummary, "nextToStart", root.numberValue(taskController.queueSummary, "next_to_start", "—")) || "—", "→"]
                ]
                delegate: InfoCard {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 86
                    theme: root.theme
                    contentPadding: theme ? theme.spaceMd : 12
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: theme ? theme.radiusSm : 6; color: theme ? theme.accentSoft : "#17445D"; Text { anchors.centerIn: parent; text: modelData[2]; color: theme ? theme.accent : "#60CDFF"; font.pixelSize: 15; font.weight: Font.DemiBold } }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { text: modelData[0]; color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                            Label { Layout.fillWidth: true; text: modelData[1]; color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontMetric : 18; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }

        InfoCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            theme: root.theme
            contentPadding: theme ? theme.spaceSm : 8
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.theme ? root.theme.spaceXs : 4
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: root.theme ? root.theme.spaceSm : 8
                    Layout.rightMargin: root.theme ? root.theme.spaceSm : 8
                    Label { Layout.fillWidth: true; text: qsTr("Queue entries"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 15; font.weight: Font.DemiBold }
                    Label { text: qsTr("%1 reported by NOVA").arg(taskController.queueEntries.length); color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme ? root.theme.border : "#454545" }
                ListView {
                    id: queueList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: root.theme ? root.theme.spaceXs : 4
                    model: taskController.queueEntries
                    visible: count > 0
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: queueList.width
                        height: root.theme ? 58 : 64
                        radius: root.theme ? root.theme.radiusSm : 6
                        color: queueMouse.containsMouse ? (root.theme ? root.theme.surfaceHover : "#3A3A3A") : "transparent"
                        border.width: (taskController.selectedId === (modelData.taskId || modelData.task_id || modelData.id || "")) ? 1 : 0
                        border.color: root.theme ? root.theme.focus : "#60CDFF"
                        MouseArea { id: queueMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: taskController.selectedId = modelData.taskId || modelData.task_id || modelData.id || "" }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.theme ? root.theme.spaceMd : 12
                            anchors.rightMargin: root.theme ? root.theme.spaceMd : 12
                            spacing: root.theme ? root.theme.spaceSm : 8
                            Rectangle { Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: 14; color: root.theme ? root.theme.accentSoft : "#17445D"; Label { anchors.centerIn: parent; text: index + 1; color: root.theme ? root.theme.accent : "#60CDFF"; font.pixelSize: root.theme ? root.theme.fontCaption : 12; font.weight: Font.DemiBold } }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2
                                Label { Layout.fillWidth: true; text: modelData.taskId || modelData.task_id || modelData.id || qsTr("Core queue entry"); color: root.theme ? root.theme.textPrimary : root.textColor; elide: Text.ElideMiddle; font.pixelSize: root.theme ? root.theme.fontBody : 13; font.weight: Font.Medium }
                                Label { Layout.fillWidth: true; text: modelData.priority || modelData.status || qsTr("Reported by NOVA Core"); color: root.theme ? root.theme.textMuted : root.muted; elide: Text.ElideRight; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                            }
                            StatusBadge { status: modelData.status || root.queueState(); labelOverride: modelData.status || qsTr("In queue"); dark: settingsService.dark; theme: root.theme }
                            IconButton { glyph: "›"; accessibleLabel: qsTr("Select queue entry"); theme: root.theme; dark: settingsService.dark; onClicked: taskController.selectedId = modelData.taskId || modelData.task_id || modelData.id || "" }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
                EmptyState { Layout.fillWidth: true; Layout.fillHeight: true; visible: queueList.count === 0; title: taskController.connected ? qsTr("The Core queue is empty") : qsTr("Waiting for NOVA Core"); subtitle: taskController.connected ? qsTr("Add a download to let NOVA report the real queue state.") : taskController.lastError; state: taskController.connected ? "empty" : "offline"; actionText: taskController.connected ? qsTr("Add download") : qsTr("Refresh connection"); theme: root.theme; onActionRequested: taskController.connected ? root.addRequested() : taskController.refreshAll() }
            }
        }

        InfoCard {
            Layout.fillWidth: true
            theme: root.theme
            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label { text: qsTr("Queue priority"); color: root.theme ? root.theme.textPrimary : root.textColor; font.weight: Font.DemiBold; font.pixelSize: root.theme ? root.theme.fontBody : 13 }
                    Label { Layout.fillWidth: true; text: qsTr("Priority is sent through the existing NOVA Core bridge for the selected task."); color: root.theme ? root.theme.textSecondary : root.muted; wrapMode: Text.Wrap; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                }
                ThemedComboBox { id: priorityBox; model: [qsTr("Critical"), qsTr("High"), qsTr("Normal"), qsTr("Low"), qsTr("Background")]; currentIndex: 2; Layout.preferredWidth: 148; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Queue priority") }
                ActionButton { text: qsTr("Set priority"); tone: "secondary"; dark: settingsService.dark; theme: root.theme; enabled: taskController.selectedId.length > 0; onClicked: taskController.setSelectedPriority(priorityBox.currentIndex) }
            }
        }
    }
}
