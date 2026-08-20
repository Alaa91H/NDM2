import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Dialog {
    id: dialog
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(680, parent ? parent.width - 48 : 680)
    padding: 0
    closePolicy: Popup.CloseOnEscape
    Theme { id: design; dark: settingsService.dark }
    onOpened: urlField.forceActiveFocus()
    background: Rectangle { color: design.surface; radius: design.radiusLg; border.color: design.borderStrong; border.width: 1 }
    header: Rectangle {
        height: 76
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: design.spaceXl
            anchors.rightMargin: design.spaceLg
            ColumnLayout { spacing: 2
                Label { text: qsTr("Add download"); color: design.textPrimary; font.pixelSize: design.fontSection + 3; font.weight: Font.DemiBold }
                Label { text: qsTr("Start with a link. Core validates and creates the task."); color: design.textSecondary; font.pixelSize: design.fontCaption }
            }
            Item { Layout.fillWidth: true }
            ToolButton { text: "×"; font.pixelSize: 22; Accessible.name: qsTr("Close add download"); onClicked: dialog.reject() }
        }
    }
    contentItem: ColumnLayout {
        width: dialog.width - design.spaceXl * 2
        spacing: design.spaceMd
        Label { text: qsTr("Download URL"); color: design.textPrimary; font.pixelSize: design.fontBody; font.weight: Font.DemiBold }
        TextField { id: urlField; Layout.fillWidth: true; placeholderText: "https://"; selectByMouse: true; Accessible.name: qsTr("Download URL"); Accessible.description: qsTr("Required URL for the download")
            background: Rectangle { radius: design.radiusSm; color: design.surfaceSubtle; border.width: urlField.activeFocus ? 2 : 1; border.color: urlField.activeFocus ? design.accent : design.border }
            Keys.onReturnPressed: if (urlField.text.trim().length > 0) addButton.clicked()
        }
        GridLayout { columns: 2; columnSpacing: design.spaceMd; rowSpacing: design.spaceSm; Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 5
                Label { text: qsTr("Filename"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                TextField { id: nameField; Layout.fillWidth: true; placeholderText: qsTr("Optional — Core detects when available"); Accessible.name: qsTr("Filename") }
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 5
                Label { text: qsTr("Category"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                ComboBox { id: categoryBox; Layout.fillWidth: true; model: ["other", "document", "program", "compressed", "video", "audio"]; Accessible.name: qsTr("Download category") }
            }
            ColumnLayout { Layout.columnSpan: 2; Layout.fillWidth: true; spacing: 5
                Label { text: qsTr("Destination"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                RowLayout { Layout.fillWidth: true
                    TextField { id: destinationField; Layout.fillWidth: true; placeholderText: qsTr("Optional — use NOVA Core default"); Accessible.name: qsTr("Destination folder") }
                    ActionButton { text: qsTr("Browse"); tone: "secondary"; dark: design.dark; theme: design; onClicked: destinationField.text = desktopService.chooseFolder() }
                }
            }
        }
        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: design.border }
        CheckBox { id: advancedToggle; text: qsTr("Show supported advanced options"); Accessible.name: text }
        GridLayout { visible: advancedToggle.checked; Layout.fillWidth: true; columns: 2; columnSpacing: design.spaceMd; rowSpacing: design.spaceSm
            ColumnLayout { Layout.fillWidth: true; spacing: 5
                Label { text: qsTr("Connections"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                SpinBox { id: connectionBox; Layout.fillWidth: true; from: 0; to: 64; value: 0; editable: true; Accessible.name: qsTr("Connections") }
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 5
                Label { text: qsTr("Task bandwidth limit (KB/s)"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                SpinBox { id: limitBox; Layout.fillWidth: true; from: 0; to: 1000000; value: 0; editable: true; Accessible.name: qsTr("Task bandwidth limit") }
            }
            ColumnLayout { Layout.columnSpan: 2; Layout.fillWidth: true; spacing: 3
                Label { text: qsTr("Active Core profile"); color: design.textSecondary; font.pixelSize: design.fontCaption }
                Label { Layout.fillWidth: true; text: taskController.activeProfile || qsTr("Core default"); color: design.textPrimary; elide: Text.ElideRight; font.pixelSize: design.fontBody }
            }
        }
        CheckBox { id: startNow; text: qsTr("Start immediately"); checked: true; Accessible.name: text }
        Label { Layout.fillWidth: true; text: qsTr("Only fields supported by NOVA Core are sent. More task controls are available after creation."); wrapMode: Text.Wrap; color: design.textMuted; font.pixelSize: design.fontCaption }
    }
    footer: Rectangle {
        height: 70
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: design.spaceXl
            anchors.rightMargin: design.spaceXl
            Item { Layout.fillWidth: true }
            ActionButton { text: qsTr("Cancel"); tone: "quiet"; dark: design.dark; theme: design; onClicked: dialog.reject() }
            ActionButton {
                id: addButton
                text: qsTr("Add download")
                tone: "primary"
                dark: design.dark
                theme: design
                enabled: urlField.text.trim().length > 0
                onClicked: { taskController.add(urlField.text, nameField.text, destinationField.text, categoryBox.currentText, connectionBox.value, limitBox.value, startNow.checked); dialog.accept() }
            }
        }
    }
}
