import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Dialog {
    id: dialog

    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(720, parent ? parent.width - 48 : 720)
    padding: 0
    closePolicy: Popup.CloseOnEscape
    property bool destinationEdited: false

    Theme { id: design; dark: settingsService.dark }

    function filenameFromUrl(value) {
        var clean = value.trim().split("?")[0].split("#")[0]
        var segment = clean.substring(clean.lastIndexOf("/") + 1)
        try { segment = decodeURIComponent(segment) } catch (error) {}
        return segment.length > 0 && segment !== "index.html" ? segment : qsTr("download")
    }
    function effectiveName() { return nameField.text.trim().length > 0 ? nameField.text.trim() : filenameFromUrl(urlField.text) }
    function updateSuggestedDestination() {
        if (!destinationEdited)
            destinationField.text = settingsService.suggestedDownloadPath(categoryBox.currentText, effectiveName())
    }
    function submit(startImmediately) {
        taskController.add(urlField.text, effectiveName(), destinationField.text, categoryBox.currentText, connectionBox.value, limitBox.value, startImmediately)
        dialog.accept()
    }

    onOpened: {
        destinationEdited = false
        updateSuggestedDestination()
        urlField.forceActiveFocus()
    }

    background: Rectangle { color: design.surface; radius: design.radiusLg; border.color: design.borderStrong; border.width: 1 }

    header: Rectangle {
        height: 82
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: design.spaceXl
            anchors.rightMargin: design.spaceLg
            spacing: design.spaceSm
            Rectangle { Layout.preferredWidth: 38; Layout.preferredHeight: 38; radius: design.radiusMd; color: design.accentSoft; Text { anchors.centerIn: parent; text: "↓"; color: design.accent; font.pixelSize: 20; font.weight: Font.DemiBold } }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Label { text: qsTr("New download"); color: design.textPrimary; font.pixelSize: design.fontSection + 3; font.weight: Font.DemiBold }
                Label { text: qsTr("Saved through NOVA Core using the same NOVA Downloads path convention."); color: design.textSecondary; font.pixelSize: design.fontCaption }
            }
            IconButton { glyph: "×"; accessibleLabel: qsTr("Close add download"); dark: design.dark; theme: design; onClicked: dialog.reject() }
        }
    }

    contentItem: ColumnLayout {
        width: dialog.width - design.spaceXl * 2
        spacing: design.spaceMd

        InfoCard {
            Layout.fillWidth: true
            theme: design
            emphasized: true
            Label { text: qsTr("Download link"); color: design.textPrimary; font.pixelSize: design.fontBody; font.weight: Font.DemiBold }
            ThemedTextField {
                id: urlField
                Layout.fillWidth: true
                placeholderText: "https://"
                leadingGlyph: "↗"
                theme: design
                dark: design.dark
                Accessible.name: qsTr("Download URL")
                Accessible.description: qsTr("Required URL for the download")
                onTextChanged: updateSuggestedDestination()
                Keys.onReturnPressed: if (urlField.text.trim().length > 0) dialog.submit(true)
            }
            Label { text: qsTr("NOVA Core validates this link and owns the task lifecycle after creation."); color: design.textMuted; font.pixelSize: design.fontCaption }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: design.spaceMd
            rowSpacing: design.spaceSm

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Label { text: qsTr("Filename"); color: design.textSecondary; font.pixelSize: design.fontCaption; font.weight: Font.DemiBold }
                ThemedTextField { id: nameField; Layout.fillWidth: true; placeholderText: qsTr("Detected from link when empty"); theme: design; dark: design.dark; leadingGlyph: "□"; Accessible.name: qsTr("Filename"); onTextEdited: updateSuggestedDestination() }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 5
                Label { text: qsTr("Category"); color: design.textSecondary; font.pixelSize: design.fontCaption; font.weight: Font.DemiBold }
                ThemedComboBox { id: categoryBox; Layout.fillWidth: true; model: ["other", "document", "program", "compressed", "video", "audio"]; theme: design; dark: design.dark; Accessible.name: qsTr("Download category"); onActivated: updateSuggestedDestination() }
            }
            ColumnLayout {
                Layout.columnSpan: 2
                Layout.fillWidth: true
                spacing: 5
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: qsTr("Save to"); color: design.textSecondary; font.pixelSize: design.fontCaption; font.weight: Font.DemiBold }
                    Item { Layout.fillWidth: true }
                    Label { text: qsTr("NOVA path"); color: design.accent; font.pixelSize: design.fontMeta; font.weight: Font.DemiBold }
                }
                RowLayout {
                    Layout.fillWidth: true
                    ThemedTextField {
                        id: destinationField
                        Layout.fillWidth: true
                        theme: design
                        dark: design.dark
                        leadingGlyph: "▣"
                        placeholderText: settingsService.suggestedDownloadPath(categoryBox.currentText, effectiveName())
                        Accessible.name: qsTr("Destination file path")
                        onTextEdited: destinationEdited = true
                    }
                    ActionButton {
                        text: qsTr("Browse")
                        tone: "secondary"
                        dark: design.dark
                        theme: design
                        onClicked: {
                            var folder = desktopService.chooseFolder()
                            if (folder.length > 0) {
                                destinationEdited = true
                                destinationField.text = settingsService.composeDownloadPath(folder, effectiveName())
                            }
                        }
                    }
                }
                Label { Layout.fillWidth: true; text: qsTr("Default: %1").arg(settingsService.suggestedDownloadFolder(categoryBox.currentText)); color: design.textMuted; font.pixelSize: design.fontMeta; elide: Text.ElideMiddle }
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: design.border }
        ThemedSwitch { id: advancedToggle; text: qsTr("Show supported advanced options"); theme: design; dark: design.dark; Accessible.name: text }

        InfoCard {
            visible: advancedToggle.checked
            Layout.fillWidth: true
            theme: design
            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: design.spaceMd
                rowSpacing: design.spaceSm
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Label { text: qsTr("Connections"); color: design.textSecondary; font.pixelSize: design.fontCaption; font.weight: Font.DemiBold }
                    ThemedSpinBox { id: connectionBox; Layout.fillWidth: true; from: 0; to: 64; value: 0; theme: design; dark: design.dark; Accessible.name: qsTr("Connections") }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 5
                    Label { text: qsTr("Task bandwidth limit (KB/s)"); color: design.textSecondary; font.pixelSize: design.fontCaption; font.weight: Font.DemiBold }
                    ThemedSpinBox { id: limitBox; Layout.fillWidth: true; from: 0; to: 1000000; value: 0; theme: design; dark: design.dark; Accessible.name: qsTr("Task bandwidth limit") }
                }
                ColumnLayout {
                    Layout.columnSpan: 2
                    Layout.fillWidth: true
                    spacing: 2
                    Label { text: qsTr("Active Core profile"); color: design.textSecondary; font.pixelSize: design.fontCaption; font.weight: Font.DemiBold }
                    Label { Layout.fillWidth: true; text: taskController.activeProfile || qsTr("Core default"); color: design.textPrimary; elide: Text.ElideRight; font.pixelSize: design.fontBody }
                }
            }
        }

        Label { Layout.fillWidth: true; text: qsTr("Queue only creates a paused-ready task. Start now hands the task to NOVA Core immediately. Both use the authenticated loopback API."); wrapMode: Text.Wrap; color: design.textMuted; font.pixelSize: design.fontCaption }
    }

    footer: Rectangle {
        height: 74
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: design.spaceXl
            anchors.rightMargin: design.spaceXl
            spacing: design.spaceSm
            ActionButton { text: qsTr("Queue only"); tone: "secondary"; dark: design.dark; theme: design; enabled: urlField.text.trim().length > 0; onClicked: dialog.submit(false) }
            ActionButton { text: qsTr("Start now"); tone: "primary"; dark: design.dark; theme: design; enabled: urlField.text.trim().length > 0; onClicked: dialog.submit(true) }
            Item { Layout.fillWidth: true }
            ActionButton { text: qsTr("Cancel"); tone: "quiet"; dark: design.dark; theme: design; onClicked: dialog.reject() }
        }
    }
}
