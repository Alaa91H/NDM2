import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

RowLayout {
    id: control
    property string title: ""
    property string subtitle: ""
    property string actionText: ""
    property var theme: null
    signal actionRequested()
    Layout.fillWidth: true
    spacing: theme ? theme.spaceMd : 12
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2
        Label { text: control.title; color: control.theme ? control.theme.textPrimary : "#F0F5FF"; font.pixelSize: control.theme ? control.theme.fontPage : 22; font.weight: Font.DemiBold }
        Label { visible: text.length > 0; text: control.subtitle; color: control.theme ? control.theme.textSecondary : "#9AABC3"; font.pixelSize: control.theme ? control.theme.fontCaption : 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
    ActionButton { visible: control.actionText.length > 0; text: control.actionText; tone: "secondary"; dark: control.theme ? control.theme.dark : true; theme: control.theme; onClicked: control.actionRequested() }
}
