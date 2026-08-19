import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "components"
import "dialogs"
import "pages"

ApplicationWindow {
    id: window
    width: 1440
    height: 900
    minimumWidth: 1080
    minimumHeight: 680
    visible: true
    title: "NDM2"
    color: dark ? "#0C1628" : "#EDF2F8"
    readonly property bool dark: settingsService.dark
    readonly property color bg: dark ? "#0C1628" : "#EDF2F8"
    readonly property color sidebar: dark ? "#101C30" : "#F6F9FE"
    readonly property color surface: dark ? "#142239" : "#FFFFFF"
    readonly property color text: dark ? "#EAF1FF" : "#1B2638"
    readonly property color muted: dark ? "#8D9AB0" : "#68758A"
    property string section: "all"
    property string searchText: ""
    property bool detailsOpen: false
    property string toastText: ""
    property bool toastError: false
    LayoutMirroring.enabled: settingsService.rightToLeft
    LayoutMirroring.childrenInherit: true

    function statusFor(name) { return name === "active" ? "downloading" : name === "completed" ? "completed" : name === "failed" ? "error" : "" }
    function titleFor(name) { return name === "all" ? qsTr("All downloads") : name === "active" ? qsTr("Active downloads") : name === "completed" ? qsTr("Completed") : name === "failed" ? qsTr("Failed") : name === "queue" ? qsTr("Queue") : name === "diagnostics" ? qsTr("Diagnostics") : qsTr("Downloads") }
    function matches(name, status, category) { var target = statusFor(section); var search = searchText.toLowerCase(); return (!target || status === target) && (!search || name.toLowerCase().indexOf(search) >= 0 || category.toLowerCase().indexOf(search) >= 0) }

    Shortcut { sequence: "Ctrl+N"; onActivated: addDialog.open() }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsDialog.open() }
    Shortcut { sequence: "Space"; onActivated: taskController.selectedDownload.status === "downloading" ? taskController.pauseSelected() : taskController.resumeSelected() }
    Connections {
        target: taskController
        function onNotice(message, isError) { window.toastText = message; window.toastError = isError; toastTimer.restart() }
        function onSelectedChanged() { if (taskController.selectedId.length > 0) window.detailsOpen = true }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 246
            color: window.sidebar
            border.color: window.dark ? "#1D2F4B" : "#DCE5F0"
            border.width: 1
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 15
                spacing: 7
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50
                    Rectangle { width: 34; height: 34; radius: 10; color: "#377FF0"; Text { anchors.centerIn: parent; text: "N"; color: "white"; font.pixelSize: 18; font.weight: Font.Bold } }
                    ColumnLayout { spacing: 0; Label { text: "NDM2"; color: window.text; font.pixelSize: 17; font.weight: Font.Bold } Label { text: qsTr("Native Download Manager"); color: window.muted; font.pixelSize: 9 } }
                }
                Label { text: qsTr("LIBRARY"); color: "#667791"; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.topMargin: 18; Layout.leftMargin: 8 }
                NavItem { label: qsTr("All Downloads"); glyph: "▦"; selected: window.section === "all"; count: taskController.downloads.count; Layout.fillWidth: true; onClicked: window.section = "all" }
                NavItem { label: qsTr("Active"); glyph: "↓"; selected: window.section === "active"; count: taskController.downloads.countForStatus("downloading"); Layout.fillWidth: true; onClicked: window.section = "active" }
                NavItem { label: qsTr("Completed"); glyph: "✓"; selected: window.section === "completed"; count: taskController.downloads.countForStatus("completed"); Layout.fillWidth: true; onClicked: window.section = "completed" }
                NavItem { label: qsTr("Failed"); glyph: "!"; selected: window.section === "failed"; count: taskController.downloads.countForStatus("error"); Layout.fillWidth: true; onClicked: window.section = "failed" }
                Label { text: qsTr("WORKFLOW"); color: "#667791"; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.topMargin: 16; Layout.leftMargin: 8 }
                NavItem { label: qsTr("Queue"); glyph: "≡"; selected: window.section === "queue"; count: taskController.queueEntries.length; Layout.fillWidth: true; onClicked: { window.section = "queue"; taskController.refreshAll() } }
                NavItem { label: qsTr("Diagnostics"); glyph: "⌁"; selected: window.section === "diagnostics"; Layout.fillWidth: true; onClicked: { window.section = "diagnostics"; taskController.refreshAll() } }
                Item { Layout.fillHeight: true }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 68
                    radius: 10
                    color: taskController.connected ? "#112E35" : "#35202B"
                    border.color: taskController.connected ? "#22515B" : "#663446"
                    RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 9
                        Rectangle { width: 8; height: 8; radius: 4; color: taskController.connected ? "#4FD3A4" : "#FF7385" }
                        ColumnLayout { Layout.fillWidth: true; spacing: 1; Label { text: taskController.connected ? qsTr("Core connected") : qsTr("Core unavailable"); color: "#D8E7EC"; font.pixelSize: 11; font.weight: Font.DemiBold } Label { Layout.fillWidth: true; text: taskController.connected ? qsTr("Authenticated loopback") : taskController.lastError; color: "#8FABBB"; font.pixelSize: 9; elide: Text.ElideRight } }
                    }
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: window.bg
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 76
                    color: window.surface
                    border.color: window.dark ? "#1D2F4B" : "#DCE5F0"
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 28
                        anchors.rightMargin: 28
                        spacing: 14
                        ColumnLayout { Layout.fillWidth: true; spacing: 1; Label { text: window.titleFor(window.section); color: window.text; font.pixelSize: 21; font.weight: Font.DemiBold } Label { text: taskController.downloads.count + qsTr(" tasks reported by NOVA Core"); color: window.muted; font.pixelSize: 11 } }
                        TextField { id: search; visible: window.section !== "queue" && window.section !== "diagnostics"; Layout.preferredWidth: 270; placeholderText: qsTr("Search downloads  Ctrl+F"); selectByMouse: true; onTextChanged: window.searchText = text; background: Rectangle { radius: 9; color: window.dark ? "#0F1B2E" : "#F0F4F9"; border.color: search.activeFocus ? "#4A90F5" : "transparent" } leftPadding: 13; rightPadding: 13 }
                        ToolButton { text: "↻"; font.pixelSize: 19; onClicked: taskController.refreshAll(); ToolTip.text: qsTr("Refresh from core"); ToolTip.visible: hovered }
                        Button { text: qsTr("+  Add download"); onClicked: addDialog.open(); contentItem: Text { text: parent.text; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.weight: Font.DemiBold; font.pixelSize: 12 } background: Rectangle { radius: 8; color: parent.hovered ? "#4B92FF" : "#3278E8" } }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 62
                    color: window.bg
                    visible: window.section !== "queue" && window.section !== "diagnostics"
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 28; spacing: 9
                        Button { text: "Ⅱ  " + qsTr("Pause"); enabled: taskController.selectedDownload.status === "downloading"; onClicked: taskController.pauseSelected() }
                        Button { text: "▶  " + qsTr("Resume"); enabled: taskController.selectedDownload.status === "paused" || taskController.selectedDownload.status === "queued"; onClicked: taskController.resumeSelected() }
                        Button { text: "↻  " + qsTr("Retry"); enabled: taskController.selectedDownload.status === "error"; onClicked: taskController.retrySelected() }
                        Button { text: "×  " + qsTr("Cancel"); enabled: taskController.selectedId.length > 0; onClicked: taskController.cancelSelected() }
                        Button { text: "⌫  " + qsTr("Delete"); enabled: taskController.selectedId.length > 0; onClicked: taskController.deleteSelected(false) }
                        Item { Layout.fillWidth: true }
                        Button { text: qsTr("Details"); enabled: taskController.selectedId.length > 0; onClicked: window.detailsOpen = true }
                        ToolButton { text: "⚙"; font.pixelSize: 17; onClicked: settingsDialog.open() }
                    }
                }
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 20
                    Layout.rightMargin: 20
                    Layout.bottomMargin: 16
                    currentIndex: window.section === "queue" ? 1 : window.section === "diagnostics" ? 2 : 0
                    Item {
                        Rectangle {
                            anchors.fill: parent
                            color: window.surface
                            radius: 12
                            border.color: window.dark ? "#1E304B" : "#DCE4EF"
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 0
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 44
                                    color: window.dark ? "#122038" : "#F5F8FC"
                                    radius: 12
                                    RowLayout { anchors.fill: parent; anchors.leftMargin: 20; anchors.rightMargin: 20; Label { Layout.preferredWidth: Math.max(230, parent.width * .31); text: qsTr("NAME"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Label { Layout.preferredWidth: Math.max(130, parent.width * .19); text: qsTr("PROGRESS"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Label { Layout.preferredWidth: Math.max(85, parent.width * .1); text: qsTr("SPEED"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Label { Layout.preferredWidth: Math.max(64, parent.width * .07); text: qsTr("ETA"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Label { Layout.preferredWidth: 34; text: qsTr("CONN."); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Item { Layout.fillWidth: true } }
                                }
                                ListView {
                                    id: list
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    model: taskController.downloads
                                    spacing: 2
                                    visible: count > 0
                                    delegate: DownloadRow { visible: window.matches(name, status, category); selected: taskController.selectedId === downloadId; compact: settingsService.density === "compact"; onActivated: taskController.selectedId = downloadId }
                                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                                }
                                EmptyState { Layout.fillWidth: true; Layout.fillHeight: true; visible: list.count === 0; title: taskController.connected ? qsTr("No downloads in this view") : qsTr("Waiting for NOVA Core"); subtitle: taskController.connected ? qsTr("Create a download and the core will provide its live state here.") : taskController.lastError; onActionRequested: addDialog.open() }
                            }
                        }
                    }
                    QueuePage { surface: window.surface; textColor: window.text; muted: window.muted; onAddRequested: addDialog.open() }
                    DiagnosticsPage { surface: window.surface; textColor: window.text; muted: window.muted }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 32; color: window.surface; border.color: window.dark ? "#1D2F4B" : "#DCE5F0"; border.width: 1
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 25; anchors.rightMargin: 25; Label { text: taskController.connected ? "● " + qsTr("Core online") : "● " + qsTr("Offline"); color: taskController.connected ? "#4CCB9D" : "#FF7181"; font.pixelSize: 10 } Item { Layout.fillWidth: true } Label { text: qsTr("Native Qt Quick UI · Authenticated SSE adapter"); color: window.muted; font.pixelSize: 10 } }
                }
            }
        }
    }
    DetailsDrawer { id: detailsDrawer; visible: window.detailsOpen; onClosed: window.detailsOpen = false }
    AddDownloadDialog { id: addDialog }
    SettingsDialog { id: settingsDialog }
    Rectangle { id: toast; z: 30; visible: window.toastText.length > 0; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 46; width: Math.min(520, toastLabel.implicitWidth + 44); height: 44; radius: 10; color: window.toastError ? "#6A2E40" : "#183A40"; border.color: window.toastError ? "#B85169" : "#2D7371"; Label { id: toastLabel; anchors.centerIn: parent; text: window.toastText; color: "#EFF6FF"; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width - 30; horizontalAlignment: Text.AlignHCenter } }
    Timer { id: toastTimer; interval: 4500; onTriggered: window.toastText = "" }
}
