import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Dialog {
    id: dialog
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(720, parent ? parent.width - 48 : 720)
    height: Math.min(760, parent ? parent.height - 48 : 760)
    padding: 0
    Theme { id: design; dark: settingsService.dark }
    background: Rectangle { color: design.surface; radius: design.radiusLg; border.color: design.borderStrong; border.width: 1 }
    header: Rectangle { height: 72; color: "transparent"
        RowLayout { anchors.fill: parent; anchors.leftMargin: design.spaceXl; anchors.rightMargin: design.spaceLg
            ColumnLayout { Layout.fillWidth: true; spacing: 2; Label { text: qsTr("Settings"); color: design.textPrimary; font.pixelSize: design.fontSection + 3; font.weight: Font.DemiBold } Label { text: qsTr("Appearance, locale and controls with an observable local or Core effect."); color: design.textSecondary; font.pixelSize: design.fontCaption } }
            IconButton { glyph: "×"; accessibleLabel: qsTr("Close settings"); dark: design.dark; theme: design; onClicked: dialog.close() }
        }
    }
    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth
        contentHeight: settingsGrid.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        GridLayout {
            id: settingsGrid
            columns: 2
            width: availableWidth
        columnSpacing: design.spaceLg
        rowSpacing: design.spaceLg
        ColumnLayout { Layout.fillWidth: true; spacing: design.spaceXs
            Label { text: qsTr("Appearance"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
            Label { text: qsTr("Theme"); color: design.textSecondary; font.pixelSize: design.fontCaption }
            ThemedComboBox { theme: design; dark: design.dark; Layout.fillWidth: true; model: ["system", "dark", "light"]; currentIndex: Math.max(0, model.indexOf(settingsService.theme)); Accessible.name: qsTr("Application theme"); onActivated: settingsService.setTheme(currentText) }
            Label { text: qsTr("Density"); color: design.textSecondary; font.pixelSize: design.fontCaption }
            ThemedComboBox { theme: design; dark: design.dark; Layout.fillWidth: true; model: ["comfortable", "compact"]; currentIndex: Math.max(0, model.indexOf(settingsService.density)); Accessible.name: qsTr("Interface density"); onActivated: settingsService.setDensity(currentText) }
        }
        ColumnLayout { Layout.fillWidth: true; spacing: design.spaceXs
            Label { text: qsTr("Language and direction"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
            Label { text: qsTr("Interface language"); color: design.textSecondary; font.pixelSize: design.fontCaption }
            ThemedComboBox { theme: design; dark: design.dark; Layout.fillWidth: true; model: ["en", "ar", "de", "he", "fa"]; currentIndex: Math.max(0, model.indexOf(settingsService.language)); Accessible.name: qsTr("Interface language"); onActivated: settingsService.setLanguage(currentText) }
            Label { text: settingsService.rightToLeft ? qsTr("Right-to-left layout enabled") : qsTr("Left-to-right layout enabled"); color: design.success; font.pixelSize: design.fontCaption }
        }
        ColumnLayout { Layout.fillWidth: true; spacing: design.spaceXs
            Label { text: qsTr("Core profile and bandwidth"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
            ThemedComboBox { id: profileSelector; theme: design; dark: design.dark; Layout.fillWidth: true; model: taskController.profiles; textRole: "name"; valueRole: "id"; currentIndex: Math.max(0, indexOfValue(taskController.activeProfile)); Accessible.name: qsTr("Core profile"); onActivated: taskController.setActiveProfile(currentValue) }
            RowLayout { Layout.fillWidth: true
                ThemedSpinBox { id: globalLimit; from: 0; to: 1000000; value: taskController.bandwidth.globalLimitKbps || taskController.bandwidth.global_limit_kbps || 0; Layout.fillWidth: true; theme: design; dark: design.dark; Accessible.name: qsTr("Global bandwidth limit in KB per second") }
                ActionButton { text: qsTr("Apply KB/s"); tone: "secondary"; dark: design.dark; theme: design; onClicked: taskController.setBandwidthLimit(globalLimit.value) }
            }
        }
        ColumnLayout { Layout.fillWidth: true; spacing: design.spaceXs
            Label { text: qsTr("Core retry policy"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
            ThemedComboBox { id: retryPreset; theme: design; dark: design.dark; Layout.fillWidth: true; model: ["default", "aggressive", "conservative", "none"]; Accessible.name: qsTr("Retry policy preset") }
            RowLayout { Layout.fillWidth: true
                ActionButton { text: qsTr("Apply preset"); tone: "secondary"; dark: design.dark; theme: design; onClicked: taskController.setRetryPolicyPreset(retryPreset.currentText) }
                Label { Layout.fillWidth: true; text: qsTr("Retries: ") + (taskController.retryPolicy.maxRetries || taskController.retryPolicy.max_retries || "—"); color: design.textMuted; font.pixelSize: design.fontCaption; horizontalAlignment: Text.AlignRight }
            }
        }
        ColumnLayout { Layout.fillWidth: true; spacing: design.spaceXs
            Label { text: qsTr("Download locations"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
            Label { text: qsTr("Default NOVA folder"); color: design.textSecondary; font.pixelSize: design.fontCaption }
            RowLayout {
                Layout.fillWidth: true
                ThemedTextField { id: defaultDownloadFolder; Layout.fillWidth: true; text: settingsService.defaultDownloadFolder; theme: design; dark: design.dark; leadingGlyph: "▣"; Accessible.name: qsTr("Default NOVA download folder") }
                ActionButton { text: qsTr("Browse"); tone: "secondary"; dark: design.dark; theme: design; onClicked: { var folder = desktopService.chooseFolder(); if (folder.length > 0) { defaultDownloadFolder.text = folder; settingsService.setDefaultDownloadFolder(folder) } } }
            }
            RowLayout {
                Layout.fillWidth: true
                ActionButton { text: qsTr("Apply folder"); tone: "quiet"; dark: design.dark; theme: design; onClicked: settingsService.setDefaultDownloadFolder(defaultDownloadFolder.text) }
                Label { Layout.fillWidth: true; text: qsTr("New downloads are routed to category folders under this location."); color: design.textMuted; font.pixelSize: design.fontMeta; wrapMode: Text.Wrap }
            }
        }
        ColumnLayout { Layout.fillWidth: true; spacing: design.spaceXs
            Label { text: qsTr("Notifications"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
            ThemedCheckBox { theme: design; dark: design.dark; text: qsTr("Notify for Core state changes"); checked: settingsService.notificationsEnabled; Accessible.name: text; onToggled: settingsService.setNotificationsEnabled(checked) }
            Label { text: qsTr("Completion, failure, pause and resume are de-duplicated through native desktop notifications."); color: design.textMuted; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
        }
        ColumnLayout { Layout.fillWidth: true; spacing: design.spaceXs
            Label { text: qsTr("Integration and diagnostics"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
            Label { Layout.fillWidth: true; text: taskController.browserHealth.status || qsTr("Browser bridge health is available on the Browser page."); color: design.textMuted; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
            Label { Layout.fillWidth: true; text: qsTr("Logs, capability details and task traces are available on Diagnostics."); color: design.textMuted; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
        }
            Label { Layout.columnSpan: 2; Layout.fillWidth: true; text: qsTr("NDM2 intentionally hides unsupported legacy-only controls rather than simulating their behavior."); wrapMode: Text.Wrap; color: design.textMuted; font.pixelSize: design.fontCaption }
        }
    }
}
