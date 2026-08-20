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
    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout { Layout.fillWidth: true
            SectionHeader { Layout.fillWidth: true; title: qsTr("Core diagnostics"); subtitle: qsTr("Live NOVA health, declared capabilities, safe logs and the selected Core task trace."); theme: root.theme }
            ComboBox { id: levelSelector; model: ["trace", "debug", "info", "warn", "error"]; currentIndex: Math.max(0, model.indexOf(taskController.logLevel)); Accessible.name: qsTr("Core log level"); onActivated: taskController.setLogLevel(currentText) }
            ActionButton { text: qsTr("Refresh"); tone: "secondary"; dark: settingsService.dark; theme: root.theme; onClicked: taskController.refreshAll() }
        }
        GridLayout { Layout.fillWidth: true; columns: 4; columnSpacing: 12; rowSpacing: 12
            Repeater { model: [[qsTr("Client"), "NDM2 " + ndm2Version], [qsTr("Core"), taskController.health.status || (taskController.connected ? qsTr("Online") : qsTr("Offline"))], [qsTr("Core version"), taskController.health.version || taskController.capabilities.version || "—"], [qsTr("Active"), taskController.statistics.activeDownloads || 0], [qsTr("Queue"), taskController.queueEntries.length], [qsTr("Bandwidth"), (taskController.bandwidth.globalLimitKbps || taskController.bandwidth.global_limit_kbps || 0) + " KB/s"], [qsTr("Profile"), taskController.activeProfile || "—"], [qsTr("Completed"), taskController.statistics.totalCompleted || 0], [qsTr("Failed"), taskController.statistics.totalFailed || 0]]
                delegate: Rectangle { required property var modelData; Layout.fillWidth: true; Layout.preferredHeight: 64; radius: 10; color: Qt.rgba(1,1,1,.035); border.color: Qt.rgba(1,1,1,.08); ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 2; Label { text: modelData[0]; color: root.muted; font.pixelSize: 10 } Label { Layout.fillWidth: true; text: modelData[1]; color: root.textColor; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight } } }
            }
        }
        SplitView { Layout.fillWidth: true; Layout.fillHeight: true; orientation: Qt.Horizontal
            Rectangle { SplitView.preferredWidth: parent.width * .52; color: root.surface; radius: 12; border.color: "#233653"
                ColumnLayout { anchors.fill: parent; anchors.margins: 10; spacing: 8
                    RowLayout { Layout.fillWidth: true; TextField { Layout.fillWidth: true; placeholderText: qsTr("Filter safe log text") ; onTextChanged: root.searchText = text } ComboBox { model: ["all", "trace", "debug", "info", "warn", "error"]; onActivated: root.viewLevel = currentText } ActionButton { text: qsTr("Reload"); tone: "quiet"; dark: settingsService.dark; theme: root.theme; onClicked: taskController.refreshLogsFiltered(500, root.viewLevel) } }
                    ListView { id: logList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.logs
                        delegate: Label { required property var modelData; visible: root.logMatches(modelData); width: logList.width; padding: 8; text: root.safeText((modelData.timestamp || "") + "  " + (modelData.level || "INFO") + "  " + (modelData.message || "")); color: String(modelData.level || "").toUpperCase() === "ERROR" ? (root.theme ? root.theme.danger : "#FF8794") : String(modelData.level || "").toUpperCase() === "WARN" ? (root.theme ? root.theme.warning : "#FFBE69") : (root.theme ? root.theme.textSecondary : "#B4C2D7"); wrapMode: Text.Wrap; font.family: "monospace"; font.pixelSize: 10 }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                }
            }
            Rectangle { SplitView.preferredWidth: parent.width * .48; color: root.surface; radius: 12; border.color: "#233653"
                TabBar { id: detailsTabs; width: parent.width; TabButton { text: qsTr("Task trace") } TabButton { text: qsTr("Capabilities") } }
                StackLayout { anchors.top: detailsTabs.bottom; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 12; currentIndex: detailsTabs.currentIndex
                    ColumnLayout { spacing: 8
                        Label { text: qsTr("Selected task trace"); color: root.textColor; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Label { Layout.fillWidth: true; text: taskController.selectedDownload.name || qsTr("Select a task in the library to request its Core trace."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 10 }
                        TextArea { Layout.fillWidth: true; Layout.fillHeight: true; readOnly: true; selectByMouse: true; text: Object.keys(taskController.taskTrace).length > 0 ? root.safeText(JSON.stringify(taskController.taskTrace, null, 2)) : qsTr("No per-task trace was returned by the Core."); wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 10 }
                    }
                    ColumnLayout { spacing: 8
                        Label { text: qsTr("Core capability report"); color: root.textColor; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Label { Layout.fillWidth: true; text: qsTr("This report is provided by the active Core; it never displays the NDM2 daemon token."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 10 }
                        TextArea { Layout.fillWidth: true; Layout.fillHeight: true; readOnly: true; selectByMouse: true; text: root.safeText(JSON.stringify(taskController.capabilities, null, 2)); wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 10 }
                    }
                }
            }
        }
    }
}
