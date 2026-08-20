import QtQuick
import QtQuick.Controls

Dialog {
    id: control

    property var theme: null
    property Item returnFocusTarget: null

    modal: true
    focus: true
    anchors.centerIn: Overlay.overlay
    padding: 0
    closePolicy: Popup.CloseOnEscape

    background: Rectangle {
        radius: control.theme ? control.theme.radiusXl : 16
        color: control.theme ? control.theme.backdrop : "#1C1C1C"
        border.width: 1
        border.color: control.theme ? control.theme.borderStrong : "#626262"
    }

    onClosed: {
        if (returnFocusTarget)
            returnFocusTarget.forceActiveFocus()
    }
}
