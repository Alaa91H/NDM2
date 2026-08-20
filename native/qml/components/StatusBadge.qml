import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: control
    property string status: ""
    property bool dark: true
    property string labelOverride: ""
    property var theme: null
    readonly property color fallbackColor: status === "downloading" || status === "active" ? "#58D6A3" : status === "completed" ? "#8DBDFF" : status === "queued" || status === "waiting" || status === "scheduled" ? "#FFC56A" : status === "error" || status === "failed" || status === "cancelled" ? "#FF8493" : "#9AABC3"
    readonly property color stateColor: theme ? theme.statusColor(status) : fallbackColor
    readonly property string stateSymbol: theme ? theme.statusSymbol(status) : "•"
    implicitWidth: Math.max(72, row.implicitWidth + 18)
    implicitHeight: 24
    radius: 12
    color: Qt.rgba(stateColor.r, stateColor.g, stateColor.b, dark ? .16 : .10)
    border.color: Qt.rgba(stateColor.r, stateColor.g, stateColor.b, dark ? .38 : .30)
    Accessible.name: (labelOverride.length > 0 ? labelOverride : status) + qsTr(" status")

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 5
        Label { text: control.stateSymbol; color: control.stateColor; font.pixelSize: 11; font.weight: Font.DemiBold }
        Label { text: control.labelOverride.length > 0 ? control.labelOverride : control.status; color: control.dark ? "#EAF1FF" : "#24324A"; font.pixelSize: 10; font.weight: Font.DemiBold; elide: Text.ElideRight }
    }
}
