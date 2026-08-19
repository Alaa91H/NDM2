import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog
    modal: true
    anchors.centerIn: Overlay.overlay
    width: 650
    padding: 0
    property color panelColor: "#152238"
    background: Rectangle { color: dialog.panelColor; radius: 14; border.color: "#2A4266" }
    header: Rectangle {
        height: 68
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 18
            ColumnLayout {
                spacing: 2
                Label { text: qsTr("Add download"); color: "#F1F6FF"; font.pixelSize: 19; font.weight: Font.DemiBold }
                Label { text: qsTr("Create a task using the actual NOVA Core contract"); color: "#8E9BB1"; font.pixelSize: 12 }
            }
            Item { Layout.fillWidth: true }
            ToolButton { text: "×"; font.pixelSize: 23; onClicked: dialog.reject() }
        }
    }
    contentItem: ColumnLayout {
        width: dialog.width - 48
        spacing: 14
        Label { text: qsTr("Download URL"); color: "#BFCBE0"; font.pixelSize: 12; font.weight: Font.DemiBold }
        TextField { id: urlField; Layout.fillWidth: true; placeholderText: "https://"; selectByMouse: true }
        GridLayout {
            columns: 2
            columnSpacing: 14
            rowSpacing: 12
            Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 6
                Label { text: qsTr("Filename (optional)") }
                TextField { id: nameField; Layout.fillWidth: true; placeholderText: qsTr("Core will detect when available") }
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 6
                Label { text: qsTr("Category") }
                ComboBox { id: categoryBox; Layout.fillWidth: true; model: ["other", "document", "program", "compressed", "video", "audio"] }
            }
            ColumnLayout { Layout.columnSpan: 2; Layout.fillWidth: true; spacing: 6
                Label { text: qsTr("Destination (optional)") }
                RowLayout {
                    Layout.fillWidth: true
                    TextField { id: destinationField; Layout.fillWidth: true; placeholderText: qsTr("Use the NOVA Core default") }
                    Button { text: qsTr("Browse"); onClicked: destinationField.text = desktopService.chooseFolder() }
                }
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 6
                Label { text: qsTr("Active Core profile") }
                Label { Layout.fillWidth: true; text: taskController.activeProfile || qsTr("Core default"); color: "#C9D5E8"; elide: Text.ElideRight }
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 6
                Label { text: qsTr("Connections") }
                SpinBox { id: connectionBox; Layout.fillWidth: true; from: 0; to: 64; value: 0; editable: true }
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 6
                Label { text: qsTr("Task bandwidth limit (KB/s)") }
                SpinBox { id: limitBox; Layout.fillWidth: true; from: 0; to: 1000000; value: 0; editable: true }
            }
        }
        CheckBox { id: startNow; text: qsTr("Start immediately"); checked: true }
        Label { Layout.fillWidth: true; text: qsTr("Only daemon-supported fields are submitted: URL, name, destination, category, connections, task limit and start state. Scheduling, priority and queue selection remain hidden until confirmed creation APIs are mapped."); wrapMode: Text.Wrap; color: "#73829A"; font.pixelSize: 11 }
    }
    footer: Rectangle {
        height: 68
        color: "transparent"
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            Item { Layout.fillWidth: true }
            Button { text: qsTr("Cancel"); flat: true; onClicked: dialog.reject() }
            Button {
                text: qsTr("Add download")
                enabled: urlField.text.trim().length > 0
                onClicked: {
                    taskController.add(urlField.text, nameField.text, destinationField.text, categoryBox.currentText, connectionBox.value, limitBox.value, startNow.checked)
                    dialog.accept()
                }
                contentItem: Text { text: parent.text; color: "white"; font.weight: Font.DemiBold; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle { radius: 8; color: parent.enabled ? "#3278E8" : "#28436B" }
            }
        }
    }
}
