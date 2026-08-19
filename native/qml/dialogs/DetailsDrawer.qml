import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Drawer {
    id: drawer
    edge: Qt.RightEdge; modal: false; interactive: true; width: Math.min(470, parent ? parent.width * .42 : 470); height: parent ? parent.height : 800
    property var task: taskController.selectedDownload
    background: Rectangle { color: "#101C30"; border.color: "#2A4266"; border.width: 1 }
    ColumnLayout { anchors.fill: parent; anchors.margins: 22; spacing: 16
        RowLayout { Layout.fillWidth: true; Label { Layout.fillWidth: true; text: drawer.task.name || qsTr("Download details"); elide: Text.ElideRight; color: "#F1F6FF"; font.pixelSize: 18; font.weight: Font.DemiBold } ToolButton { text: "×"; font.pixelSize: 22; onClicked: drawer.close() } }
        Label { Layout.fillWidth: true; text: drawer.task.url || ""; color: "#8391A8"; font.pixelSize: 11; elide: Text.ElideMiddle }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: "#263955" }
        GridLayout { Layout.fillWidth: true; columns: 2; columnSpacing: 20; rowSpacing: 16
            Repeater { model: [ [qsTr("Status"), drawer.task.status || "—"], [qsTr("Progress"), Math.round((drawer.task.progress || 0) * 100) + "%"], [qsTr("Speed"), drawer.task.speed > 0 ? Math.round(drawer.task.speed / 1024) + " KB/s" : "—"], [qsTr("Connections"), drawer.task.connections || "—"], [qsTr("Segments"), (drawer.task.completedSegments || 0) + " / " + (drawer.task.totalSegments || 0)], [qsTr("Retries"), drawer.task.retries || 0] ]
                delegate: ColumnLayout { Layout.fillWidth: true; spacing: 3; Label { text: modelData[0]; color: "#8492A8"; font.pixelSize: 11 } Label { text: modelData[1]; color: "#DFE8F7"; font.pixelSize: 14; font.weight: Font.Medium } }
            }
        }
        Label { text: qsTr("Live speed"); color: "#DCE6F8"; font.pixelSize: 13; font.weight: Font.DemiBold }
        SpeedGraph { Layout.fillWidth: true; Layout.preferredHeight: 145; samples: taskController.speedSamples }
        Label { visible: (drawer.task.errorMessage || "").length > 0; Layout.fillWidth: true; text: drawer.task.errorMessage || ""; wrapMode: Text.Wrap; color: "#FF8894"; font.pixelSize: 12 }
        Item { Layout.fillHeight: true }
        RowLayout { Layout.fillWidth: true; Button { text: qsTr("Open file"); enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.openFile(drawer.task.savePath) } Button { text: qsTr("Show folder"); enabled: (drawer.task.savePath || "").length > 0; onClicked: desktopService.revealFile(drawer.task.savePath) } Item { Layout.fillWidth: true } Button { text: qsTr("Retry"); onClicked: taskController.retrySelected() } }
    }
}
