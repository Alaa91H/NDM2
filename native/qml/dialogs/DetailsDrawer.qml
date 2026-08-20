import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Drawer {
    id: drawer
    edge: Qt.RightEdge
    modal: false
    width: Math.min(560, parent ? parent.width * .48 : 560)
    height: parent ? parent.height : 800
    property var task: taskController.selectedDownload
    Theme { id: design; dark: settingsService.dark }
    background: Rectangle { color: design.surface; border.color: design.borderStrong; border.width: 1 }
    function bytes(value) { if (!value || value <= 0) return "—"; var units = ["B", "KB", "MB", "GB", "TB"], i = 0; while (value >= 1024 && i < units.length - 1) { value /= 1024; i++ } return value.toFixed(i === 0 ? 0 : 1) + " " + units[i] }
    function time(seconds) { if (!seconds || seconds <= 0 || !isFinite(seconds)) return "—"; var h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60), s = Math.floor(seconds % 60); return h > 0 ? h + "h " + m + "m" : m > 0 ? m + "m " + s + "s" : s + "s" }
    function stateCanPause() { return task.status === "downloading" || task.status === "active" }
    function stateCanResume() { return task.status === "paused" || task.status === "queued" || task.status === "waiting" }
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: design.spaceLg
        spacing: design.spaceMd
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 3
                Label { Layout.fillWidth: true; text: drawer.task.name || qsTr("Download details"); elide: Text.ElideRight; color: design.textPrimary; font.pixelSize: design.fontSection + 2; font.weight: Font.DemiBold; Accessible.name: text }
                Label { Layout.fillWidth: true; text: drawer.task.url || qsTr("No URL supplied by Core"); color: design.textSecondary; font.pixelSize: design.fontCaption; elide: Text.ElideMiddle }
            }
            ToolButton { text: "×"; font.pixelSize: 22; Accessible.name: qsTr("Close details"); onClicked: drawer.close() }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 70; radius: design.radiusMd; color: design.surfaceSubtle; border.color: design.border
            RowLayout { anchors.fill: parent; anchors.margins: design.spaceMd; spacing: design.spaceMd
                StatusBadge { status: drawer.task.status || "unknown"; dark: design.dark; theme: design }
                ColumnLayout { Layout.fillWidth: true; spacing: 2
                    Label { text: Math.round((drawer.task.progress || 0) * 100) + "%"; color: design.textPrimary; font.pixelSize: design.fontBodyLarge; font.weight: Font.DemiBold }
                    Label { text: drawer.bytes(drawer.task.downloadedBytes) + " / " + drawer.bytes(drawer.task.sizeBytes) + "  ·  " + drawer.bytes(drawer.task.speed) + "/s  ·  " + qsTr("ETA %1").arg(drawer.time(drawer.task.eta)); color: design.textSecondary; font.pixelSize: design.fontCaption; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }
        }
        TabBar {
            id: tabBar
            Layout.fillWidth: true
            Accessible.name: qsTr("Download detail sections")
            TabButton { text: qsTr("Overview") }
            TabButton { text: qsTr("Speed") }
            TabButton { text: qsTr("File") }
            TabButton { text: qsTr("Mirrors") }
            TabButton { text: qsTr("Logs") }
        }
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex
            Item {
                GridLayout { anchors.fill: parent; columns: 2; columnSpacing: design.spaceLg; rowSpacing: design.spaceMd
                    Repeater { model: [[qsTr("Status"), drawer.task.status || "—"], [qsTr("Category"), drawer.task.category || "—"], [qsTr("Downloaded"), drawer.bytes(drawer.task.downloadedBytes)], [qsTr("Total size"), drawer.bytes(drawer.task.sizeBytes)], [qsTr("Speed"), drawer.bytes(drawer.task.speed) + "/s"], [qsTr("ETA"), drawer.time(drawer.task.eta)], [qsTr("Connections"), drawer.task.connections || "—"], [qsTr("Segments"), (drawer.task.completedSegments || 0) + " / " + (drawer.task.totalSegments || 0)], [qsTr("Retries"), drawer.task.retries || 0], [qsTr("Engine"), drawer.task.engine || "—"]]
                        delegate: ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 3
                            Label { text: modelData[0]; color: design.textMuted; font.pixelSize: design.fontMeta }
                            Label { Layout.fillWidth: true; text: modelData[1]; color: design.textPrimary; font.pixelSize: design.fontBody; font.weight: Font.Medium; elide: Text.ElideRight }
                        }
                    }
                }
            }
            Item { ColumnLayout { anchors.fill: parent; spacing: design.spaceSm
                Label { text: qsTr("Live speed history"); color: design.textPrimary; font.pixelSize: design.fontBody; font.weight: Font.DemiBold }
                Label { text: qsTr("Reconciled from the Core stream while this application is open."); color: design.textSecondary; font.pixelSize: design.fontCaption }
                SpeedGraph { Layout.fillWidth: true; Layout.preferredHeight: 180; samples: taskController.speedSamples; lineColor: design.accent; gridColor: design.border }
                ProgressBar { Layout.fillWidth: true; from: 0; to: 1; value: drawer.task.progress || 0; Accessible.name: qsTr("Download progress") }
            } }
            Item { ColumnLayout { anchors.fill: parent; spacing: design.spaceSm
                Label { text: qsTr("Source and file"); color: design.textPrimary; font.pixelSize: design.fontBody; font.weight: Font.DemiBold }
                Label { text: qsTr("URL"); color: design.textMuted; font.pixelSize: design.fontMeta }
                TextArea { Layout.fillWidth: true; Layout.preferredHeight: 88; readOnly: true; text: drawer.task.url || ""; wrapMode: Text.WrapAnywhere; selectByMouse: true; Accessible.name: qsTr("Source URL") }
                Label { text: qsTr("Save path"); color: design.textMuted; font.pixelSize: design.fontMeta }
                TextArea { Layout.fillWidth: true; Layout.preferredHeight: 70; readOnly: true; text: drawer.task.savePath || ""; wrapMode: Text.WrapAnywhere; selectByMouse: true; Accessible.name: qsTr("Save path") }
            } }
            Item { ColumnLayout { anchors.fill: parent; spacing: design.spaceSm
                Label { text: qsTr("Core mirrors"); color: design.textPrimary; font.pixelSize: design.fontBody; font.weight: Font.DemiBold }
                Label { text: qsTr("Add mirrors only when an alternate source is available."); color: design.textSecondary; font.pixelSize: design.fontCaption }
                TextField { id: localMirrorUrl; Layout.fillWidth: true; placeholderText: qsTr("https://mirror.example/file"); Accessible.name: qsTr("Mirror URL") }
                RowLayout { Layout.fillWidth: true
                    SpinBox { id: localPriority; from: 0; to: 99; value: 0; editable: true; Accessible.name: qsTr("Mirror priority") }
                    ActionButton { text: qsTr("Add mirror"); tone: "secondary"; dark: design.dark; theme: design; enabled: localMirrorUrl.text.trim().length > 0; onClicked: { taskController.addSelectedMirror(localMirrorUrl.text, localPriority.value); localMirrorUrl.clear() } }
                    ActionButton { text: qsTr("Fail over"); tone: "quiet"; dark: design.dark; theme: design; onClicked: taskController.triggerSelectedMirrorFailover() }
                }
                ListView { id: selectedMirrorList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.mirrors
                    delegate: Rectangle { required property var modelData; width: selectedMirrorList.width; visible: modelData.task_id === taskController.selectedId; height: visible ? mirrorLabel.implicitHeight + design.spaceMd : 0; radius: design.radiusSm; color: design.surfaceSubtle
                        Label { id: mirrorLabel; anchors.fill: parent; anchors.margins: design.spaceSm; text: (modelData.active_url || "—") + "\n" + (modelData.mirrors || []).map(function(x) { return x.url }).join("\n"); color: design.textSecondary; wrapMode: Text.WrapAnywhere; font.pixelSize: design.fontCaption }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            } }
            Item { TextArea { anchors.fill: parent; readOnly: true; selectByMouse: true; text: Object.keys(taskController.taskTrace).length > 0 ? JSON.stringify(taskController.taskTrace, null, 2) : qsTr("No selected-task trace was returned by Core."); wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: design.fontMeta; Accessible.name: qsTr("Task trace") } }
        }
        Label { visible: (drawer.task.errorMessage || "").length > 0; Layout.fillWidth: true; text: "!  " + (drawer.task.errorMessage || ""); wrapMode: Text.Wrap; color: design.danger; font.pixelSize: design.fontBody; Accessible.name: qsTr("Download error: %1").arg(drawer.task.errorMessage || "") }
        RowLayout { Layout.fillWidth: true; spacing: design.spaceXs
            ActionButton { visible: drawer.stateCanPause(); text: qsTr("Pause"); tone: "secondary"; dark: design.dark; theme: design; onClicked: taskController.pauseSelected() }
            ActionButton { visible: drawer.stateCanResume(); text: qsTr("Resume"); tone: "primary"; dark: design.dark; theme: design; onClicked: taskController.resumeSelected() }
            ActionButton { text: qsTr("Retry"); tone: "quiet"; dark: design.dark; theme: design; onClicked: taskController.retrySelected() }
            Item { Layout.fillWidth: true }
            ActionButton { text: qsTr("Show folder"); tone: "quiet"; dark: design.dark; theme: design; enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.revealFile(drawer.task.savePath) }
            ActionButton { text: qsTr("Open file"); tone: "primary"; dark: design.dark; theme: design; enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.openFile(drawer.task.savePath) }
        }
    }
}
