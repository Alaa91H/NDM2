import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root

    property color surface: "#292929"
    property color textColor: "#FFFFFF"
    property color muted: "#A6A6A6"
    property var theme: null
    property int selectedFormatIndex: -1

    function pretty(value) { return value === undefined || value === null || value === "" ? "—" : String(value) }
    function formatLabel(item) { return (item.format_id || "?") + "  ·  " + (item.format || item.ext || qsTr("format")) + "  ·  " + (item.resolution || qsTr("audio")) + (item.filesize ? "  ·  " + Math.round(item.filesize / 1048576) + " MB" : "") }

    ColumnLayout {
        anchors.fill: parent
        spacing: theme ? theme.spaceLg : 16

        SectionHeader {
            title: qsTr("Media discovery")
            subtitle: qsTr("Inspect real formats reported by NOVA, then create a native media task.")
            actionText: qsTr("Refresh engines")
            theme: root.theme
            onActionRequested: taskController.refreshAll()
        }

        InfoCard {
            Layout.fillWidth: true
            theme: root.theme
            emphasized: true
            Label { text: qsTr("Find available formats"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 15; font.weight: Font.DemiBold }
            Label { text: qsTr("NOVA yt-dlp capability determines the formats shown here. No format data is simulated."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12; wrapMode: Text.Wrap }
            GridLayout {
                Layout.fillWidth: true
                columns: 3
                columnSpacing: root.theme ? root.theme.spaceSm : 8
                rowSpacing: root.theme ? root.theme.spaceSm : 8
                ThemedTextField { id: mediaUrl; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Media webpage URL"); leadingGlyph: "↗"; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Media webpage URL") }
                ActionButton { text: qsTr("Probe with NOVA"); tone: "primary"; dark: settingsService.dark; theme: root.theme; enabled: mediaUrl.text.trim().length > 0; onClicked: { root.selectedFormatIndex = -1; taskController.probeMedia(mediaUrl.text) } }
                ThemedTextField { id: outputDir; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Optional destination file path"); leadingGlyph: "▣"; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Media destination") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: root.theme ? root.theme.spaceXs : 4
                    Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: taskController.ffmpegStatus.available ? (root.theme ? root.theme.success : "#6CCB9A") : (root.theme ? root.theme.danger : "#FF99A4") }
                    Label { Layout.fillWidth: true; text: taskController.ffmpegStatus.available ? qsTr("FFmpeg ready") : qsTr("FFmpeg unavailable"); color: root.theme ? root.theme.textSecondary : root.muted; horizontalAlignment: Text.AlignRight; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                }
            }
        }

        InfoCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            theme: root.theme
            ColumnLayout {
                Layout.fillWidth: true
                spacing: root.theme ? root.theme.spaceXs : 4
                RowLayout {
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: taskController.mediaProbeError.length > 0 ? qsTr("NOVA could not inspect this URL") : taskController.mediaProbe.title || qsTr("No media inspected yet"); color: taskController.mediaProbeError.length > 0 ? (root.theme ? root.theme.danger : "#FF99A4") : (root.theme ? root.theme.textPrimary : root.textColor); font.pixelSize: root.theme ? root.theme.fontBodyLarge : 15; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    StatusBadge { status: taskController.mediaProbeError.length > 0 ? "error" : Object.keys(taskController.mediaProbe).length > 0 ? "completed" : "waiting"; labelOverride: taskController.mediaProbeError.length > 0 ? qsTr("Probe failed") : Object.keys(taskController.mediaProbe).length > 0 ? qsTr("Formats ready") : qsTr("Awaiting probe"); dark: settingsService.dark; theme: root.theme }
                }
                Label { Layout.fillWidth: true; visible: taskController.mediaProbeError.length > 0; text: taskController.mediaProbeError; color: root.theme ? root.theme.danger : "#FF99A4"; wrapMode: Text.Wrap; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                Label { Layout.fillWidth: true; visible: taskController.mediaProbe.uploader !== undefined; text: qsTr("Uploader: %1   •   Duration: %2").arg(root.pretty(taskController.mediaProbe.uploader)).arg(root.pretty(taskController.mediaProbe.durationString)); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12; elide: Text.ElideRight }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: root.theme ? root.theme.border : "#454545" }
                ListView {
                    id: formatList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: root.theme ? root.theme.spaceXs : 4
                    visible: (taskController.mediaProbe.formats || []).length > 0
                    model: taskController.mediaProbe.formats || []
                    delegate: Rectangle {
                        required property var modelData
                        width: formatList.width
                        height: root.theme ? 48 : 50
                        radius: root.theme ? root.theme.radiusSm : 6
                        color: root.selectedFormatIndex === index ? (root.theme ? root.theme.selection : "#1B5C7D") : formatMouse.containsMouse ? (root.theme ? root.theme.surfaceHover : "#3A3A3A") : (root.theme ? root.theme.surfaceSubtle : "#252525")
                        border.width: root.selectedFormatIndex === index ? 1 : 0
                        border.color: root.theme ? root.theme.focus : "#60CDFF"
                        MouseArea { id: formatMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedFormatIndex = index }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: root.theme ? root.theme.spaceMd : 12
                            anchors.rightMargin: root.theme ? root.theme.spaceMd : 12
                            spacing: root.theme ? root.theme.spaceSm : 8
                            Rectangle { Layout.preferredWidth: 26; Layout.preferredHeight: 26; radius: root.theme ? root.theme.radiusXs : 4; color: root.selectedFormatIndex === index ? (root.theme ? root.theme.accent : "#60CDFF") : (root.theme ? root.theme.controlFill : "#363636"); Text { anchors.centerIn: parent; text: modelData.vcodec === "none" ? "♪" : "▶"; color: root.selectedFormatIndex === index ? "white" : (root.theme ? root.theme.textSecondary : root.muted); font.pixelSize: 13 } }
                            Label { Layout.fillWidth: true; text: root.formatLabel(modelData); color: root.theme ? root.theme.textPrimary : root.textColor; elide: Text.ElideRight; font.pixelSize: root.theme ? root.theme.fontBody : 13 }
                            Label { text: modelData.ext || "—"; color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
                EmptyState { Layout.fillWidth: true; Layout.fillHeight: true; visible: (taskController.mediaProbe.formats || []).length === 0 && taskController.mediaProbeError.length === 0; title: qsTr("Inspect a media page"); subtitle: qsTr("Paste a supported page URL to receive its real NOVA format list."); state: "empty"; actionText: qsTr("Focus URL"); theme: root.theme; onActionRequested: mediaUrl.forceActiveFocus() }
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.selectedFormatIndex >= 0 && (taskController.mediaProbe.formats || []).length > root.selectedFormatIndex
                    spacing: root.theme ? root.theme.spaceSm : 8
                    Label { Layout.fillWidth: true; text: qsTr("Selected: %1").arg(root.selectedFormatIndex >= 0 && (taskController.mediaProbe.formats || []).length > root.selectedFormatIndex ? root.formatLabel(taskController.mediaProbe.formats[root.selectedFormatIndex]) : "—"); color: root.theme ? root.theme.information : "#75BEFF"; elide: Text.ElideRight; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                    ActionButton { text: qsTr("Create media download"); tone: "primary"; dark: settingsService.dark; theme: root.theme; enabled: root.selectedFormatIndex >= 0 && (taskController.mediaProbe.formats || []).length > root.selectedFormatIndex; onClicked: { var item = taskController.mediaProbe.formats[root.selectedFormatIndex]; taskController.createMediaDownload(mediaUrl.text, taskController.mediaProbe.title || "media-download", outputDir.text, item.format_id, item.vcodec === "none") } }
                }
                ThemedTextArea { visible: Object.keys(taskController.mediaProbe).length > 0; Layout.fillWidth: true; Layout.preferredHeight: 112; readOnly: true; selectByMouse: true; text: JSON.stringify(taskController.mediaProbe, null, 2); monospace: true; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Raw media probe details") }
            }
        }
    }
}
