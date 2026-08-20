import QtQuick
import QtQuick.Controls

ComboBox {
    id: control
    property var theme: null
    property bool dark: theme ? theme.dark : true
    implicitHeight: 34
    leftPadding: 10
    rightPadding: 30
    focusPolicy: Qt.StrongFocus
    Accessible.name: displayText
    contentItem: Text {
        leftPadding: control.leftPadding
        rightPadding: control.rightPadding
        text: control.displayText
        color: control.enabled ? (control.theme ? control.theme.textPrimary : "#F0F5FF") : (control.dark ? "#61718A" : "#99A4B5")
        font: control.font
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
    }
    indicator: Text {
        x: control.width - width - 10
        y: Math.round((control.height - height) / 2)
        text: "⌄"
        color: control.theme ? control.theme.textSecondary : "#9AABC3"
        font.pixelSize: 16
    }
    background: Rectangle {
        radius: control.theme ? control.theme.radiusSm : 7
        color: !control.enabled ? (control.dark ? "#172235" : "#EEF2F7") : control.pressed ? (control.theme ? control.theme.accentSoft : "#203452") : control.hovered ? (control.theme ? control.theme.surfaceSubtle : "#1A2A42") : (control.theme ? control.theme.surfaceRaised : "#152238")
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.theme ? control.theme.border : "#243651")
    }
    delegate: ItemDelegate {
        width: control.width
        height: 34
        text: control.textAt(index)
        highlighted: control.highlightedIndex === index
        contentItem: Text {
            text: parent.text
            color: control.theme ? control.theme.textPrimary : "#F0F5FF"
            font: parent.font
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10
            rightPadding: 10
            elide: Text.ElideRight
        }
        background: Rectangle {
            color: parent.highlighted ? (control.theme ? control.theme.selection : "#193A67") : parent.hovered ? (control.theme ? control.theme.surfaceSubtle : "#1A2A42") : "transparent"
        }
    }
    popup: Popup {
        y: control.height + 2
        width: control.width
        implicitHeight: Math.min(contentItem.implicitHeight + topPadding + bottomPadding, 280)
        padding: 1
        background: Rectangle {
            radius: control.theme ? control.theme.radiusSm : 7
            color: control.theme ? control.theme.surfaceRaised : "#172741"
            border.color: control.theme ? control.theme.borderStrong : "#365579"
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
