import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Drawer {
    id: drawer
    edge: Qt.RightEdge
    modal: false
    interactive: true
    width: Math.min(500, parent ? parent.width * .45 : 500)
    height: parent ? parent.height : 800
    property var task: taskController.selectedDownload
    background: Rectangle { color: "#101C30"; border.color: "#2A4266"; border.width: 1 }
    function bytes(value) { if (!value || value <= 0) return "—"; var units = ["B", "KB", "MB", "GB", "TB"]; var i = 0; while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ } return value.toFixed(i === 0 ? 0 : 1) + " " + units[i] }
    function time(seconds) { if (!seconds || seconds <= 0) return "—"; var h = Math.floor(seconds / 3600); var m = Math.floor((seconds % 3600) / 60); return h > 0 ? h + "h " + m + "m" : m + "m" }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 22
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: drawer.task.name || qsTr("Download details"); elide: Text.ElideRight; color: "#F1F6FF"; font.pixelSize: 18; font.weight: Font.DemiBold }
            ToolButton { text: "×"; font.pixelSize: 22; onClicked: drawer.close() }
        }
        Label { Layout.fillWidth: true; text: drawer.task.url || ""; color: "#8391A8"; font.pixelSize: 11; elide: Text.ElideMiddle }
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            TabButton { text: qsTr("Overview") }
            TabButton { text: qsTr("Progress") }
            TabButton { text: qsTr("Source") }
            TabButton { text: qsTr("Logs") }
        }
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex
            Item {
                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: 20
                    rowSpacing: 16
                    Repeater {
                        model: [
                            [qsTr("Status"), drawer.task.status || "—"], [qsTr("Category"), drawer.task.category || "—"],
                            [qsTr("Downloaded"), drawer.bytes(drawer.task.downloadedBytes)], [qsTr("Total size"), drawer.bytes(drawer.task.sizeBytes)],
                            [qsTr("Speed"), drawer.bytes(drawer.task.speed) + "/s"], [qsTr("ETA"), drawer.time(drawer.task.eta)],
                            [qsTr("Connections"), drawer.task.connections || "—"], [qsTr("Segments"), (drawer.task.completedSegments || 0) + " / " + (drawer.task.totalSegments || 0)],
                            [qsTr("Retries"), drawer.task.retries || 0], [qsTr("Engine"), drawer.task.engine || "—"]
                        ]
                        delegate: ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 3
                            Label { text: modelData[0]; color: "#8492A8"; font.pixelSize: 11 }
                            Label { Layout.fillWidth: true; text: modelData[1]; color: "#DFE8F7"; font.pixelSize: 14; font.weight: Font.Medium; elide: Text.ElideRight }
                        }
                    }
                }
            }
            Item {
                ColumnLayout { anchors.fill: parent; spacing: 12
                    Label { text: qsTr("Live speed history"); color: "#DCE6F8"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    SpeedGraph { Layout.fillWidth: true; Layout.preferredHeight: 160; samples: taskController.speedSamples }
                    ProgressBar { Layout.fillWidth: true; from: 0; to: 1; value: drawer.task.progress || 0 }
                    Label { text: Math.round((drawer.task.progress || 0) * 100) + "%"; color: "#AAB8CC"; font.pixelSize: 12 }
                }
            }
            Item {
                ColumnLayout { anchors.fill: parent; spacing: 12
                    Label { text: qsTr("Source"); color: "#DCE6F8"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    TextArea { Layout.fillWidth: true; Layout.fillHeight: true; readOnly: true; text: drawer.task.url || ""; wrapMode: Text.Wrap; selectByMouse: true }
                    Label { text: qsTr("Save path"); color: "#8492A8"; font.pixelSize: 11 }
                    TextArea { Layout.fillWidth: true; Layout.preferredHeight: 52; readOnly: true; text: drawer.task.savePath || ""; wrapMode: Text.Wrap; selectByMouse: true }
                }
            }
            Item {
                ListView {
                    id: taskLogList
                    anchors.fill: parent
                    clip: true
                    model: taskController.logs
                    delegate: Label { required property var modelData; width: taskLogList.width; padding: 8; text: (modelData.timestamp || "") + "  " + (modelData.message || ""); wrapMode: Text.Wrap; color: modelData.level === "ERROR" ? "#FF8794" : "#B4C2D7"; font.pixelSize: 10; font.family: "monospace" }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            }
        }
        Label { visible: (drawer.task.errorMessage || "").length > 0; Layout.fillWidth: true; text: drawer.task.errorMessage || ""; wrapMode: Text.Wrap; color: "#FF8894"; font.pixelSize: 12 }
        RowLayout {
            Layout.fillWidth: true
            Button { text: qsTr("Open file"); enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.openFile(drawer.task.savePath) }
            Button { text: qsTr("Show folder"); enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.revealFile(drawer.task.savePath) }
            Item { Layout.fillWidth: true }
            Button { text: qsTr("Retry"); onClicked: taskController.retrySelected() }
        }
    }
}
