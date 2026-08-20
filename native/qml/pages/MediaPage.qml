import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    property int selectedFormatIndex: -1
    function pretty(value) { return value === undefined || value === null || value === "" ? "—" : String(value) }
    function formatLabel(item) { return (item.format_id || "?") + " · " + (item.format || item.ext || "format") + " · " + (item.resolution || "audio") + (item.filesize ? " · " + Math.round(item.filesize / 1048576) + " MB" : "") }
    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout { Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 2; Label { text: qsTr("Media discovery & download"); color: root.textColor; font.pixelSize: 20; font.weight: Font.DemiBold } Label { text: qsTr("Only formats reported by the existing NOVA yt-dlp capability may be selected."); color: root.muted; font.pixelSize: 11 } }
            Button { text: qsTr("Refresh engines"); onClicked: taskController.refreshAll() }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 112; radius: 10; color: Qt.rgba(1,1,1,.035); border.color: Qt.rgba(1,1,1,.08)
            GridLayout { anchors.fill: parent; anchors.margins: 14; columns: 3; columnSpacing: 10; rowSpacing: 8
                TextField { id: mediaUrl; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Media webpage URL") }
                Button { text: qsTr("Probe with Core"); enabled: mediaUrl.text.trim().length > 0; onClicked: { root.selectedFormatIndex = -1; taskController.probeMedia(mediaUrl.text) } }
                TextField { id: outputDir; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Optional destination folder") }
                Label { Layout.fillWidth: true; text: taskController.ffmpegStatus.available ? qsTr("FFmpeg available") : qsTr("FFmpeg unavailable"); color: taskController.ffmpegStatus.available ? "#6ED2A7" : "#FF8794"; horizontalAlignment: Text.AlignRight; font.pixelSize: 11 }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: 12; color: root.surface; border.color: "#233653"
            ColumnLayout { anchors.fill: parent; anchors.margins: 18; spacing: 10
                Label { Layout.fillWidth: true; text: taskController.mediaProbeError.length > 0 ? taskController.mediaProbeError : taskController.mediaProbe.title || qsTr("No media metadata has been requested."); color: taskController.mediaProbeError.length > 0 ? "#FF8794" : root.textColor; font.pixelSize: 15; font.weight: Font.Medium; wrapMode: Text.Wrap }
                Label { Layout.fillWidth: true; visible: taskController.mediaProbe.uploader !== undefined; text: qsTr("Uploader: ") + root.pretty(taskController.mediaProbe.uploader) + " · " + qsTr("Duration: ") + root.pretty(taskController.mediaProbe.durationString); color: root.muted; font.pixelSize: 11 }
                ListView { id: formatList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; visible: (taskController.mediaProbe.formats || []).length > 0; model: taskController.mediaProbe.formats || []
                    delegate: Rectangle { required property var modelData; width: formatList.width; height: 54; radius: 8; color: root.selectedFormatIndex === index ? "#1B3558" : Qt.rgba(1,1,1,.025); border.color: root.selectedFormatIndex === index ? "#4C8FEB" : Qt.rgba(1,1,1,.06)
                        MouseArea { anchors.fill: parent; onClicked: root.selectedFormatIndex = index }
                        RowLayout { anchors.fill: parent; anchors.margins: 10; Label { Layout.fillWidth: true; text: root.formatLabel(modelData); color: root.textColor; elide: Text.ElideRight; font.pixelSize: 12 } Label { text: modelData.ext || "—"; color: root.muted; font.pixelSize: 11 } }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
                Label { visible: (taskController.mediaProbe.formats || []).length === 0 && taskController.mediaProbeError.length === 0; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: qsTr("Probe a supported media page to receive the Core format list."); color: root.muted }
                RowLayout { Layout.fillWidth: true; visible: root.selectedFormatIndex >= 0 && (taskController.mediaProbe.formats || []).length > root.selectedFormatIndex
                    Label { Layout.fillWidth: true; text: qsTr("Selected: ") + (root.selectedFormatIndex >= 0 && (taskController.mediaProbe.formats || []).length > root.selectedFormatIndex ? root.formatLabel(taskController.mediaProbe.formats[root.selectedFormatIndex]) : "—"); color: "#A9C8FA"; elide: Text.ElideRight; font.pixelSize: 11 }
                    Button { text: qsTr("Create media download"); enabled: root.selectedFormatIndex >= 0 && (taskController.mediaProbe.formats || []).length > root.selectedFormatIndex; onClicked: { var item = taskController.mediaProbe.formats[root.selectedFormatIndex]; taskController.createMediaDownload(mediaUrl.text, taskController.mediaProbe.title || "media-download", outputDir.text, item.format_id, item.vcodec === "none") } }
                }
                TextArea { visible: Object.keys(taskController.mediaProbe).length > 0; Layout.fillWidth: true; Layout.preferredHeight: 90; readOnly: true; selectByMouse: true; text: JSON.stringify(taskController.mediaProbe, null, 2); wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 9 }
            }
        }
    }
}
