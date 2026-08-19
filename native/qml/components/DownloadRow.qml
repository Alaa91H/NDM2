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
    property bool selected: false
    property bool compact: false
    signal activated(bool extendSelection)
    height: compact ? 68 : 82
    width: ListView.view ? ListView.view.width : 1000
    function bytes(value) { if (value <= 0) return "—"; var u = ["B", "KB", "MB", "GB", "TB"], i = 0; while (value >= 1024 && i < u.length - 1) { value /= 1024; i++ } return value.toFixed(i === 0 ? 0 : 1) + " " + u[i] }
    function duration(seconds) { if (seconds <= 0 || !isFinite(seconds)) return "—"; var h = Math.floor(seconds / 3600), m = Math.floor((seconds % 3600) / 60), s = Math.floor(seconds % 60); return h > 0 ? h + "h " + m + "m" : m > 0 ? m + "m " + s + "s" : s + "s" }
    function statusColor(value) { return value === "downloading" ? "#45C99A" : value === "completed" ? "#50A7FF" : value === "error" ? "#FF6E7C" : value === "queued" ? "#FFBD59" : "#9AA8BD" }
    function typeGlyph(value) { return value === "video" ? "▻" : value === "audio" ? "♫" : value === "compressed" ? "▤" : value === "program" ? "◆" : value === "document" ? "▧" : "▣" }
    Rectangle {
        anchors.fill: parent; anchors.leftMargin: 6; anchors.rightMargin: 6; radius: 10
        color: root.selected ? "#182F50" : rowMouse.containsMouse ? "#142137" : "transparent"
        border.color: root.selected ? "#2D67B4" : "transparent"; border.width: 1
        MouseArea { id: rowMouse; anchors.fill: parent; hoverEnabled: true; onClicked: function(mouse) { root.activated((mouse.modifiers & Qt.ControlModifier) || (mouse.modifiers & Qt.ShiftModifier)) } onDoubleClicked: root.activated(false) }
        RowLayout { anchors.fill: parent; anchors.leftMargin: 14; anchors.rightMargin: 14; spacing: 12
            CheckBox { checked: root.selected; onToggled: if (activeFocus) root.activated(true) }
            Rectangle { Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: 10; color: "#223654"; Text { anchors.centerIn: parent; text: root.typeGlyph(root.fileType); color: "#8FC0FF"; font.pixelSize: 16; font.weight: Font.DemiBold } }
            ColumnLayout { Layout.preferredWidth: Math.max(220, root.width * .30); Layout.fillHeight: true; spacing: 3
                Label { Layout.fillWidth: true; text: root.name || qsTr("Untitled download"); elide: Text.ElideRight; color: "#EAF1FF"; font.pixelSize: 14; font.weight: Font.Medium }
                Label { Layout.fillWidth: true; text: root.bytes(root.downloadedBytes) + " / " + root.bytes(root.sizeBytes) + (root.category.length > 0 ? " · " + root.category : ""); color: "#8D9AB0"; elide: Text.ElideRight; font.pixelSize: 10 }
                Label { visible: root.errorMessage.length > 0; Layout.fillWidth: true; text: root.errorMessage; elide: Text.ElideRight; color: "#FF8490"; font.pixelSize: 10 }
            }
            ColumnLayout { Layout.preferredWidth: Math.max(125, root.width * .18); spacing: 5
                ProgressBar { Layout.fillWidth: true; from: 0; to: 1; value: root.progress; background: Rectangle { implicitHeight: 6; radius: 3; color: "#23324A" } contentItem: Item { Rectangle { width: parent.visualPosition * parent.width; height: parent.height; radius: 3; color: root.statusColor(root.status) } } }
                Label { text: Math.round(root.progress * 100) + "%"; color: "#AAB8CC"; font.pixelSize: 10 }
            }
            Label { Layout.preferredWidth: Math.max(80, root.width * .09); text: root.bytes(root.speed) + "/s"; color: root.speed > 0 ? "#86D9BD" : "#7F8CA1"; font.pixelSize: 12 }
            Label { Layout.preferredWidth: Math.max(60, root.width * .06); text: root.duration(root.eta); color: "#AAB8CC"; font.pixelSize: 12 }
            Label { Layout.preferredWidth: 34; text: root.connections > 0 ? root.connections : "—"; color: "#AAB8CC"; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
            Rectangle { Layout.preferredWidth: 84; Layout.preferredHeight: 23; radius: 12; color: Qt.rgba(1, 1, 1, .04); border.color: Qt.rgba(1, 1, 1, .08); Row { anchors.centerIn: parent; spacing: 5; Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 6; height: 6; radius: 3; color: root.statusColor(root.status) } Text { text: root.status; color: "#C1CCDA"; font.pixelSize: 10 } } }
        }
    }
}
