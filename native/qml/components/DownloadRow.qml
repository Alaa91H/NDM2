import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    required property string downloadId
    required property string name
    required property string status
    required property string fileType
    required property double progress
    required property double speed
    required property double sizeBytes
    required property double downloadedBytes
    required property double eta
    required property int connections
    required property string category
    required property string queueId
    required property string errorMessage
    property string url: ""
    property bool selected: false
    property bool compact: false
    property var theme: null
    property bool dark: true
    signal activated(bool extendSelection)
    signal detailsRequested()
    signal pauseRequested()
    signal resumeRequested()
    signal retryRequested()
    signal cancelRequested()
    signal deleteRequested()

    height: compact ? (theme ? theme.rowHeightCompact : 70) : (theme ? theme.rowHeightComfortable : 86)
    width: ListView.view ? ListView.view.width : 1000
    focus: ListView.isCurrentItem
    Accessible.role: Accessible.ListItem
    Accessible.name: name + ", " + status + ", " + Math.round(progress * 100) + qsTr(" percent")
    Accessible.description: errorMessage.length > 0 ? errorMessage : qsTr("Press Enter to open details. Use the context-menu key for available actions.")
    Keys.onReturnPressed: root.detailsRequested()
    Keys.onEnterPressed: root.detailsRequested()
    Keys.onMenuPressed: contextMenu.popup()

    function bytes(value) { if (value <= 0) return "—"; var u = ["B", "KB", "MB", "GB", "TB"], i = 0; while (value >= 1024 && i < u.length - 1) { value /= 1024; i++ } return value.toFixed(i === 0 ? 0 : 1) + " " + u[i] }
    function duration(seconds) { if (seconds <= 0 || !isFinite(seconds)) return "—"; var h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60), s = Math.floor(seconds % 60); return h > 0 ? h + "h " + m + "m" : m > 0 ? m + "m " + s + "s" : s + "s" }
    function typeGlyph(value) { return value === "video" ? "▶" : value === "audio" ? "♫" : value === "compressed" ? "▤" : value === "program" ? "◆" : value === "document" ? "▧" : "▣" }
    function canPause() { return status === "downloading" || status === "active" }
    function canResume() { return status === "paused" || status === "queued" || status === "waiting" }
    function canRetry() { return status === "error" || status === "failed" || status === "cancelled" }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: theme ? theme.spaceXs : 4
        anchors.rightMargin: theme ? theme.spaceXs : 4
        radius: theme ? theme.radiusSm : 6
        color: root.selected ? (theme ? theme.selection : "#1B5C7D") : rowMouse.containsMouse ? (theme ? theme.surfaceHover : "#3A3A3A") : "transparent"
        border.color: root.selected ? (theme ? theme.focus : "#60CDFF") : "transparent"
        border.width: root.selected ? 1 : 0
        Behavior on color { ColorAnimation { duration: 100 } }

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) { root.activated(false); if (ListView.view) ListView.view.currentIndex = index; contextMenu.popup(rowMouse, mouse.x, mouse.y); return }
                if (ListView.view) ListView.view.currentIndex = index
                root.activated((mouse.modifiers & Qt.ControlModifier) || (mouse.modifiers & Qt.ShiftModifier))
            }
            onDoubleClicked: root.detailsRequested()
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: theme ? theme.spaceMd : 12
            anchors.rightMargin: theme ? theme.spaceMd : 12
            spacing: theme ? theme.spaceSm : 8

            ThemedCheckBox { checked: root.selected; theme: root.theme; dark: root.dark; Accessible.name: qsTr("Select %1").arg(root.name); onToggled: if (activeFocus) root.activated(true) }
            Rectangle { Layout.preferredWidth: compact ? 32 : 36; Layout.preferredHeight: compact ? 32 : 36; radius: theme ? theme.radiusSm : 6; color: root.selected ? (theme ? theme.accent : "#60CDFF") : (theme ? theme.accentSoft : "#17445D"); Text { anchors.centerIn: parent; text: root.typeGlyph(root.fileType); color: root.selected ? "white" : (theme ? theme.accent : "#60CDFF"); font.pixelSize: 15; font.weight: Font.DemiBold } }
            ColumnLayout {
                Layout.preferredWidth: Math.max(205, root.width * .30)
                Layout.fillHeight: true
                spacing: 1
                Label { Layout.fillWidth: true; text: root.name || qsTr("Untitled download"); elide: Text.ElideRight; color: theme ? theme.textPrimary : "#FFFFFF"; font.pixelSize: theme ? theme.fontBody : 13; font.weight: Font.DemiBold; Accessible.name: text }
                Label { Layout.fillWidth: true; text: root.bytes(root.downloadedBytes) + " / " + root.bytes(root.sizeBytes) + (root.category.length > 0 ? "  ·  " + root.category : "") + (root.queueId.length > 0 ? "  ·  " + root.queueId : ""); color: theme ? theme.textSecondary : "#D0D0D0"; elide: Text.ElideRight; font.pixelSize: theme ? theme.fontMeta : 11 }
                Label { visible: root.errorMessage.length > 0; Layout.fillWidth: true; text: root.errorMessage; elide: Text.ElideRight; color: theme ? theme.danger : "#FF99A4"; font.pixelSize: theme ? theme.fontMeta : 11 }
            }
            ColumnLayout {
                Layout.preferredWidth: Math.max(148, root.width * .18)
                spacing: 4
                ProgressBar {
                    Layout.fillWidth: true
                    from: 0; to: 1; value: Math.max(0, Math.min(1, root.progress))
                    Accessible.name: qsTr("Progress %1 percent").arg(Math.round(root.progress * 100))
                    background: Rectangle { implicitHeight: 5; radius: 3; color: theme ? theme.controlFill : "#363636" }
                    contentItem: Item { Rectangle { width: parent.visualPosition * parent.width; height: parent.height; radius: 3; color: theme ? theme.statusColor(root.status) : "#6CCB9A"; Behavior on width { NumberAnimation { duration: theme ? theme.durationNormal : 140 } } } }
                }
                RowLayout { Layout.fillWidth: true; Label { text: Math.round(root.progress * 100) + "%"; color: theme ? theme.textSecondary : "#D0D0D0"; font.pixelSize: theme ? theme.fontMeta : 11 } Item { Layout.fillWidth: true } Label { text: root.connections > 0 ? qsTr("%1 connections").arg(root.connections) : ""; color: theme ? theme.textMuted : "#A6A6A6"; font.pixelSize: theme ? theme.fontMeta : 11 } }
            }
            ColumnLayout { Layout.preferredWidth: Math.max(82, root.width * .085); spacing: 1; Label { text: root.bytes(root.speed) + "/s"; color: root.speed > 0 ? (theme ? theme.success : "#6CCB9A") : (theme ? theme.textMuted : "#A6A6A6"); font.pixelSize: theme ? theme.fontBody : 13; font.weight: Font.Medium } Label { text: qsTr("Speed"); color: theme ? theme.textMuted : "#A6A6A6"; font.pixelSize: theme ? theme.fontMeta : 11 } }
            ColumnLayout { Layout.preferredWidth: Math.max(58, root.width * .06); spacing: 1; Label { text: root.duration(root.eta); color: theme ? theme.textSecondary : "#D0D0D0"; font.pixelSize: theme ? theme.fontBody : 13 } Label { text: qsTr("ETA"); color: theme ? theme.textMuted : "#A6A6A6"; font.pixelSize: theme ? theme.fontMeta : 11 } }
            StatusBadge { Layout.preferredWidth: 96; status: root.status; dark: root.dark; theme: root.theme }
            RowLayout { visible: rowMouse.containsMouse || root.selected; Layout.preferredWidth: visible ? implicitWidth : 0; spacing: 2; IconButton { visible: root.canPause(); glyph: "Ⅱ"; accessibleLabel: qsTr("Pause download"); theme: root.theme; dark: root.dark; onClicked: root.pauseRequested() } IconButton { visible: root.canResume(); glyph: "▶"; accessibleLabel: qsTr("Resume download"); tone: "accent"; theme: root.theme; dark: root.dark; onClicked: root.resumeRequested() } IconButton { visible: root.canRetry(); glyph: "↻"; accessibleLabel: qsTr("Retry download"); theme: root.theme; dark: root.dark; onClicked: root.retryRequested() } }
        }
    }

    FluentMenu {
        id: contextMenu
        theme: root.theme
        dark: root.dark
        MenuItem { text: qsTr("Open details"); onTriggered: root.detailsRequested() }
        MenuSeparator { }
        MenuItem { visible: root.canPause(); text: qsTr("Pause"); onTriggered: root.pauseRequested() }
        MenuItem { visible: root.canResume(); text: qsTr("Resume"); onTriggered: root.resumeRequested() }
        MenuItem { visible: root.canRetry(); text: qsTr("Retry"); onTriggered: root.retryRequested() }
        MenuItem { text: qsTr("Cancel"); enabled: root.status !== "completed" && root.status !== "cancelled"; onTriggered: root.cancelRequested() }
        MenuSeparator { }
        MenuItem { text: qsTr("Delete"); onTriggered: root.deleteRequested() }
    }
}
