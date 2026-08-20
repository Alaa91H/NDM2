import QtQuick
import QtQuick.Layouts

Rectangle {
    id: card

    property var theme: null
    property bool emphasized: false
    property bool interactive: false
    property int contentPadding: theme ? theme.spaceLg : 16
    property color fill: emphasized ? (theme ? theme.surfaceRaised : "#323232") : (theme ? theme.surface : "#292929")

    implicitWidth: contentHost.implicitWidth + contentPadding * 2
    implicitHeight: contentHost.implicitHeight + contentPadding * 2
    radius: theme ? theme.radiusLg : 12
    color: interactive && cardMouse.containsMouse ? (theme ? theme.surfaceHover : "#3A3A3A") : fill
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? (theme ? theme.focus : "#60CDFF") : (theme ? theme.border : "#454545")
    focus: interactive
    Accessible.role: Accessible.Pane

    default property alias content: contentHost.data
    signal clicked()

    MouseArea {
        id: cardMouse
        anchors.fill: parent
        enabled: card.interactive
        hoverEnabled: true
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: { card.forceActiveFocus(); card.clicked() }
    }

    Behavior on color { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    ColumnLayout {
        id: contentHost
        anchors.fill: parent
        anchors.margins: card.contentPadding
        spacing: card.theme ? card.theme.spaceSm : 8
    }
}
