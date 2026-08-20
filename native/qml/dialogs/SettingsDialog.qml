import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Dialog {
    id: dialog

    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(design.dialogMaxWidth, parent ? parent.width - design.dialogInset : design.dialogMaxWidth)
    height: Math.min(design.dialogMaxHeight, parent ? parent.height - design.dialogInset : design.dialogMaxHeight)
    padding: 0
    closePolicy: Popup.CloseOnEscape

    Theme { id: design; dark: settingsService.dark }
    background: Rectangle { color: design.backdrop; radius: design.radiusXl; border.color: design.borderStrong; border.width: 1 }

    header: Rectangle {
        height: 84
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: design.spaceXl
            anchors.rightMargin: design.spaceLg
            spacing: design.spaceSm
            Rectangle { Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: design.radiusSm; color: design.accentSoft; Text { anchors.centerIn: parent; text: "⚙"; color: design.accent; font.pixelSize: 18; font.weight: Font.DemiBold } }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: qsTr("Settings"); color: design.textPrimary; font.pixelSize: design.fontPage; font.weight: Font.DemiBold }
                Label { text: qsTr("Personalize NDM2, choose download locations, and manage real NOVA Core controls."); color: design.textSecondary; font.pixelSize: design.fontCaption; elide: Text.ElideRight; Layout.fillWidth: true }
            }
            IconButton { glyph: "×"; accessibleLabel: qsTr("Close settings"); dark: design.dark; theme: design; onClicked: dialog.close() }
        }
    }

    contentItem: ScrollView {
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        GridLayout {
            id: settingsGrid
            columns: width < 640 ? 1 : 2
            width: availableWidth
            columnSpacing: design.spaceMd
            rowSpacing: design.spaceMd

            InfoCard {
                Layout.fillWidth: true
                theme: design
                Label { text: qsTr("Appearance"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
                Label { text: qsTr("Choose the visual language and information density used across NDM2."); color: design.textSecondary; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: design.spaceSm
                    rowSpacing: design.spaceSm
                    Label { text: qsTr("Theme"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                    ThemedComboBox { theme: design; dark: design.dark; Layout.fillWidth: true; model: ["system", "dark", "light"]; currentIndex: Math.max(0, model.indexOf(settingsService.theme)); Accessible.name: qsTr("Application theme"); onActivated: settingsService.setTheme(currentText) }
                    Label { text: qsTr("Density"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                    ThemedComboBox { theme: design; dark: design.dark; Layout.fillWidth: true; model: ["comfortable", "compact"]; currentIndex: Math.max(0, model.indexOf(settingsService.density)); Accessible.name: qsTr("Interface density"); onActivated: settingsService.setDensity(currentText) }
                }
            }

            InfoCard {
                Layout.fillWidth: true
                theme: design
                Label { text: qsTr("Language and reading direction"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
                Label { text: qsTr("Language changes apply to the native interface and reading direction immediately."); color: design.textSecondary; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
                ThemedComboBox { theme: design; dark: design.dark; Layout.fillWidth: true; model: ["en", "ar", "de", "he", "fa"]; currentIndex: Math.max(0, model.indexOf(settingsService.language)); Accessible.name: qsTr("Interface language"); onActivated: settingsService.setLanguage(currentText) }
                RowLayout { Layout.fillWidth: true; Rectangle { Layout.preferredWidth: 8; Layout.preferredHeight: 8; radius: 4; color: design.success } Label { Layout.fillWidth: true; text: settingsService.rightToLeft ? qsTr("Right-to-left layout is active") : qsTr("Left-to-right layout is active"); color: design.textMuted; font.pixelSize: design.fontCaption } }
            }

            InfoCard {
                Layout.fillWidth: true
                theme: design
                Label { text: qsTr("Download locations"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
                Label { text: qsTr("New downloads follow the NOVA category path convention under this default folder."); color: design.textSecondary; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
                RowLayout {
                    Layout.fillWidth: true
                    ThemedTextField { id: defaultDownloadFolder; Layout.fillWidth: true; text: settingsService.defaultDownloadFolder; theme: design; dark: design.dark; leadingGlyph: "▣"; Accessible.name: qsTr("Default NOVA download folder") }
                    IconButton { glyph: "…"; accessibleLabel: qsTr("Browse download folder"); theme: design; dark: design.dark; onClicked: { var folder = desktopService.chooseFolder(); if (folder.length > 0) { defaultDownloadFolder.text = folder; settingsService.setDefaultDownloadFolder(folder) } } }
                }
                RowLayout { Layout.fillWidth: true; ActionButton { text: qsTr("Apply folder"); tone: "secondary"; dark: design.dark; theme: design; onClicked: settingsService.setDefaultDownloadFolder(defaultDownloadFolder.text) } Item { Layout.fillWidth: true } Label { text: qsTr("Used by new tasks"); color: design.textMuted; font.pixelSize: design.fontCaption } }
            }

            InfoCard {
                Layout.fillWidth: true
                theme: design
                Label { text: qsTr("NOVA Core profile"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
                Label { text: qsTr("Select the active Core profile and apply its confirmed global bandwidth limit."); color: design.textSecondary; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
                ThemedComboBox { id: profileSelector; theme: design; dark: design.dark; Layout.fillWidth: true; model: taskController.profiles; textRole: "name"; valueRole: "id"; currentIndex: Math.max(0, indexOfValue(taskController.activeProfile)); Accessible.name: qsTr("Core profile"); onActivated: taskController.setActiveProfile(currentValue) }
                RowLayout { Layout.fillWidth: true; ThemedSpinBox { id: globalLimit; from: 0; to: 1000000; value: taskController.bandwidth.globalLimitKbps || taskController.bandwidth.global_limit_kbps || 0; Layout.fillWidth: true; theme: design; dark: design.dark; Accessible.name: qsTr("Global bandwidth limit in KB per second") } ActionButton { text: qsTr("Apply KB/s"); tone: "secondary"; dark: design.dark; theme: design; onClicked: taskController.setBandwidthLimit(globalLimit.value) } }
            }

            InfoCard {
                Layout.fillWidth: true
                theme: design
                Label { text: qsTr("Retry behavior"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
                Label { text: qsTr("Choose one of the retry policies exposed by the connected NOVA Core."); color: design.textSecondary; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
                RowLayout { Layout.fillWidth: true; ThemedComboBox { id: retryPreset; theme: design; dark: design.dark; Layout.fillWidth: true; model: ["default", "aggressive", "conservative", "none"]; Accessible.name: qsTr("Retry policy preset") } ActionButton { text: qsTr("Apply"); tone: "secondary"; dark: design.dark; theme: design; onClicked: taskController.setRetryPolicyPreset(retryPreset.currentText) } }
                Label { text: qsTr("Reported retries: %1").arg(taskController.retryPolicy.maxRetries || taskController.retryPolicy.max_retries || "—"); color: design.textMuted; font.pixelSize: design.fontCaption }
            }

            InfoCard {
                Layout.fillWidth: true
                theme: design
                Label { text: qsTr("Notifications"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBodyLarge }
                ThemedCheckBox { theme: design; dark: design.dark; text: qsTr("Notify for NOVA Core state changes"); checked: settingsService.notificationsEnabled; Accessible.name: text; onToggled: settingsService.setNotificationsEnabled(checked) }
                Label { text: qsTr("Completion, failure, pause, and resume events are de-duplicated by the native desktop client."); color: design.textSecondary; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap }
            }

            InfoCard {
                Layout.columnSpan: settingsGrid.columns
                Layout.fillWidth: true
                theme: design
                RowLayout {
                    Layout.fillWidth: true
                    Rectangle { Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: design.radiusSm; color: design.surfaceSubtle; Text { anchors.centerIn: parent; text: "i"; color: design.information; font.pixelSize: 16; font.weight: Font.DemiBold } }
                    ColumnLayout { Layout.fillWidth: true; spacing: 2; Label { text: qsTr("Integration and diagnostics"); color: design.textPrimary; font.weight: Font.DemiBold; font.pixelSize: design.fontBody } Label { Layout.fillWidth: true; text: taskController.browserHealth.status || qsTr("Browser bridge health is available on the Browser page. Logs, capabilities, and task traces are available in Diagnostics."); color: design.textSecondary; font.pixelSize: design.fontCaption; wrapMode: Text.Wrap } }
                }
            }
            Label { Layout.columnSpan: settingsGrid.columns; Layout.fillWidth: true; text: qsTr("NDM2 deliberately does not simulate legacy-only controls. Every option above has a local native effect or a confirmed NOVA Core effect."); wrapMode: Text.Wrap; color: design.textMuted; font.pixelSize: design.fontCaption; Layout.topMargin: design.spaceXs }
        }
    }
}
