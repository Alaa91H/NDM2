import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: windowSurface

    property var theme: null
    property string pageTitle: ""
    property string pageSubtitle: ""
    property string glyph: ""
    property string statusText: ""
    property string actionText: ""
    property string actionGlyph: "↻"
    property bool actionEnabled: true
    signal actionRequested()

    default property alias content: contentHost.data

    implicitWidth: 720
    implicitHeight: header.implicitHeight + contentHost.implicitHeight + (theme ? theme.spaceLg * 2 : 32)
    color: theme ? theme.surface : "#292929"
    radius: theme ? theme.radiusXl : 16
    border.width: activeFocus ? 2 : 1
    border.color: activeFocus ? (theme ? theme.focus : "#60CDFF") : (theme ? theme.borderStrong : "#626262")
    clip: true
    Accessible.role: Accessible.Pane
    Accessible.name: pageTitle

    Behavior on border.color { ColorAnimation { duration: 100 } }

    Rectangle {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: theme ? 74 : 72
        color: theme ? theme.surfaceRaised : "#323232"
        border.width: 1
        border.color: theme ? theme.border : "#454545"

        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 3
            color: theme ? theme.accent : "#60CDFF"
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: theme ? theme.spaceLg : 16
            anchors.rightMargin: theme ? theme.spaceLg : 16
            anchors.topMargin: theme ? theme.spaceSm : 8
            anchors.bottomMargin: theme ? theme.spaceSm : 8
            spacing: theme ? theme.spaceMd : 12

            Rectangle {
                visible: windowSurface.glyph.length > 0
                Layout.preferredWidth: theme ? theme.touchHeight : 40
                Layout.preferredHeight: theme ? theme.touchHeight : 40
                radius: theme ? theme.radiusMd : 8
                color: theme ? theme.accentSoft : "#17445D"
                Text {
                    anchors.centerIn: parent
                    text: windowSurface.glyph
                    color: theme ? theme.accent : "#60CDFF"
                    font.pixelSize: theme ? theme.fontSection : 17
                    font.weight: Font.DemiBold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                Label {
                    Layout.fillWidth: true
                    text: windowSurface.pageTitle
                    color: theme ? theme.textPrimary : "#FFFFFF"
                    font.pixelSize: theme ? theme.fontSection : 17
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    visible: windowSurface.pageSubtitle.length > 0
                    text: windowSurface.pageSubtitle
                    color: theme ? theme.textSecondary : "#D0D0D0"
                    font.pixelSize: theme ? theme.fontCaption : 12
                    elide: Text.ElideRight
                }
            }

            Label {
                visible: windowSurface.statusText.length > 0
                text: windowSurface.statusText
                color: theme ? theme.textMuted : "#A6A6A6"
                font.pixelSize: theme ? theme.fontCaption : 12
                elide: Text.ElideRight
            }

            ActionButton {
                visible: windowSurface.actionText.length > 0
                text: windowSurface.actionGlyph + "  " + windowSurface.actionText
                tone: "secondary"
                enabled: windowSurface.actionEnabled
                dark: settingsService.dark
                theme: windowSurface.theme
                onClicked: windowSurface.actionRequested()
            }
        }
    }

    Item {
        id: contentHost
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: theme ? theme.spaceLg : 16
    }
}
