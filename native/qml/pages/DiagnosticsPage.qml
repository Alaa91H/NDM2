import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

WorkspaceWindow {
    id: root

    pageTitle: qsTr("Diagnostics")
    pageSubtitle: qsTr("Live Core health, safe logs, capabilities, and selected-task inspection.")
    glyph: "⌁"
    statusText: taskController.connected ? qsTr("Core online") : qsTr("Core unavailable")
    actionText: qsTr("Refresh")
    onActionRequested: taskController.refreshAll()

    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    property string searchText: ""
    property string viewLevel: "all"

    function safeText(value) {
        return String(value === undefined || value === null ? "" : value)
            .replace(/Bearer\s+[A-Za-z0-9._~+\/-]+=*/gi, "Bearer [REDACTED]")
            .replace(/("?(?:token|api[_-]?key|authorization)"?\s*[:=]\s*")[^"]+/gi, "$1[REDACTED]")
    }
    function logMatches(item) {
        var level = String(item.level || "info").toLowerCase()
        var text = root.safeText((item.message || "") + " " + (item.target || "") + " " + (item.task || "")).toLowerCase()
        return (root.viewLevel === "all" || level === root.viewLevel) && (root.searchText.length === 0 || text.indexOf(root.searchText.toLowerCase()) >= 0)
    }
    function levelColor(level) {
        var normalized = String(level || "info").toLowerCase()
        if (normalized === "error") return theme ? theme.danger : "#FF8493"
        if (normalized === "warn") return theme ? theme.warning : "#FFC56A"
        if (normalized === "debug" || normalized === "trace") return theme ? theme.textMuted : "#71829B"
        return theme ? theme.information : "#8DBDFF"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: theme ? theme.spaceMd : 12

        RowLayout {
            Layout.fillWidth: true
            Label { Layout.fillWidth: true; text: qsTr("Core log level"); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
            ThemedComboBox { id: levelSelector; Layout.preferredWidth: 148; model: ["trace", "debug", "info", "warn", "error"]; currentIndex: Math.max(0, model.indexOf(taskController.logLevel)); theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Core log level"); onActivated: taskController.setLogLevel(currentText) }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width < 860 ? 3 : 5
            columnSpacing: theme ? theme.spaceSm : 8
            rowSpacing: theme ? theme.spaceSm : 8
            Repeater {
                model: [
                    [qsTr("Client"), "NDM2 " + ndm2Version, "◆", theme ? theme.accent : "#5C9EFF"],
                    [qsTr("Core"), taskController.health.status || (taskController.connected ? qsTr("Online") : qsTr("Offline")), "●", taskController.connected ? (theme ? theme.success : "#58D6A3") : (theme ? theme.danger : "#FF8493")],
                    [qsTr("Core version"), taskController.health.version || taskController.capabilities.version || "—", "⌁", theme ? theme.information : "#8DBDFF"],
                    [qsTr("Active"), taskController.statistics.activeDownloads || 0, "↓", theme ? theme.success : "#58D6A3"],
                    [qsTr("Queue"), taskController.queueEntries.length, "≡", theme ? theme.warning : "#FFC56A"],
                    [qsTr("Bandwidth"), (taskController.bandwidth.globalLimitKbps || taskController.bandwidth.global_limit_kbps || 0) + " KB/s", "↯", theme ? theme.accent : "#5C9EFF"],
                    [qsTr("Profile"), taskController.activeProfile || "—", "◈", theme ? theme.information : "#8DBDFF"],
                    [qsTr("Completed"), taskController.statistics.totalCompleted || 0, "✓", theme ? theme.success : "#58D6A3"],
                    [qsTr("Failed"), taskController.statistics.totalFailed || 0, "!", theme ? theme.danger : "#FF8493"]
                ]
                delegate: InfoCard {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    theme: root.theme
                    emphasized: true
                    contentPadding: root.theme ? root.theme.spaceMd : 12
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: root.theme ? root.theme.radiusSm : 6; color: Qt.rgba(modelData[3].r, modelData[3].g, modelData[3].b, .14); Text { anchors.centerIn: parent; text: modelData[2]; color: modelData[3]; font.pixelSize: 14; font.weight: Font.DemiBold } }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            Label { text: modelData[0]; color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontMeta : 10 }
                            Label { Layout.fillWidth: true; text: modelData[1]; color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBody : 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: theme ? theme.spaceMd : 12

            InfoCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * .55
                theme: root.theme
                Label { text: qsTr("Safe Core log"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                Label { text: qsTr("Sensitive authorization values are redacted before display."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11 }
                RowLayout {
                    Layout.fillWidth: true
                    ThemedTextField { Layout.fillWidth: true; placeholderText: qsTr("Filter safe log text"); leadingGlyph: "⌕"; theme: root.theme; dark: settingsService.dark; onTextChanged: root.searchText = text }
                    ThemedComboBox { Layout.preferredWidth: 116; model: ["all", "trace", "debug", "info", "warn", "error"]; theme: root.theme; dark: settingsService.dark; onActivated: root.viewLevel = currentText }
                    IconButton { glyph: "↻"; accessibleLabel: qsTr("Reload logs"); theme: root.theme; dark: settingsService.dark; onClicked: taskController.refreshLogsFiltered(500, root.viewLevel) }
                }
                ListView {
                    id: logList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    model: taskController.logs
                    delegate: Rectangle {
                        required property var modelData
                        visible: root.logMatches(modelData)
                        width: logList.width
                        height: visible ? logLabel.implicitHeight + 14 : 0
                        radius: root.theme ? root.theme.radiusXs : 4
                        color: Qt.rgba(root.levelColor(modelData.level).r, root.levelColor(modelData.level).g, root.levelColor(modelData.level).b, .09)
                        border.color: Qt.rgba(root.levelColor(modelData.level).r, root.levelColor(modelData.level).g, root.levelColor(modelData.level).b, .24)
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 7
                            spacing: 8
                            Label { Layout.preferredWidth: 42; text: String(modelData.level || "info").toUpperCase(); color: root.levelColor(modelData.level); font.pixelSize: root.theme ? root.theme.fontMeta : 10; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter }
                            Label { id: logLabel; Layout.fillWidth: true; text: root.safeText((modelData.timestamp || "") + "  " + (modelData.message || "")); color: root.theme ? root.theme.textSecondary : root.muted; wrapMode: Text.Wrap; font.family: root.theme ? root.theme.fontMono : "monospace"; font.pixelSize: root.theme ? root.theme.fontMeta : 10 }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            }

            InfoCard {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: parent.width * .45
                theme: root.theme
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Core inspection"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                }
                FluentTabBar {
                    id: detailsTabs
                    Layout.fillWidth: true
                    theme: root.theme
                    accessibleName: qsTr("Core inspection sections")
                    labels: [qsTr("Task trace"), qsTr("Capabilities")]
                }
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: detailsTabs.currentIndex
                    ColumnLayout {
                        spacing: root.theme ? root.theme.spaceSm : 8
                        Label { text: qsTr("Selected task trace"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBody : 12; font.weight: Font.DemiBold }
                        Label { Layout.fillWidth: true; text: taskController.selectedDownload.name || qsTr("Select a task in the library to request its Core trace."); color: root.theme ? root.theme.textSecondary : root.muted; wrapMode: Text.Wrap; font.pixelSize: root.theme ? root.theme.fontCaption : 11 }
                        ThemedTextArea { Layout.fillWidth: true; Layout.fillHeight: true; readOnly: true; monospace: true; text: Object.keys(taskController.taskTrace).length > 0 ? root.safeText(JSON.stringify(taskController.taskTrace, null, 2)) : qsTr("No per-task trace was returned by the Core."); theme: root.theme; dark: settingsService.dark }
                    }
                    ColumnLayout {
                        spacing: root.theme ? root.theme.spaceSm : 8
                        Label { text: qsTr("Core capability report"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBody : 12; font.weight: Font.DemiBold }
                        Label { Layout.fillWidth: true; text: qsTr("Provided by the active Core; the NDM2 daemon token is never shown here."); color: root.theme ? root.theme.textSecondary : root.muted; wrapMode: Text.Wrap; font.pixelSize: root.theme ? root.theme.fontCaption : 11 }
                        ThemedTextArea { Layout.fillWidth: true; Layout.fillHeight: true; readOnly: true; monospace: true; text: root.safeText(JSON.stringify(taskController.capabilities, null, 2)); theme: root.theme; dark: settingsService.dark }
                    }
                }
            }
        }
    }
}
