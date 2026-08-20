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
    height: compact ? 70 : 88
    width: ListView.view ? ListView.view.width : 1000
    function bytes(value) { if (value <= 0) return "—"; var u = ["B", "KB", "MB", "GB", "TB"], i = 0; while (value >= 1024 && i < u.length - 1) { value /= 1024; i++ } return value.toFixed(i === 0 ? 0 : 1) + " " + u[i] }
    function duration(seconds) { if (seconds <= 0 || !isFinite(seconds)) return "—"; var h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60), s = Math.floor(seconds % 60); return h > 0 ? h + "h " + m + "m" : m > 0 ? m + "m " + s + "s" : s + "s" }
    function typeGlyph(value) { return value === "video" ? "▶" : value === "audio" ? "♫" : value === "compressed" ? "▤" : value === "program" ? "◆" : value === "document" ? "▧" : "▣" }
    function canPause() { return status === "downloading" || status === "active" }
    function canResume() { return status === "paused" || status === "queued" || status === "waiting" }
    function canRetry() { return status === "error" || status === "failed" || status === "cancelled" }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 5
        anchors.rightMargin: 5
        radius: theme ? theme.radiusMd : 10
        color: root.selected ? (theme ? theme.selection : "#182F50") : rowMouse.containsMouse ? (theme ? theme.surfaceSubtle : "#142137") : "transparent"
        border.color: root.selected ? (theme ? theme.borderStrong : "#2D67B4") : rowMouse.containsMouse ? (theme ? theme.border : "transparent") : "transparent"
        border.width: root.selected ? 1 : 1
        Behavior on color { ColorAnimation { duration: 100 } }
        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) { root.activated(false); contextMenu.popup(); return }
                root.activated((mouse.modifiers & Qt.ControlModifier) || (mouse.modifiers & Qt.ShiftModifier))
            }
            onDoubleClicked: root.detailsRequested()
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: theme ? theme.spaceMd : 14
            anchors.rightMargin: theme ? theme.spaceMd : 14
            spacing: theme ? theme.spaceMd : 12
            CheckBox { checked: root.selected; Accessible.name: qsTr("Select %1").arg(root.name); onToggled: if (activeFocus) root.activated(true) }
            Rectangle { Layout.preferredWidth: 38; Layout.preferredHeight: 38; radius: theme ? theme.radiusSm : 10; color: theme ? theme.accentSoft : "#223654"; Text { anchors.centerIn: parent; text: root.typeGlyph(root.fileType); color: theme ? theme.information : "#8FC0FF"; font.pixelSize: 16; font.weight: Font.DemiBold } }
            ColumnLayout { Layout.preferredWidth: Math.max(205, root.width * .30); Layout.fillHeight: true; spacing: 2
                Label { Layout.fillWidth: true; text: root.name || qsTr("Untitled download"); elide: Text.ElideRight; color: theme ? theme.textPrimary : "#EAF1FF"; font.pixelSize: theme ? theme.fontBodyLarge : 14; font.weight: Font.Medium; Accessible.name: text }
                Label { Layout.fillWidth: true; text: root.bytes(root.downloadedBytes) + " / " + root.bytes(root.sizeBytes) + (root.category.length > 0 ? "  ·  " + root.category : "") + (root.queueId.length > 0 ? "  ·  " + root.queueId : ""); color: theme ? theme.textSecondary : "#8D9AB0"; elide: Text.ElideRight; font.pixelSize: theme ? theme.fontMeta : 10 }
                Label { visible: root.errorMessage.length > 0; Layout.fillWidth: true; text: root.errorMessage; elide: Text.ElideRight; color: theme ? theme.danger : "#FF8490"; font.pixelSize: theme ? theme.fontMeta : 10 }
            }
            ColumnLayout { Layout.preferredWidth: Math.max(138, root.width * .18); spacing: 5
                ProgressBar { Layout.fillWidth: true; from: 0; to: 1; value: Math.max(0, Math.min(1, root.progress)); Accessible.name: qsTr("Progress %1 percent").arg(Math.round(root.progress * 100)); background: Rectangle { implicitHeight: 6; radius: 3; color: theme ? theme.border : "#23324A" } contentItem: Item { Rectangle { width: parent.visualPosition * parent.width; height: parent.height; radius: 3; color: theme ? theme.statusColor(root.status) : "#58D6A3"; Behavior on width { NumberAnimation { duration: 140 } } } } }
                RowLayout { Layout.fillWidth: true; Label { text: Math.round(root.progress * 100) + "%"; color: theme ? theme.textSecondary : "#AAB8CC"; font.pixelSize: theme ? theme.fontMeta : 10 } Item { Layout.fillWidth: true } Label { text: root.connections > 0 ? qsTr("%1 connections").arg(root.connections) : ""; color: theme ? theme.textMuted : "#7F8CA1"; font.pixelSize: theme ? theme.fontMeta : 10 } }
            }
            ColumnLayout { Layout.preferredWidth: Math.max(78, root.width * .085); spacing: 2; Label { text: root.bytes(root.speed) + "/s"; color: root.speed > 0 ? (theme ? theme.success : "#86D9BD") : (theme ? theme.textMuted : "#7F8CA1"); font.pixelSize: theme ? theme.fontBody : 12; font.weight: Font.Medium } Label { text: qsTr("Speed"); color: theme ? theme.textMuted : "#7F8CA1"; font.pixelSize: theme ? theme.fontMeta : 10 } }
            ColumnLayout { Layout.preferredWidth: Math.max(54, root.width * .06); spacing: 2; Label { text: root.duration(root.eta); color: theme ? theme.textSecondary : "#AAB8CC"; font.pixelSize: theme ? theme.fontBody : 12 } Label { text: qsTr("ETA"); color: theme ? theme.textMuted : "#7F8CA1"; font.pixelSize: theme ? theme.fontMeta : 10 } }
            StatusBadge { Layout.preferredWidth: 92; status: root.status; dark: root.dark; theme: root.theme }
            RowLayout { visible: rowMouse.containsMouse || root.selected; Layout.preferredWidth: visible ? implicitWidth : 0; spacing: 2
                ToolButton { visible: root.canPause(); text: "Ⅱ"; Accessible.name: qsTr("Pause download"); ToolTip.text: qsTr("Pause"); ToolTip.visible: hovered; onClicked: root.pauseRequested() }
                ToolButton { visible: root.canResume(); text: "▶"; Accessible.name: qsTr("Resume download"); ToolTip.text: qsTr("Resume"); ToolTip.visible: hovered; onClicked: root.resumeRequested() }
                ToolButton { visible: root.canRetry(); text: "↻"; Accessible.name: qsTr("Retry download"); ToolTip.text: qsTr("Retry"); ToolTip.visible: hovered; onClicked: root.retryRequested() }
                ToolButton { text: "⋮"; Accessible.name: qsTr("Download actions"); ToolTip.text: qsTr("More actions"); ToolTip.visible: hovered; onClicked: contextMenu.popup() }
            }
        }
    }
    Menu {
        id: contextMenu
        MenuItem { text: qsTr("Open details"); onTriggered: root.detailsRequested() }
        MenuSeparator {}
        MenuItem { visible: root.canPause(); text: qsTr("Pause"); onTriggered: root.pauseRequested() }
        MenuItem { visible: root.canResume(); text: qsTr("Resume"); onTriggered: root.resumeRequested() }
        MenuItem { visible: root.canRetry(); text: qsTr("Retry"); onTriggered: root.retryRequested() }
        MenuItem { text: qsTr("Cancel"); enabled: root.status !== "completed" && root.status !== "cancelled"; onTriggered: root.cancelRequested() }
        MenuSeparator {}
        MenuItem { text: qsTr("Delete"); onTriggered: root.deleteRequested() }
    }
}
