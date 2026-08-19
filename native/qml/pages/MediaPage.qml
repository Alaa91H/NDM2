import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: root
    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    function pretty(value) { return value === undefined || value === null || value === "" ? "—" : String(value) }
    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout { Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 2; Label { text: qsTr("Media discovery"); color: root.textColor; font.pixelSize: 20; font.weight: Font.DemiBold } Label { text: qsTr("Formats and metadata are shown only when the existing yt-dlp Core integration reports them."); color: root.muted; font.pixelSize: 11 } }
            Button { text: qsTr("Refresh engines"); onClicked: taskController.refreshAll() }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 100; radius: 10; color: Qt.rgba(1,1,1,.035); border.color: Qt.rgba(1,1,1,.08)
            RowLayout { anchors.fill: parent; anchors.margins: 14; spacing: 10
                TextField { id: mediaUrl; Layout.fillWidth: true; placeholderText: qsTr("Media URL") }
                Button { text: qsTr("Probe with Core"); enabled: mediaUrl.text.trim().length > 0; onClicked: taskController.probeMedia(mediaUrl.text) }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.fillHeight: true; radius: 12; color: root.surface; border.color: "#233653"
            Flickable { anchors.fill: parent; anchors.margins: 18; contentWidth: width; contentHeight: content.implicitHeight; clip: true
                ColumnLayout { id: content; width: parent.width; spacing: 12
                    Label { Layout.fillWidth: true; text: taskController.mediaProbeError.length > 0 ? taskController.mediaProbeError : taskController.mediaProbe.title || qsTr("No media metadata has been requested."); color: taskController.mediaProbeError.length > 0 ? "#FF8794" : root.textColor; font.pixelSize: 15; font.weight: Font.Medium; wrapMode: Text.Wrap }
                    GridLayout { Layout.fillWidth: true; columns: 2; visible: Object.keys(taskController.mediaProbe).length > 0; columnSpacing: 22; rowSpacing: 12
                        Repeater { model: [[qsTr("Uploader"), root.pretty(taskController.mediaProbe.uploader)], [qsTr("Duration"), root.pretty(taskController.mediaProbe.duration)], [qsTr("Source"), root.pretty(taskController.mediaProbe.url)], [qsTr("FFmpeg"), root.pretty(taskController.ffmpegStatus.available)]]
                            delegate: ColumnLayout { required property var modelData; Layout.fillWidth: true; spacing: 3; Label { text: modelData[0]; color: root.muted; font.pixelSize: 10 } Label { Layout.fillWidth: true; text: modelData[1]; color: root.textColor; elide: Text.ElideRight; font.pixelSize: 12 } }
                        }
                    }
                    Label { visible: Object.keys(taskController.mediaProbe).length > 0; Layout.fillWidth: true; text: qsTr("Raw Core metadata"); color: root.muted; font.pixelSize: 11; font.weight: Font.DemiBold }
                    TextArea { visible: Object.keys(taskController.mediaProbe).length > 0; Layout.fillWidth: true; Layout.preferredHeight: 220; readOnly: true; selectByMouse: true; text: JSON.stringify(taskController.mediaProbe, null, 2); wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 10 }
                    Label { Layout.fillWidth: true; text: qsTr("Creating media tasks is withheld until a probe reports Core-supported formats and the native option mapper is completed. NDM2 does not invent format lists."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 11 }
                }
            }
        }
    }
}
