import QtQuick
import QtQuick.Controls

SpinBox {
    id: control

    property var theme: null
    property bool dark: true

    implicitHeight: 38
    editable: true
    font.pixelSize: theme ? theme.fontBody : 12

    contentItem: TextInput {
        z: 2
        text: control.textFromValue(control.value, control.locale)
        font: control.font
        color: control.enabled ? (control.theme ? control.theme.textPrimary : "#F0F5FF") : (control.theme ? control.theme.textMuted : "#71829B")
        selectionColor: control.theme ? control.theme.accent : "#5C9EFF"
        selectedTextColor: "#FFFFFF"
        horizontalAlignment: Qt.AlignHCenter
        verticalAlignment: Qt.AlignVCenter
        readOnly: !control.editable
        validator: control.validator
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        onTextEdited: {
            var value = control.valueFromText(text, control.locale)
            if (!isNaN(value))
                control.value = value
        }
    }

    up.indicator: Rectangle {
        x: control.mirrored ? 0 : parent.width - width
        height: parent.height / 2
        width: 24
        radius: theme ? theme.radiusSm : 7
        color: control.up.hovered ? (theme ? theme.surfaceRaised : "#172741") : "transparent"
        Text { anchors.centerIn: parent; text: "⌃"; color: theme ? theme.textSecondary : "#9AABC3"; font.pixelSize: 12 }
    }
    down.indicator: Rectangle {
        x: control.mirrored ? 0 : parent.width - width
        y: parent.height / 2
        height: parent.height / 2
        width: 24
        radius: theme ? theme.radiusSm : 7
        color: control.down.hovered ? (theme ? theme.surfaceRaised : "#172741") : "transparent"
        Text { anchors.centerIn: parent; text: "⌄"; color: theme ? theme.textSecondary : "#9AABC3"; font.pixelSize: 12 }
    }

    background: Rectangle {
        radius: theme ? theme.radiusSm : 7
        color: control.theme ? control.theme.surfaceSubtle : "#0E192B"
        border.width: control.activeFocus ? 2 : 1
        border.color: control.activeFocus ? (control.theme ? control.theme.accent : "#5C9EFF") : (control.theme ? control.theme.border : "#243651")
    }
}
