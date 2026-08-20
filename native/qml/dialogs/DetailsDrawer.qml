import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Drawer {
    id: drawer

    edge: Qt.RightEdge
    modal: false
    width: Math.min(600, parent ? parent.width * .50 : 600)
    height: parent ? parent.height : 800
    property var task: taskController.selectedDownload

    Theme { id: design; dark: settingsService.dark }

    background: Rectangle {
        color: design.background
        border.color: design.borderStrong
        border.width: 1
    }

    function bytes(value) {
        if (!value || value <= 0) return "—"
        var units = ["B", "KB", "MB", "GB", "TB"], index = 0
        while (value >= 1024 && index < units.length - 1) { value /= 1024; index++ }
        return value.toFixed(index === 0 ? 0 : 1) + " " + units[index]
    }
    function time(seconds) {
        if (!seconds || seconds <= 0 || !isFinite(seconds)) return "—"
        var hours = Math.floor(seconds / 3600), minutes = Math.floor((seconds % 3600) / 60), remainder = Math.floor(seconds % 60)
        return hours > 0 ? hours + "h " + minutes + "m" : minutes > 0 ? minutes + "m " + remainder + "s" : remainder + "s"
    }
    function stateCanPause() { return task.status === "downloading" || task.status === "active" }
    function stateCanResume() { return task.status === "paused" || task.status === "queued" || task.status === "waiting" }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: design.spaceLg
        spacing: design.spaceMd

        RowLayout {
            Layout.fillWidth: true
            spacing: design.spaceSm
            Rectangle {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: design.radiusMd
                color: design.accentSoft
                Text { anchors.centerIn: parent; text: "↓"; color: design.accent; font.pixelSize: 20; font.weight: Font.DemiBold }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { Layout.fillWidth: true; text: drawer.task.name || qsTr("Download details"); elide: Text.ElideRight; color: design.textPrimary; font.pixelSize: design.fontSection + 3; font.weight: Font.DemiBold; Accessible.name: text }
                Label { Layout.fillWidth: true; text: drawer.task.url || qsTr("No URL supplied by Core"); color: design.textSecondary; font.pixelSize: design.fontCaption; elide: Text.ElideMiddle }
            }
            IconButton { glyph: "×"; accessibleLabel: qsTr("Close details"); tone: "neutral"; dark: design.dark; theme: design; onClicked: drawer.close() }
        }

        InfoCard {
            Layout.fillWidth: true
            Layout.preferredHeight: 104
            theme: design
            emphasized: true
            contentPadding: design.spaceMd
            RowLayout {
                Layout.fillWidth: true
                spacing: design.spaceMd
                StatusBadge { Layout.alignment: Qt.AlignTop; status: drawer.task.status || "unknown"; dark: design.dark; theme: design }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: design.spaceSm
                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: Math.round((drawer.task.progress || 0) * 100) + "%"; color: design.textPrimary; font.pixelSize: design.fontMetric + 4; font.weight: Font.DemiBold }
                        Item { Layout.fillWidth: true }
                        Label { text: drawer.bytes(drawer.task.speed) + "/s"; color: drawer.task.speed > 0 ? design.success : design.textMuted; font.pixelSize: design.fontBody; font.weight: Font.DemiBold }
                    }
                    ProgressBar {
                        Layout.fillWidth: true
                        from: 0
                        to: 1
                        value: drawer.task.progress || 0
                        Accessible.name: qsTr("Download progress")
                        background: Rectangle { implicitHeight: 8; radius: 4; color: design.border }
                        contentItem: Item { Rectangle { width: parent.visualPosition * parent.width; height: parent.height; radius: 4; color: design.statusColor(drawer.task.status); Behavior on width { NumberAnimation { duration: 140 } } } }
                    }
                    Label { Layout.fillWidth: true; text: drawer.bytes(drawer.task.downloadedBytes) + " / " + drawer.bytes(drawer.task.sizeBytes) + "  ·  " + qsTr("ETA %1").arg(drawer.time(drawer.task.eta)); color: design.textSecondary; font.pixelSize: design.fontCaption; elide: Text.ElideRight }
                }
            }
        }

        TabBar {
            id: tabBar
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            Accessible.name: qsTr("Download detail sections")
            background: Rectangle { radius: design.radiusMd; color: design.surfaceSubtle; border.color: design.border }
            Repeater {
                model: [qsTr("Overview"), qsTr("Speed"), qsTr("File"), qsTr("Mirrors"), qsTr("Logs")]
                delegate: TabButton {
                    required property string modelData
                    text: modelData
                    contentItem: Text { text: parent.text; color: parent.checked ? "#FFFFFF" : design.textSecondary; font.pixelSize: design.fontCaption; font.weight: parent.checked ? Font.DemiBold : Font.Normal; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                    background: Rectangle { anchors.margins: 3; radius: design.radiusSm; color: parent.checked ? design.accent : parent.hovered ? design.surfaceRaised : "transparent" }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabBar.currentIndex

            Item {
                GridLayout {
                    anchors.fill: parent
                    columns: 2
                    columnSpacing: design.spaceMd
                    rowSpacing: design.spaceMd
                    Repeater {
                        model: [
                            [qsTr("Status"), drawer.task.status || "—", "●"],
                            [qsTr("Category"), drawer.task.category || "—", "▣"],
                            [qsTr("Downloaded"), drawer.bytes(drawer.task.downloadedBytes), "↓"],
                            [qsTr("Total size"), drawer.bytes(drawer.task.sizeBytes), "□"],
                            [qsTr("Speed"), drawer.bytes(drawer.task.speed) + "/s", "↯"],
                            [qsTr("ETA"), drawer.time(drawer.task.eta), "◷"],
                            [qsTr("Connections"), drawer.task.connections || "—", "⌁"],
                            [qsTr("Segments"), (drawer.task.completedSegments || 0) + " / " + (drawer.task.totalSegments || 0), "▤"],
                            [qsTr("Retries"), drawer.task.retries || 0, "↻"],
                            [qsTr("Engine"), drawer.task.engine || "—", "◆"]
                        ]
                        delegate: InfoCard {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredHeight: 70
                            theme: design
                            emphasized: true
                            contentPadding: design.spaceSm
                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: modelData[2]; color: design.accent; font.pixelSize: 14 }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Label { text: modelData[0]; color: design.textMuted; font.pixelSize: design.fontMeta }
                                    Label { Layout.fillWidth: true; text: modelData[1]; color: design.textPrimary; font.pixelSize: design.fontBody; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                }
                            }
                        }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: design.spaceMd
                    InfoCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        theme: design
                        Label { text: qsTr("Live speed history"); color: design.textPrimary; font.pixelSize: design.fontBodyLarge; font.weight: Font.DemiBold }
                        Label { text: qsTr("Reconciled from the Core stream while NDM2 is open."); color: design.textSecondary; font.pixelSize: design.fontCaption }
                        SpeedGraph { Layout.fillWidth: true; Layout.fillHeight: true; samples: taskController.speedSamples; lineColor: design.accent; gridColor: design.border }
                        Label { text: qsTr("Current speed: %1/s").arg(drawer.bytes(drawer.task.speed)); color: design.textSecondary; font.pixelSize: design.fontCaption }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: design.spaceMd
                    InfoCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        theme: design
                        Label { text: qsTr("Source and file"); color: design.textPrimary; font.pixelSize: design.fontBodyLarge; font.weight: Font.DemiBold }
                        Label { text: qsTr("URL"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold }
                        ThemedTextArea { Layout.fillWidth: true; Layout.preferredHeight: 92; readOnly: true; text: drawer.task.url || ""; theme: design; dark: design.dark; monospace: true; Accessible.name: qsTr("Source URL") }
                        Label { text: qsTr("Save path"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold }
                        ThemedTextArea { Layout.fillWidth: true; Layout.preferredHeight: 76; readOnly: true; text: drawer.task.savePath || ""; theme: design; dark: design.dark; monospace: true; Accessible.name: qsTr("Save path") }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: design.spaceMd
                    InfoCard {
                        Layout.fillWidth: true
                        theme: design
                        Label { text: qsTr("Core mirrors"); color: design.textPrimary; font.pixelSize: design.fontBodyLarge; font.weight: Font.DemiBold }
                        Label { text: qsTr("Add an alternate source only when one is available."); color: design.textSecondary; font.pixelSize: design.fontCaption }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField { id: localMirrorUrl; Layout.fillWidth: true; placeholderText: qsTr("https://mirror.example/file"); leadingGlyph: "↗"; theme: design; dark: design.dark; Accessible.name: qsTr("Mirror URL") }
                            ThemedSpinBox { id: localPriority; Layout.preferredWidth: 86; from: 0; to: 99; value: 0; theme: design; dark: design.dark; Accessible.name: qsTr("Mirror priority") }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ActionButton { text: qsTr("Add mirror"); tone: "secondary"; dark: design.dark; theme: design; enabled: localMirrorUrl.text.trim().length > 0; onClicked: { taskController.addSelectedMirror(localMirrorUrl.text, localPriority.value); localMirrorUrl.clear() } }
                            ActionButton { text: qsTr("Fail over"); tone: "quiet"; dark: design.dark; theme: design; onClicked: taskController.triggerSelectedMirrorFailover() }
                            Item { Layout.fillWidth: true }
                        }
                    }
                    InfoCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        theme: design
                        Label { text: qsTr("Current mirror map"); color: design.textPrimary; font.pixelSize: design.fontBodyLarge; font.weight: Font.DemiBold }
                        ListView {
                            id: selectedMirrorList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            model: taskController.mirrors
                            delegate: InfoCard {
                                required property var modelData
                                width: selectedMirrorList.width
                                visible: modelData.task_id === taskController.selectedId
                                height: visible ? 74 : 0
                                theme: design
                                emphasized: true
                                contentPadding: design.spaceSm
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Label { Layout.fillWidth: true; text: qsTr("Active: ") + (modelData.active_url || "—"); color: design.textPrimary; font.pixelSize: design.fontCaption; elide: Text.ElideMiddle }
                                    Label { Layout.fillWidth: true; text: (modelData.mirrors || []).map(function(item) { return item.url }).join("  ·  "); color: design.textSecondary; font.pixelSize: design.fontMeta; elide: Text.ElideMiddle }
                                }
                            }
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                    }
                }
            }

            Item {
                InfoCard {
                    anchors.fill: parent
                    theme: design
                    Label { text: qsTr("Core task trace"); color: design.textPrimary; font.pixelSize: design.fontBodyLarge; font.weight: Font.DemiBold }
                    Label { text: qsTr("Safe diagnostic data returned for the selected task."); color: design.textSecondary; font.pixelSize: design.fontCaption }
                    ThemedTextArea { Layout.fillWidth: true; Layout.fillHeight: true; readOnly: true; monospace: true; text: Object.keys(taskController.taskTrace).length > 0 ? JSON.stringify(taskController.taskTrace, null, 2) : qsTr("No selected-task trace was returned by Core."); theme: design; dark: design.dark; Accessible.name: qsTr("Task trace") }
                }
            }
        }

        InfoCard {
            visible: (drawer.task.errorMessage || "").length > 0
            Layout.fillWidth: true
            theme: design
            color: design.dangerSoft
            border.color: design.danger
            RowLayout {
                Layout.fillWidth: true
                Text { text: "!"; color: design.danger; font.pixelSize: 18; font.weight: Font.Bold }
                Label { Layout.fillWidth: true; text: drawer.task.errorMessage || ""; wrapMode: Text.Wrap; color: design.textPrimary; font.pixelSize: design.fontBody; Accessible.name: qsTr("Download error: %1").arg(drawer.task.errorMessage || "") }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: design.spaceXs
            ActionButton { visible: drawer.stateCanPause(); text: qsTr("Pause"); tone: "secondary"; dark: design.dark; theme: design; onClicked: taskController.pauseSelected() }
            ActionButton { visible: drawer.stateCanResume(); text: qsTr("Resume"); tone: "primary"; dark: design.dark; theme: design; onClicked: taskController.resumeSelected() }
            ActionButton { text: qsTr("Retry"); tone: "quiet"; dark: design.dark; theme: design; onClicked: taskController.retrySelected() }
            Item { Layout.fillWidth: true }
            ActionButton { text: qsTr("Show folder"); tone: "quiet"; dark: design.dark; theme: design; enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.revealFile(drawer.task.savePath) }
            ActionButton { text: qsTr("Open file"); tone: "primary"; dark: design.dark; theme: design; enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.openFile(drawer.task.savePath) }
        }
    }
}
