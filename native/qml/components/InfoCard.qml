import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card

    property var theme: null
    property bool emphasized: false
    property int contentPadding: theme ? theme.spaceMd : 12

    radius: theme ? theme.radiusMd : 11
    color: emphasized ? (theme ? theme.surfaceRaised : "#172741") : (theme ? theme.surface : "#121F34")
    border.width: 1
    border.color: theme ? theme.border : "#243651"

    default property alias content: contentHost.data

    ColumnLayout {
        id: contentHost
        anchors.fill: parent
        anchors.margins: card.contentPadding
        spacing: card.theme ? card.theme.spaceSm : 8
    }
}
