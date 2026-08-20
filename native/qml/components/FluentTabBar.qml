import QtQuick
import QtQuick.Controls

TabBar {
    id: control

    property var theme: null
    property var labels: []
    property string accessibleName: ""

    implicitHeight: theme ? theme.controlHeight : 32
    focusPolicy: Qt.StrongFocus
    Accessible.name: accessibleName.length > 0 ? accessibleName : qsTr("Sections")

    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 6
        color: control.theme ? control.theme.controlFill : "#363636"
        border.width: 1
        border.color: control.theme ? control.theme.border : "#454545"
    }

    Repeater {
        model: control.labels
        delegate: TabButton {
            id: tab
            required property string modelData
            text: modelData
            focusPolicy: Qt.StrongFocus
            Accessible.name: text
            Accessible.description: checked ? qsTr("Current section") : qsTr("Open section")

            contentItem: Label {
                text: tab.text
                color: tab.checked
                    ? (control.theme ? control.theme.textPrimary : "#FFFFFF")
                    : (control.theme ? control.theme.textSecondary : "#D0D0D0")
                font.pixelSize: control.theme ? control.theme.fontCaption : 12
                font.weight: tab.checked ? Font.DemiBold : Font.Normal
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            background: Rectangle {
                anchors.margins: control.theme ? control.theme.space2xs : 3
                radius: control.theme ? control.theme.radiusXs : 4
                border.width: tab.checked || tab.activeFocus ? 1 : 0
                border.color: tab.activeFocus
                    ? (control.theme ? control.theme.focus : "#60CDFF")
                    : (control.theme ? control.theme.borderStrong : "transparent")
                color: tab.down
                    ? (control.theme ? control.theme.surfacePressed : "#454545")
                    : tab.checked
                        ? (control.theme ? control.theme.selection : "#1B5C7D")
                        : tab.hovered
                            ? (control.theme ? control.theme.surfaceHover : "#3A3A3A")
                            : "transparent"
                Behavior on color {
                    ColorAnimation { duration: control.theme ? control.theme.durationFast : 100 }
                }
            }
        }
    }
}
