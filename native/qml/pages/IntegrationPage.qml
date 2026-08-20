import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

WorkspaceWindow {
    id: root

    pageTitle: qsTr("Browser integration")
    pageSubtitle: qsTr("Secure extension and native-messaging bridge status from NOVA Core.")
    glyph: "◈"
    statusText: root.bridgeOnline() ? qsTr("Bridge connected") : qsTr("Checking bridge")
    actionText: qsTr("Refresh status")
    onActionRequested: taskController.refreshAll()

    property color surface: "#292929"
    property color textColor: "#FFFFFF"
    property color muted: "#A6A6A6"

    function bridgeOnline() {
        var value = taskController.browserHealth.status || taskController.browserHealth.ok || ""
        return value === true || String(value).toLowerCase() === "connected" || String(value).toLowerCase() === "ok" || String(value).toLowerCase() === "healthy"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: theme ? theme.spaceLg : 16

        InfoCard {
            Layout.fillWidth: true
            theme: root.theme
            emphasized: true
            RowLayout {
                Layout.fillWidth: true
                Rectangle { Layout.preferredWidth: 42; Layout.preferredHeight: 42; radius: root.theme ? root.theme.radiusMd : 8; color: root.bridgeOnline() ? (root.theme ? root.theme.successSoft : "#183C2B") : (root.theme ? root.theme.warningSoft : "#493A1C"); Text { anchors.centerIn: parent; text: root.bridgeOnline() ? "✓" : "◈"; color: root.bridgeOnline() ? (root.theme ? root.theme.success : "#6CCB9A") : (root.theme ? root.theme.warning : "#F5C96A"); font.pixelSize: 20; font.weight: Font.DemiBold } }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Label { text: root.bridgeOnline() ? qsTr("Browser bridge is ready") : qsTr("Browser bridge status"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 15; font.weight: Font.DemiBold }
                    Label { Layout.fillWidth: true; text: taskController.browserHealth.status || taskController.browserHealth.ok || qsTr("No bridge status reported by NOVA Core yet."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12; elide: Text.ElideRight }
                }
                StatusBadge { status: root.bridgeOnline() ? "completed" : "waiting"; labelOverride: root.bridgeOnline() ? qsTr("Connected") : qsTr("Checking"); dark: settingsService.dark; theme: root.theme }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: width < 620 ? 1 : 2
            columnSpacing: theme ? theme.spaceMd : 12
            rowSpacing: theme ? theme.spaceMd : 12
            Repeater {
                model: [
                    [qsTr("Native messaging"), taskController.browserHealth.nativeMessaging || taskController.browserHealth.native_messaging || "—", "⌁"],
                    [qsTr("Extension version"), taskController.browserHealth.version || "—", "◫"],
                    [qsTr("Core endpoint"), taskController.endpoint || "loopback", "⌂"],
                    [qsTr("Authentication"), qsTr("Authenticated loopback bridge"), "✓"]
                ]
                delegate: InfoCard {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: 94
                    theme: root.theme
                    contentPadding: theme ? theme.spaceMd : 12
                    RowLayout {
                        Layout.fillWidth: true
                        Rectangle { Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: root.theme ? root.theme.radiusXs : 4; color: root.theme ? root.theme.surfaceSubtle : "#252525"; Text { anchors.centerIn: parent; text: modelData[2]; color: root.theme ? root.theme.information : "#75BEFF"; font.pixelSize: 14 } }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            Label { text: modelData[0]; color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
                            Label { Layout.fillWidth: true; text: modelData[1]; color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBody : 13; font.weight: Font.Medium; elide: Text.ElideRight }
                        }
                    }
                }
            }
        }

        InfoCard {
            Layout.fillWidth: true
            theme: root.theme
            RowLayout {
                Layout.fillWidth: true
                Rectangle { Layout.preferredWidth: 28; Layout.preferredHeight: 28; radius: root.theme ? root.theme.radiusXs : 4; color: root.theme ? root.theme.accentSoft : "#17445D"; Text { anchors.centerIn: parent; text: "i"; color: root.theme ? root.theme.accent : "#60CDFF"; font.pixelSize: 15; font.weight: Font.DemiBold } }
                Label { Layout.fillWidth: true; text: qsTr("Browser configuration, installation, and authentication remain owned by the existing secured NOVA extension/native-messaging flow. NDM2 opens no additional network endpoint."); wrapMode: Text.Wrap; color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 12 }
            }
        }
    }
}
