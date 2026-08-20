import QtQuick
import QtQuick.Controls

ComboBox {
    id: control

    property var theme: null
    property bool dark: theme ? theme.dark : true

    implicitHeight: theme ? theme.controlHeight : 32
    leftPadding: theme ? theme.spaceMd : 12
    rightPadding: 32
    focusPolicy: Qt.StrongFocus
    Accessible.name: displayText

    contentItem: Text {
        leftPadding: control.leftPadding
        rightPadding: control.rightPadding
        text: control.displayText
        color: control.enabled ? (control.theme ? control.theme.textPrimary : "#FFFFFF") : (control.theme ? control.theme.textMuted : "#A6A6A6")
        font.pixelSize: control.theme ? control.theme.fontBody : 13
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 11
        y: Math.round((control.height - height) / 2) - 1
        text: "⌄"
        color: control.theme ? control.theme.textSecondary : "#D0D0D0"
        font.pixelSize: 16
        font.weight: Font.DemiBold
    }
    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 6
        color: !control.enabled ? (control.theme ? control.theme.surfaceSubtle : "#252525") : control.pressed ? (control.theme ? control.theme.controlPressed : "#505050") : control.hovered ? (control.theme ? control.theme.controlHover : "#454545") : (control.theme ? control.theme.controlFill : "#363636")
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.focus : "#60CDFF") : (control.hovered ? (control.theme ? control.theme.borderStrong : "#626262") : (control.theme ? control.theme.border : "#454545"))
        Behavior on color { ColorAnimation { duration: 100 } }
    }
    delegate: ItemDelegate {
        width: control.width
        height: control.theme ? control.theme.touchHeight : 40
        text: control.textAt(index)
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: parent.text
            color: control.theme ? control.theme.textPrimary : "#FFFFFF"
            font.pixelSize: control.theme ? control.theme.fontBody : 13
            verticalAlignment: Text.AlignVCenter
            leftPadding: control.theme ? control.theme.spaceMd : 12
            rightPadding: control.theme ? control.theme.spaceMd : 12
            elide: Text.ElideRight
        }
        background: Rectangle {
            radius: control.theme ? control.theme.radiusXs : 4
            color: parent.highlighted ? (control.theme ? control.theme.selection : "#1B5C7D") : parent.hovered ? (control.theme ? control.theme.surfaceHover : "#3A3A3A") : "transparent"
        }
    }
    popup: Popup {
        y: control.height + 4
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 320)
        padding: 4
        background: Rectangle {
            radius: control.theme ? control.theme.radiusMd : 8
            color: control.theme ? control.theme.surfaceRaised : "#323232"
            border.color: control.theme ? control.theme.borderStrong : "#626262"
            border.width: 1
        }
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: control.popup.visible ? control.delegateModel : null
            currentIndex: control.highlightedIndex
            ScrollIndicator.vertical: ScrollIndicator {}
        }
    }
}
