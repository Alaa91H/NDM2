import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import "components"
import "dialogs"
import "pages"

ApplicationWindow {
    id: window
    width: 1180
    height: 760
    minimumWidth: 820
    minimumHeight: 560
    visible: true
    title: "NDM2"
    readonly property bool dark: settingsService.dark
    color: design.background
    property string section: "library"
    property string statusFilter: ""
    property string categoryFilter: ""
    property string queueFilter: ""
    property bool detailsOpen: false
    property string toastText: ""
    property bool toastError: false
    LayoutMirroring.enabled: settingsService.rightToLeft
    LayoutMirroring.childrenInherit: true

    Theme { id: design; dark: window.dark }
    palette: Palette {
        window: design.background
        windowText: design.textPrimary
        base: design.surface
        alternateBase: design.surfaceSubtle
        text: design.textPrimary
        button: design.surfaceRaised
        buttonText: design.textPrimary
        highlight: design.accent
        highlightedText: "#FFFFFF"
        placeholderText: design.textMuted
        brightText: design.danger
        light: design.borderStrong
        mid: design.border
        dark: design.surfaceSubtle
    }
    function applyLibraryFilters() { taskController.setLibraryFilters(search.text, statusFilter, categoryFilter, queueFilter) }
    function setSection(value, status) { section = value; statusFilter = status || ""; applyLibraryFilters() }
    function pageTitle() { return section === "queue" ? qsTr("Queue") : section === "automation" ? qsTr("Automation") : section === "media" ? qsTr("Media discovery") : section === "browser" ? qsTr("Browser integration") : section === "diagnostics" ? qsTr("Diagnostics") : statusFilter === "downloading" ? qsTr("Active downloads") : statusFilter === "completed" ? qsTr("Completed downloads") : statusFilter === "error" ? qsTr("Failed downloads") : qsTr("Download library") }
    function selectTaskAnd(action) { if (taskController.selectedId.length === 0) return; action() }

    Shortcut { sequence: "Ctrl+N"; onActivated: addDialog.open() }
    Shortcut { sequence: "Ctrl+F"; onActivated: { if (window.section !== "library") window.setSection("library", ""); search.forceActiveFocus() } }
    Shortcut { sequence: "Ctrl+,"; onActivated: settingsDialog.open() }
    Shortcut { sequence: "Ctrl+A"; enabled: window.section === "library"; onActivated: taskController.selectAllFiltered() }
    Shortcut { sequence: "Ctrl+I"; enabled: taskController.selectedId.length > 0; onActivated: window.detailsOpen = true }
    Shortcut { sequence: "Ctrl+D"; enabled: taskController.selectedId.length > 0; onActivated: window.detailsOpen = true }
    Shortcut { sequence: "Ctrl+P"; enabled: taskController.selectedId.length > 0; onActivated: taskController.pauseSelected() }
    Shortcut { sequence: "Ctrl+R"; enabled: taskController.selectedId.length > 0; onActivated: taskController.resumeSelected() }
    Shortcut { sequence: "Space"; context: Qt.WindowShortcut; enabled: window.section === "library" && taskController.selectedId.length > 0 && !addDialog.visible && !settingsDialog.visible && !search.activeFocus; onActivated: { var state = taskController.selectedDownload.status || ""; if (state === "downloading" || state === "active") taskController.pauseSelected(); else taskController.resumeSelected() } }
    Shortcut { sequence: "P"; context: Qt.WindowShortcut; enabled: window.section === "library" && taskController.selectedId.length > 0 && !addDialog.visible && !settingsDialog.visible && !search.activeFocus; onActivated: taskController.pauseSelected() }
    Shortcut { sequence: "R"; context: Qt.WindowShortcut; enabled: window.section === "library" && taskController.selectedId.length > 0 && !addDialog.visible && !settingsDialog.visible && !search.activeFocus; onActivated: taskController.resumeSelected() }
    Shortcut { sequence: "O"; context: Qt.WindowShortcut; enabled: window.section === "library" && (taskController.selectedDownload.savePath || "").length > 0 && !addDialog.visible && !settingsDialog.visible && !search.activeFocus; onActivated: desktopService.openFile(taskController.selectedDownload.savePath) }
    Shortcut { sequence: "Delete"; enabled: taskController.selectedIds.length > 0; onActivated: taskController.bulkDelete(false) }
    Shortcut { sequence: "F5"; onActivated: taskController.refreshAll() }
    Shortcut { sequence: "Escape"; onActivated: { if (window.detailsOpen) window.detailsOpen = false; else taskController.clearSelection() } }

    Connections {
        target: taskController
        function onNotice(message, isError) { window.toastText = message; window.toastError = isError; toastTimer.restart() }
    }

    RowLayout {
        anchors.fill: parent
        spacing: 0
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: window.width < 1110 ? 224 : 252
            color: design.sidebar
            border.color: design.border
            border.width: 1
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: design.spaceMd
                spacing: design.spaceXs
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    Rectangle { width: 36; height: 36; radius: design.radiusSm; color: design.accent; clip: true; Image { anchors.fill: parent; anchors.margins: 3; source: "qrc:/branding/app-icon.png"; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true } }
                    ColumnLayout { spacing: 0; Label { text: "NDM2"; color: design.textPrimary; font.pixelSize: 18; font.weight: Font.Bold } Label { text: qsTr("Native Download Manager"); color: design.textSecondary; font.pixelSize: design.fontMeta } }
                }
                Label { text: qsTr("LIBRARY"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold; Layout.topMargin: design.spaceLg; Layout.leftMargin: design.spaceSm }
                NavItem { label: qsTr("All downloads"); glyph: "▦"; selected: window.section === "library" && window.statusFilter === ""; count: taskController.downloads.count; theme: design; Layout.fillWidth: true; onClicked: window.setSection("library", "") }
                NavItem { label: qsTr("Active"); glyph: "↓"; selected: window.section === "library" && window.statusFilter === "downloading"; count: taskController.downloads.countForStatus("downloading"); theme: design; Layout.fillWidth: true; onClicked: window.setSection("library", "downloading") }
                NavItem { label: qsTr("Completed"); glyph: "✓"; selected: window.section === "library" && window.statusFilter === "completed"; count: taskController.downloads.countForStatus("completed"); theme: design; Layout.fillWidth: true; onClicked: window.setSection("library", "completed") }
                NavItem { label: qsTr("Needs attention"); glyph: "!"; selected: window.section === "library" && window.statusFilter === "error"; count: taskController.downloads.countForStatus("error"); theme: design; Layout.fillWidth: true; onClicked: window.setSection("library", "error") }
                Label { text: qsTr("WORKFLOWS"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold; Layout.topMargin: design.spaceMd; Layout.leftMargin: design.spaceSm }
                NavItem { label: qsTr("Queue"); glyph: "≡"; selected: window.section === "queue"; count: taskController.queueEntries.length; theme: design; Layout.fillWidth: true; onClicked: { window.section = "queue"; taskController.refreshAll() } }
                NavItem { label: qsTr("Automation"); glyph: "⌘"; selected: window.section === "automation"; theme: design; Layout.fillWidth: true; onClicked: { window.section = "automation"; taskController.refreshAll() } }
                NavItem { label: qsTr("Media"); glyph: "▶"; selected: window.section === "media"; theme: design; Layout.fillWidth: true; onClicked: { window.section = "media"; taskController.refreshAll() } }
                NavItem { label: qsTr("Browser"); glyph: "◈"; selected: window.section === "browser"; theme: design; Layout.fillWidth: true; onClicked: { window.section = "browser"; taskController.refreshAll() } }
                NavItem { label: qsTr("Diagnostics"); glyph: "⌁"; selected: window.section === "diagnostics"; theme: design; Layout.fillWidth: true; onClicked: { window.section = "diagnostics"; taskController.refreshAll() } }
                Item { Layout.fillHeight: true }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 66; radius: design.radiusMd; color: taskController.connected ? design.successSoft : design.dangerSoft; border.color: taskController.connected ? Qt.rgba(design.success.r, design.success.g, design.success.b, .35) : Qt.rgba(design.danger.r, design.danger.g, design.danger.b, .35)
                    RowLayout { anchors.fill: parent; anchors.margins: design.spaceSm; spacing: design.spaceSm
                        StatusBadge { status: taskController.connected ? "connected" : "offline"; labelOverride: taskController.connected ? qsTr("Core connected") : qsTr("Core offline"); dark: window.dark; theme: design }
                        ColumnLayout { Layout.fillWidth: true; spacing: 1; Label { Layout.fillWidth: true; text: taskController.connected ? qsTr("Authenticated loopback") : taskController.lastError; color: design.textSecondary; font.pixelSize: design.fontMeta; elide: Text.ElideRight } }
                    }
                }
                ActionButton { Layout.fillWidth: true; text: qsTr("Settings"); tone: "quiet"; dark: window.dark; theme: design; onClicked: settingsDialog.open() }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: design.background
            ColumnLayout {
                anchors.fill: parent
                spacing: 0
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 86
                    color: design.surface
                    border.color: design.border
                    border.width: 1
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: design.spaceXl
                        anchors.rightMargin: design.spaceXl
                        spacing: design.spaceMd
                        ColumnLayout { Layout.fillWidth: true; spacing: 1; Label { text: window.pageTitle(); color: design.textPrimary; font.pixelSize: design.fontPage; font.weight: Font.DemiBold } Label { text: window.section === "library" ? qsTr("%1 visible of %2 tasks from NOVA Core").arg(list.count).arg(taskController.downloads.count) : qsTr("Live state from the authenticated NOVA Core"); color: design.textSecondary; font.pixelSize: design.fontCaption } }
                        ThemedTextField { id: search; visible: window.section === "library"; Layout.preferredWidth: Math.min(320, Math.max(200, window.width * .24)); placeholderText: qsTr("Search name, URL or category  ·  Ctrl+F"); leadingGlyph: "⌕"; assistiveText: qsTr("Filter downloads by name, URL, or category"); Accessible.name: qsTr("Search downloads"); theme: design; dark: window.dark; onTextChanged: window.applyLibraryFilters() }
                        ActionButton { text: "↻  " + qsTr("Refresh"); tone: "secondary"; dark: window.dark; theme: design; onClicked: taskController.refreshAll() }
                        ActionButton { text: "+  " + qsTr("Add download"); tone: "primary"; dark: window.dark; theme: design; onClicked: addDialog.open() }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: window.section === "library" ? 104 : 0
                    visible: window.section === "library"
                    color: design.background
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.leftMargin: design.spaceXl
                        anchors.rightMargin: design.spaceXl
                        spacing: design.spaceXs
                        RowLayout { Layout.fillWidth: true; spacing: design.spaceSm
                            ThemedComboBox { id: categoryBox; theme: design; dark: window.dark; Layout.preferredWidth: 154; model: ["", "other", "document", "program", "compressed", "video", "audio"]; displayText: currentText.length === 0 ? qsTr("All categories") : currentText; onActivated: { window.categoryFilter = currentText; window.applyLibraryFilters() } }
                            ThemedComboBox { id: queueBox; theme: design; dark: window.dark; Layout.preferredWidth: 132; model: ["", "main"]; displayText: currentText.length === 0 ? qsTr("All queues") : currentText; onActivated: { window.queueFilter = currentText; window.applyLibraryFilters() } }
                            ThemedComboBox { id: sortBox; theme: design; dark: window.dark; Layout.preferredWidth: 140; model: ["date", "name", "status", "size", "progress", "speed", "eta", "category", "queue"]; displayText: qsTr("Sort: ") + currentText; onActivated: taskController.setLibrarySort(currentText, descending.checked) }
                            ThemedCheckBox { id: descending; theme: design; dark: window.dark; text: qsTr("Descending"); checked: true; onToggled: taskController.setLibrarySort(sortBox.currentText, checked) }
                            Item { Layout.fillWidth: true }
                            Label { text: taskController.selectedIds.length > 0 ? qsTr("%1 selected").arg(taskController.selectedIds.length) : qsTr("Ctrl/Cmd-click to select multiple"); color: design.textMuted; font.pixelSize: design.fontMeta }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: taskController.selectedIds.length > 0 ? 40 : 0; visible: taskController.selectedIds.length > 0; radius: design.radiusMd; color: design.accentSoft; border.width: 1; border.color: design.borderStrong
                            RowLayout { anchors.fill: parent; anchors.leftMargin: design.spaceSm; anchors.rightMargin: design.spaceSm; spacing: design.spaceXs
                                Label { text: qsTr("Bulk actions"); color: design.textPrimary; font.pixelSize: design.fontCaption; font.weight: Font.DemiBold }
                                ActionButton { text: qsTr("Pause"); tone: "quiet"; dark: window.dark; theme: design; onClicked: taskController.bulkPause() }
                                ActionButton { text: qsTr("Resume"); tone: "quiet"; dark: window.dark; theme: design; onClicked: taskController.bulkResume() }
                                ActionButton { text: qsTr("Retry"); tone: "quiet"; dark: window.dark; theme: design; onClicked: taskController.bulkRetry() }
                                ActionButton { text: qsTr("Delete"); tone: "danger"; dark: window.dark; theme: design; onClicked: taskController.bulkDelete(false) }
                                Item { Layout.fillWidth: true }
                                ActionButton { text: qsTr("Clear selection"); tone: "quiet"; dark: window.dark; theme: design; onClicked: taskController.clearSelection() }
                            }
                        }
                    }
                }
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: design.spaceLg
                    Layout.rightMargin: design.spaceLg
                    Layout.bottomMargin: design.spaceMd
                    currentIndex: window.section === "queue" ? 1 : window.section === "automation" ? 2 : window.section === "media" ? 3 : window.section === "browser" ? 4 : window.section === "diagnostics" ? 5 : 0
                    Item {
                        Rectangle { anchors.fill: parent; color: design.surface; radius: design.radiusLg; border.color: design.border
                            ColumnLayout { anchors.fill: parent; spacing: 0
                                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 40; color: design.surfaceSubtle; radius: design.radiusLg
                                    RowLayout { anchors.fill: parent; anchors.leftMargin: design.spaceLg; anchors.rightMargin: design.spaceLg; spacing: design.spaceMd
                                        Label { Layout.preferredWidth: 34; text: "" }
                                        Label { Layout.preferredWidth: Math.max(205, parent.width * .29); text: qsTr("NAME"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold }
                                        Label { Layout.preferredWidth: Math.max(138, parent.width * .18); text: qsTr("PROGRESS"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold }
                                        Label { Layout.preferredWidth: Math.max(78, parent.width * .085); text: qsTr("SPEED"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold }
                                        Label { Layout.preferredWidth: Math.max(54, parent.width * .06); text: qsTr("ETA"); color: design.textMuted; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold }
                                        Item { Layout.fillWidth: true }
                                    }
                                }
                                ListView { id: list; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.filteredDownloads; spacing: 2; visible: count > 0; delegate: DownloadRow { selected: taskController.isSelected(downloadId); compact: settingsService.density === "compact"; theme: design; dark: window.dark; onActivated: function(extendSelection) { taskController.toggleSelection(downloadId, !extendSelection) } onDetailsRequested: { taskController.selectedId = downloadId; window.detailsOpen = true } onPauseRequested: { taskController.selectedId = downloadId; taskController.pauseSelected() } onResumeRequested: { taskController.selectedId = downloadId; taskController.resumeSelected() } onRetryRequested: { taskController.selectedId = downloadId; taskController.retrySelected() } onCancelRequested: { taskController.selectedId = downloadId; taskController.cancelSelected() } onDeleteRequested: { taskController.selectedId = downloadId; taskController.deleteSelected(false) } } ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded } }
                                EmptyState { Layout.fillWidth: true; Layout.fillHeight: true; visible: list.count === 0; title: taskController.connected ? qsTr("No downloads in this view") : qsTr("Waiting for NOVA Core"); subtitle: taskController.connected ? qsTr("Change filters or add a download to see live Core state here.") : taskController.lastError; state: taskController.connected ? "empty" : "offline"; actionText: taskController.connected ? qsTr("Add download") : qsTr("Refresh connection"); theme: design; onActionRequested: taskController.connected ? addDialog.open() : taskController.refreshAll() }
                            }
                        }
                    }
                    QueuePage { surface: design.surface; textColor: design.textPrimary; muted: design.textSecondary; theme: design; onAddRequested: addDialog.open() }
                    AutomationPage { surface: design.surface; textColor: design.textPrimary; muted: design.textSecondary; theme: design }
                    MediaPage { surface: design.surface; textColor: design.textPrimary; muted: design.textSecondary; theme: design }
                    IntegrationPage { surface: design.surface; textColor: design.textPrimary; muted: design.textSecondary; theme: design }
                    DiagnosticsPage { surface: design.surface; textColor: design.textPrimary; muted: design.textSecondary; theme: design }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 34; color: design.surface; border.color: design.border; border.width: 1
                    RowLayout { anchors.fill: parent; anchors.leftMargin: design.spaceXl; anchors.rightMargin: design.spaceXl
                        StatusBadge { status: taskController.connected ? "connected" : "offline"; labelOverride: taskController.connected ? qsTr("Core online") : qsTr("Offline"); dark: window.dark; theme: design }
                        Label { text: taskController.selectedIds.length > 0 ? qsTr("%1 tasks selected").arg(taskController.selectedIds.length) : qsTr("Ready"); color: design.textSecondary; font.pixelSize: design.fontMeta }
                        Item { Layout.fillWidth: true }
                        Label { text: qsTr("Native Qt Quick · authenticated loopback · SSE reconciliation"); color: design.textMuted; font.pixelSize: design.fontMeta }
                    }
                }
            }
        }
    }
    DetailsDrawer { id: detailsDrawer; visible: window.detailsOpen; onClosed: window.detailsOpen = false }
    AddDownloadDialog { id: addDialog }
    SettingsDialog { id: settingsDialog }
    Rectangle { id: toast; z: 30; visible: window.toastText.length > 0; anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; anchors.bottomMargin: 46; width: Math.min(540, toastLabel.implicitWidth + 44); height: 44; radius: design.radiusMd; color: window.toastError ? design.dangerSoft : design.successSoft; border.color: window.toastError ? design.danger : design.success; Label { id: toastLabel; anchors.centerIn: parent; text: window.toastText; color: design.textPrimary; font.pixelSize: design.fontBody; elide: Text.ElideRight; width: parent.width - 30; horizontalAlignment: Text.AlignHCenter } }
    Timer { id: toastTimer; interval: 4500; onTriggered: window.toastText = "" }
}
