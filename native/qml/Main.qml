import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "components"
import "dialogs"
import "pages"

ApplicationWindow {
    id: window
    width: 1480
    height: 920
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
    property string section: "library"
    property string statusFilter: ""
    property string categoryFilter: ""
    property string queueFilter: ""
    property bool detailsOpen: false
    property string toastText: ""
    property bool toastError: false
    LayoutMirroring.enabled: settingsService.rightToLeft
    LayoutMirroring.childrenInherit: true

    function applyLibraryFilters() { taskController.setLibraryFilters(search.text, statusFilter, categoryFilter, queueFilter) }
    function setSection(value, status) { section = value; statusFilter = status || ""; applyLibraryFilters() }
    function pageTitle() { return section === "queue" ? qsTr("Queue") : section === "automation" ? qsTr("Automation & sources") : section === "media" ? qsTr("Media discovery") : section === "browser" ? qsTr("Browser integration") : section === "diagnostics" ? qsTr("Diagnostics") : statusFilter === "downloading" ? qsTr("Active downloads") : statusFilter === "completed" ? qsTr("Completed") : statusFilter === "error" ? qsTr("Failed") : qsTr("All downloads") }

    Shortcut { sequence: "Ctrl+N"; onActivated: addDialog.open() }
    Shortcut { sequence: "Ctrl+F"; onActivated: search.forceActiveFocus() }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsDialog.open() }
    Shortcut { sequence: "Ctrl+A"; enabled: section === "library"; onActivated: taskController.selectAllFiltered() }
    Shortcut { sequence: "Escape"; onActivated: taskController.clearSelection() }
    Shortcut { sequence: "Delete"; enabled: taskController.selectedIds.length > 0; onActivated: taskController.bulkDelete(false) }
    Shortcut { sequence: "F5"; onActivated: taskController.refreshAll() }
    Connections { target: taskController; function onNotice(message, isError) { window.toastText = message; window.toastError = isError; toastTimer.restart() } function onSelectedChanged() { if (taskController.selectedId.length > 0) window.detailsOpen = true } }

    RowLayout { anchors.fill: parent; spacing: 0
        Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 250; color: window.sidebar; border.color: window.dark ? "#1D2F4B" : "#DCE5F0"; border.width: 1
            ColumnLayout { anchors.fill: parent; anchors.margins: 15; spacing: 7
                RowLayout { Layout.fillWidth: true; Layout.preferredHeight: 50; Rectangle { width: 34; height: 34; radius: 10; color: "#377FF0"; Text { anchors.centerIn: parent; text: "N"; color: "white"; font.pixelSize: 18; font.weight: Font.Bold } } ColumnLayout { spacing: 0; Label { text: "NDM2"; color: window.text; font.pixelSize: 17; font.weight: Font.Bold } Label { text: qsTr("Native Download Manager"); color: window.muted; font.pixelSize: 9 } } }
                Label { text: qsTr("LIBRARY"); color: "#667791"; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.topMargin: 18; Layout.leftMargin: 8 }
                NavItem { label: qsTr("All Downloads"); glyph: "▦"; selected: window.section === "library" && window.statusFilter === ""; count: taskController.downloads.count; Layout.fillWidth: true; onClicked: window.setSection("library", "") }
                NavItem { label: qsTr("Active"); glyph: "↓"; selected: window.section === "library" && window.statusFilter === "downloading"; count: taskController.downloads.countForStatus("downloading"); Layout.fillWidth: true; onClicked: window.setSection("library", "downloading") }
                NavItem { label: qsTr("Completed"); glyph: "✓"; selected: window.section === "library" && window.statusFilter === "completed"; count: taskController.downloads.countForStatus("completed"); Layout.fillWidth: true; onClicked: window.setSection("library", "completed") }
                NavItem { label: qsTr("Failed"); glyph: "!"; selected: window.section === "library" && window.statusFilter === "error"; count: taskController.downloads.countForStatus("error"); Layout.fillWidth: true; onClicked: window.setSection("library", "error") }
                Label { text: qsTr("WORKFLOW"); color: "#667791"; font.pixelSize: 10; font.weight: Font.DemiBold; Layout.topMargin: 14; Layout.leftMargin: 8 }
                NavItem { label: qsTr("Queue"); glyph: "≡"; selected: window.section === "queue"; count: taskController.queueEntries.length; Layout.fillWidth: true; onClicked: { window.section = "queue"; taskController.refreshAll() } }
                NavItem { label: qsTr("Automation"); glyph: "⌘"; selected: window.section === "automation"; Layout.fillWidth: true; onClicked: { window.section = "automation"; taskController.refreshAll() } }
                NavItem { label: qsTr("Media"); glyph: "▻"; selected: window.section === "media"; Layout.fillWidth: true; onClicked: { window.section = "media"; taskController.refreshAll() } }
                NavItem { label: qsTr("Browser"); glyph: "◈"; selected: window.section === "browser"; Layout.fillWidth: true; onClicked: { window.section = "browser"; taskController.refreshAll() } }
                NavItem { label: qsTr("Diagnostics"); glyph: "⌁"; selected: window.section === "diagnostics"; Layout.fillWidth: true; onClicked: { window.section = "diagnostics"; taskController.refreshAll() } }
                Item { Layout.fillHeight: true }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 66; radius: 10; color: taskController.connected ? "#112E35" : "#35202B"; border.color: taskController.connected ? "#22515B" : "#663446"; RowLayout { anchors.fill: parent; anchors.margins: 10; spacing: 9; Rectangle { width: 8; height: 8; radius: 4; color: taskController.connected ? "#4FD3A4" : "#FF7385" } ColumnLayout { Layout.fillWidth: true; spacing: 1; Label { text: taskController.connected ? qsTr("Core connected") : qsTr("Core unavailable"); color: "#D8E7EC"; font.pixelSize: 11; font.weight: Font.DemiBold } Label { Layout.fillWidth: true; text: taskController.connected ? qsTr("Authenticated loopback") : taskController.lastError; color: "#8FABBB"; font.pixelSize: 9; elide: Text.ElideRight } } } }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; color: window.bg
            ColumnLayout { anchors.fill: parent; spacing: 0
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 76; color: window.surface; border.color: window.dark ? "#1D2F4B" : "#DCE5F0"; border.width: 1
                    RowLayout { anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 28; spacing: 12
                        ColumnLayout { Layout.fillWidth: true; spacing: 1; Label { text: window.pageTitle(); color: window.text; font.pixelSize: 21; font.weight: Font.DemiBold } Label { text: taskController.filteredDownloads.count + qsTr(" matching tasks · ") + taskController.downloads.count + qsTr(" reported by NOVA Core"); color: window.muted; font.pixelSize: 11 } }
                        TextField { id: search; visible: window.section === "library"; Layout.preferredWidth: 260; placeholderText: qsTr("Search name, URL, category  Ctrl+F"); selectByMouse: true; onTextChanged: window.applyLibraryFilters(); background: Rectangle { radius: 9; color: window.dark ? "#0F1B2E" : "#F0F4F9"; border.color: search.activeFocus ? "#4A90F5" : "transparent" } leftPadding: 13; rightPadding: 13 }
                        ToolButton { text: "↻"; font.pixelSize: 19; onClicked: taskController.refreshAll(); ToolTip.text: qsTr("Refresh from Core"); ToolTip.visible: hovered }
                        Button { text: qsTr("+  Add download"); onClicked: addDialog.open(); contentItem: Text { text: parent.text; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter; font.weight: Font.DemiBold; font.pixelSize: 12 } background: Rectangle { radius: 8; color: parent.hovered ? "#4B92FF" : "#3278E8" } }
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: window.section === "library" ? 90 : 0; visible: window.section === "library"; color: window.bg
                    ColumnLayout { anchors.fill: parent; anchors.leftMargin: 28; anchors.rightMargin: 28; spacing: 5
                        RowLayout { Layout.fillWidth: true; spacing: 8
                            ComboBox { id: categoryBox; Layout.preferredWidth: 150; model: ["", "other", "document", "program", "compressed", "video", "audio"]; displayText: currentText.length === 0 ? qsTr("All categories") : currentText; onActivated: { window.categoryFilter = currentText; window.applyLibraryFilters() } }
                            ComboBox { id: queueBox; Layout.preferredWidth: 130; model: ["", "main"]; displayText: currentText.length === 0 ? qsTr("All queues") : currentText; onActivated: { window.queueFilter = currentText; window.applyLibraryFilters() } }
                            ComboBox { id: sortBox; Layout.preferredWidth: 145; model: ["date", "name", "status", "size", "progress", "speed", "eta", "category", "queue"]; displayText: qsTr("Sort: ") + currentText; onActivated: taskController.setLibrarySort(currentText, descending.checked) }
                            CheckBox { id: descending; text: qsTr("Descending"); checked: true; onToggled: taskController.setLibrarySort(sortBox.currentText, checked) }
                            Item { Layout.fillWidth: true }
                            Label { text: taskController.selectedIds.length > 0 ? qsTr("%1 selected").arg(taskController.selectedIds.length) : qsTr("Ctrl/Cmd-click for multi-select"); color: window.muted; font.pixelSize: 10 }
                        }
                        RowLayout { Layout.fillWidth: true; spacing: 8; Button { text: qsTr("Pause"); enabled: taskController.selectedIds.length > 0; onClicked: taskController.bulkPause() } Button { text: qsTr("Resume"); enabled: taskController.selectedIds.length > 0; onClicked: taskController.bulkResume() } Button { text: qsTr("Retry"); enabled: taskController.selectedIds.length > 0; onClicked: taskController.bulkRetry() } Button { text: qsTr("Delete"); enabled: taskController.selectedIds.length > 0; onClicked: taskController.bulkDelete(false) } ComboBox { id: bulkPriority; model: [qsTr("Critical"), qsTr("High"), qsTr("Normal"), qsTr("Low"), qsTr("Background")]; currentIndex: 2; Layout.preferredWidth: 130 } Button { text: qsTr("Set priority"); enabled: taskController.selectedIds.length > 0; onClicked: taskController.bulkSetPriority(bulkPriority.currentIndex) } Item { Layout.fillWidth: true } Button { text: qsTr("Details"); enabled: taskController.selectedId.length > 0; onClicked: window.detailsOpen = true } Button { text: qsTr("Clear"); enabled: taskController.selectedIds.length > 0; onClicked: taskController.clearSelection() } }
                    }
                }
                StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; Layout.leftMargin: 20; Layout.rightMargin: 20; Layout.bottomMargin: 16; currentIndex: window.section === "queue" ? 1 : window.section === "automation" ? 2 : window.section === "media" ? 3 : window.section === "browser" ? 4 : window.section === "diagnostics" ? 5 : 0
                    Item { Rectangle { anchors.fill: parent; color: window.surface; radius: 12; border.color: window.dark ? "#1E304B" : "#DCE4EF"; ColumnLayout { anchors.fill: parent; spacing: 0
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 42; color: window.dark ? "#122038" : "#F5F8FC"; radius: 12; RowLayout { anchors.fill: parent; anchors.leftMargin: 18; anchors.rightMargin: 18; Label { Layout.preferredWidth: 34; text: "" } Label { Layout.preferredWidth: Math.max(220, parent.width * .29); text: qsTr("NAME"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Label { Layout.preferredWidth: Math.max(125, parent.width * .18); text: qsTr("PROGRESS"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Label { Layout.preferredWidth: Math.max(80, parent.width * .09); text: qsTr("SPEED"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } Label { Layout.preferredWidth: Math.max(60, parent.width * .06); text: qsTr("ETA"); color: window.muted; font.pixelSize: 10; font.weight: Font.DemiBold } } }
                        ListView { id: list; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.filteredDownloads; spacing: 2; visible: count > 0; delegate: DownloadRow { selected: taskController.isSelected(downloadId); compact: settingsService.density === "compact"; onActivated: function(extendSelection) { taskController.toggleSelection(downloadId, !extendSelection) } } ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded } }
                        EmptyState { Layout.fillWidth: true; Layout.fillHeight: true; visible: list.count === 0; title: taskController.connected ? qsTr("No downloads in this view") : qsTr("Waiting for NOVA Core"); subtitle: taskController.connected ? qsTr("Change filters or add a download to see live Core state here.") : taskController.lastError; onActionRequested: addDialog.open() }
                    } } }
                    QueuePage { surface: window.surface; textColor: window.text; muted: window.muted; onAddRequested: addDialog.open() }
                    AutomationPage { surface: window.surface; textColor: window.text; muted: window.muted }
                    MediaPage { surface: window.surface; textColor: window.text; muted: window.muted }
                    IntegrationPage { surface: window.surface; textColor: window.text; muted: window.muted }
                    DiagnosticsPage { surface: window.surface; textColor: window.text; muted: window.muted }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 32; color: window.surface; border.color: window.dark ? "#1D2F4B" : "#DCE5F0"; border.width: 1; RowLayout { anchors.fill: parent; anchors.leftMargin: 25; anchors.rightMargin: 25; Label { text: taskController.connected ? "● " + qsTr("Core online") : "● " + qsTr("Offline"); color: taskController.connected ? "#4CCB9D" : "#FF7181"; font.pixelSize: 10 } Item { Layout.fillWidth: true } Label { text: qsTr("Native Qt Quick UI · authenticated loopback · SSE reconciliation"); color: window.muted; font.pixelSize: 10 } } }
            }
        }
    }
    DetailsDrawer { id: detailsDrawer; visible: window.detailsOpen; onClosed: window.detailsOpen = false }
    AddDownloadDialog { id: addDialog }
    SettingsDialog { id: settingsDialog }
    Rectangle { id: toast; z: 30; visible: window.toastText.length > 0; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 46; width: Math.min(520, toastLabel.implicitWidth + 44); height: 44; radius: 10; color: window.toastError ? "#6A2E40" : "#183A40"; border.color: window.toastError ? "#B85169" : "#2D7371"; Label { id: toastLabel; anchors.centerIn: parent; text: window.toastText; color: "#EFF6FF"; font.pixelSize: 12; elide: Text.ElideRight; width: parent.width - 30; horizontalAlignment: Text.AlignHCenter } }
    Timer { id: toastTimer; interval: 4500; onTriggered: window.toastText = "" }
}
