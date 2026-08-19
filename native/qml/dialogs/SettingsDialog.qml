import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Dialog {
    id: dialog; modal: true; anchors.centerIn: Overlay.overlay; width: 670; padding: 0
    background: Rectangle { color: "#152238"; radius: 14; border.color: "#2A4266" }
    header: RowLayout { height: 68; Label { Layout.leftMargin: 24; Layout.fillWidth: true; text: qsTr("Settings"); color: "#F1F6FF"; font.pixelSize: 19; font.weight: Font.DemiBold } ToolButton { Layout.rightMargin: 16; text: "×"; font.pixelSize: 22; onClicked: dialog.close() } }
    contentItem: GridLayout { columns: 2; width: dialog.width - 48; columnSpacing: 24; rowSpacing: 20
        ColumnLayout { Layout.fillWidth: true; Label { text: qsTr("Appearance"); color: "#C9D5E8"; font.weight: Font.DemiBold } Label { text: qsTr("Theme"); color: "#8C9AB0"; font.pixelSize: 11 } ComboBox { Layout.fillWidth: true; model: ["system", "dark", "light"]; currentIndex: Math.max(0, model.indexOf(settingsService.theme)); onActivated: settingsService.setTheme(currentText) } Label { text: qsTr("Density"); color: "#8C9AB0"; font.pixelSize: 11 } ComboBox { Layout.fillWidth: true; model: ["comfortable", "compact"]; currentIndex: Math.max(0, model.indexOf(settingsService.density)); onActivated: settingsService.setDensity(currentText) } }
        ColumnLayout { Layout.fillWidth: true; Label { text: qsTr("Language and direction"); color: "#C9D5E8"; font.weight: Font.DemiBold } Label { text: qsTr("Interface language"); color: "#8C9AB0"; font.pixelSize: 11 } ComboBox { Layout.fillWidth: true; model: ["en", "ar", "de", "he", "fa"]; currentIndex: Math.max(0, model.indexOf(settingsService.language)); onActivated: settingsService.setLanguage(currentText) } Label { text: settingsService.rightToLeft ? qsTr("Right-to-left layout enabled") : qsTr("Left-to-right layout enabled"); color: "#78C8A9"; font.pixelSize: 11 } }
        ColumnLayout { Layout.columnSpan: 2; Layout.fillWidth: true; Label { text: qsTr("Core bandwidth limit"); color: "#C9D5E8"; font.weight: Font.DemiBold } RowLayout { Layout.fillWidth: true; SpinBox { id: globalLimit; from: 0; to: 1000000; value: 0; editable: true; Layout.fillWidth: true } Button { text: qsTr("Apply to core"); onClicked: taskController.setBandwidthLimit(globalLimit.value) } } Label { text: qsTr("0 means the value supplied to the core is unrestricted only if the core treats it as such."); color: "#78879E"; font.pixelSize: 11 } }
        Label { Layout.columnSpan: 2; Layout.fillWidth: true; text: qsTr("NDM2 persists only presentation settings locally. Download engine settings remain core-owned and are changed only through its authenticated API."); wrapMode: Text.Wrap; color: "#8390A4"; font.pixelSize: 11 }
    }
}
