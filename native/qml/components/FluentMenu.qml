import QtQuick
import QtQuick.Controls

Menu {
    id: control

    property var theme: null
    property bool dark: true

    padding: theme ? theme.spaceXs : 4
    implicitWidth: 208
    Accessible.role: Accessible.PopupMenu

    background: Rectangle {
        radius: control.theme ? control.theme.radiusMd : 8
        color: control.theme ? control.theme.surfaceRaised : "#323232"
        border.width: 1
        border.color: control.theme ? control.theme.borderStrong : "#626262"
    }

    delegate: MenuItem {
        id: menuItem
        implicitHeight: control.theme ? control.theme.touchHeight : 40
        leftPadding: control.theme ? control.theme.spaceMd : 12
        rightPadding: control.theme ? control.theme.spaceMd : 12
        focusPolicy: Qt.StrongFocus

        contentItem: Label {
            text: menuItem.text
            color: menuItem.enabled
                ? (control.theme ? control.theme.textPrimary : "#FFFFFF")
                : (control.theme ? control.theme.textMuted : "#A6A6A6")
            font.pixelSize: control.theme ? control.theme.fontBody : 13
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        background: Rectangle {
            radius: control.theme ? control.theme.radiusXs : 4
            border.width: menuItem.activeFocus ? 2 : 0
            border.color: menuItem.activeFocus && control.theme ? control.theme.focus : "transparent"
            color: menuItem.down
                ? (control.theme ? control.theme.surfacePressed : "#454545")
                : menuItem.highlighted
                    ? (control.theme ? control.theme.surfaceHover : "#3A3A3A")
                    : "transparent"
            Behavior on color {
                ColorAnimation { duration: control.theme ? control.theme.durationFast : 100 }
            }
        }
    }

    MenuSeparator {
        contentItem: Rectangle {
            implicitHeight: 1
            color: control.theme ? control.theme.border : "#454545"
        }
    }
}
