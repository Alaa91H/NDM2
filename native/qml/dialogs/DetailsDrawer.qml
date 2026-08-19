import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Drawer {
    id: drawer
    edge: Qt.RightEdge
    modal: false
    width: Math.min(540, parent ? parent.width * .47 : 540)
    height: parent ? parent.height : 800
    property var task: taskController.selectedDownload
    background: Rectangle { color: "#101C30"; border.color: "#2A4266"; border.width: 1 }
    function bytes(value) { if (!value || value <= 0) return "—"; var units = ["B", "KB", "MB", "GB", "TB"]; var i = 0; while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ } return value.toFixed(i === 0 ? 0 : 1) + " " + units[i] }
    function time(seconds) { if (!seconds || seconds <= 0) return "—"; var h = Math.floor(seconds / 3600); var m = Math.floor((seconds % 3600) / 60); return h > 0 ? h + "h " + m + "m" : m + "m" }
    ColumnLayout { anchors.fill: parent; anchors.margins: 20; spacing: 12
        RowLayout { Layout.fillWidth: true; Label { Layout.fillWidth: true; text: drawer.task.name || qsTr("Download details"); elide: Text.ElideRight; color: "#F1F6FF"; font.pixelSize: 18; font.weight: Font.DemiBold } ToolButton { text: "×"; font.pixelSize: 22; onClicked: drawer.close() } }
        Label { Layout.fillWidth: true; text: drawer.task.url || ""; color: "#8391A8"; font.pixelSize: 11; elide: Text.ElideMiddle }
        TabBar { id: tabBar; Layout.fillWidth: true; TabButton { text: qsTr("Overview") } TabButton { text: qsTr("Speed") } TabButton { text: qsTr("File") } TabButton { text: qsTr("Mirrors") } TabButton { text: qsTr("Logs") } }
        StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: tabBar.currentIndex
            Item { GridLayout { anchors.fill: parent; columns: 2; columnSpacing: 18; rowSpacing: 13
                Repeater { model: [[qsTr("Status"), drawer.task.status || "—"], [qsTr("Category"), drawer.task.category || "—"], [qsTr("Downloaded"), drawer.bytes(drawer.task.downloadedBytes)], [qsTr("Total size"), drawer.bytes(drawer.task.sizeBytes)], [qsTr("Speed"), drawer.bytes(drawer.task.speed) + "/s"], [qsTr("ETA"), drawer.time(drawer.task.eta)], [qsTr("Connections"), drawer.task.connections || "—"], [qsTr("Segments"), (drawer.task.completedSegments || 0) + " / " + (drawer.task.totalSegments || 0)], [qsTr("Retries"), drawer.task.retries || 0], [qsTr("Engine"), drawer.task.engine || "—"]]
                    delegate: ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 3; Label { text: modelData[0]; color: "#8492A8"; font.pixelSize: 10 } Label { Layout.fillWidth: true; text: modelData[1]; color: "#DFE8F7"; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight } }
                }
            } }
            Item { ColumnLayout { anchors.fill: parent; spacing: 10; Label { text: qsTr("Live speed history"); color: "#DCE6F8"; font.pixelSize: 13; font.weight: Font.DemiBold } SpeedGraph { Layout.fillWidth: true; Layout.preferredHeight: 160; samples: taskController.speedSamples } ProgressBar { Layout.fillWidth: true; from: 0; to: 1; value: drawer.task.progress || 0 } Label { text: Math.round((drawer.task.progress || 0) * 100) + "%"; color: "#AAB8CC"; font.pixelSize: 12 } } }
            Item { ColumnLayout { anchors.fill: parent; spacing: 10; Label { text: qsTr("Source and file"); color: "#DCE6F8"; font.pixelSize: 13; font.weight: Font.DemiBold } Label { text: qsTr("URL"); color: "#8492A8"; font.pixelSize: 10 } TextArea { Layout.fillWidth: true; Layout.preferredHeight: 80; readOnly: true; text: drawer.task.url || ""; wrapMode: Text.Wrap; selectByMouse: true } Label { text: qsTr("Save path"); color: "#8492A8"; font.pixelSize: 10 } TextArea { Layout.fillWidth: true; Layout.preferredHeight: 65; readOnly: true; text: drawer.task.savePath || ""; wrapMode: Text.Wrap; selectByMouse: true } } }
            Item { ColumnLayout { anchors.fill: parent; spacing: 10; Label { text: qsTr("Core mirrors"); color: "#DCE6F8"; font.pixelSize: 13; font.weight: Font.DemiBold } TextField { id: localMirrorUrl; Layout.fillWidth: true; placeholderText: qsTr("https://mirror.example/file") } RowLayout { Layout.fillWidth: true; SpinBox { id: localPriority; from: 0; to: 99; value: 0; editable: true } Button { text: qsTr("Add"); enabled: localMirrorUrl.text.trim().length > 0; onClicked: { taskController.addSelectedMirror(localMirrorUrl.text, localPriority.value); localMirrorUrl.clear() } } Button { text: qsTr("Failover"); onClicked: taskController.triggerSelectedMirrorFailover() } } ListView { id: selectedMirrorList; Layout.fillWidth: true; Layout.fillHeight: true; model: taskController.mirrors; delegate: Label { required property var modelData; width: selectedMirrorList.width; visible: modelData.task_id === taskController.selectedId; text: (modelData.active_url || "—") + "\n" + (modelData.mirrors || []).map(function(x) { return x.url }).join("\n"); color: "#B4C2D7"; wrapMode: Text.Wrap; padding: 8; font.pixelSize: 10 } ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded } } } }
            Item { TextArea { anchors.fill: parent; readOnly: true; selectByMouse: true; text: Object.keys(taskController.taskTrace).length > 0 ? JSON.stringify(taskController.taskTrace, null, 2) : qsTr("No selected-task trace was returned by Core."); wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 10 } }
        }
        Label { visible: (drawer.task.errorMessage || "").length > 0; Layout.fillWidth: true; text: drawer.task.errorMessage || ""; wrapMode: Text.Wrap; color: "#FF8894"; font.pixelSize: 12 }
        RowLayout { Layout.fillWidth: true; Button { text: qsTr("Open file"); enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.openFile(drawer.task.savePath) } Button { text: qsTr("Show folder"); enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.revealFile(drawer.task.savePath) } Item { Layout.fillWidth: true } Button { text: qsTr("Retry"); onClicked: taskController.retrySelected() } }
    }
}
