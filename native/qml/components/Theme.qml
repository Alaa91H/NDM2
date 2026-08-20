import QtQuick

QtObject {
    id: theme
    property bool dark: true

    // Fluent-inspired Windows 11 material layers.  The palette intentionally
    // remains opaque so that it behaves consistently on every supported desktop.
    readonly property color background: dark ? "#202020" : "#F3F3F3"
    readonly property color backdrop: dark ? "#1C1C1C" : "#F7F7F7"
    readonly property color sidebar: dark ? "#272727" : "#F7F7F7"
    readonly property color surface: dark ? "#292929" : "#FFFFFF"
    readonly property color surfaceRaised: dark ? "#323232" : "#FFFFFF"
    readonly property color surfaceSubtle: dark ? "#252525" : "#F9F9F9"
    readonly property color surfaceHover: dark ? "#3A3A3A" : "#F1F1F1"
    readonly property color surfacePressed: dark ? "#454545" : "#E5E5E5"
    readonly property color controlFill: dark ? "#363636" : "#FBFBFB"
    readonly property color controlHover: dark ? "#454545" : "#F5F5F5"
    readonly property color controlPressed: dark ? "#505050" : "#E9E9E9"
    readonly property color textPrimary: dark ? "#FFFFFF" : "#1A1A1A"
    readonly property color textSecondary: dark ? "#D0D0D0" : "#5E5E5E"
    readonly property color textMuted: dark ? "#A6A6A6" : "#767676"
    readonly property color border: dark ? "#454545" : "#E0E0E0"
    readonly property color borderStrong: dark ? "#626262" : "#C7C7C7"
    readonly property color focus: dark ? "#60CDFF" : "#005FB8"
    readonly property color accent: dark ? "#60CDFF" : "#005FB8"
    readonly property color accentHover: dark ? "#8CDBFF" : "#004A8F"
    readonly property color accentPressed: dark ? "#3AAAE0" : "#003A70"
    readonly property color accentSoft: dark ? "#17445D" : "#D7E9FF"
    readonly property color success: dark ? "#6CCB9A" : "#0F7B45"
    readonly property color successSoft: dark ? "#183C2B" : "#DDF4E7"
    readonly property color warning: dark ? "#F5C96A" : "#9D5A00"
    readonly property color warningSoft: dark ? "#493A1C" : "#FFF1D6"
    readonly property color danger: dark ? "#FF99A4" : "#C42B1C"
    readonly property color dangerSoft: dark ? "#4C252A" : "#FDE7E9"
    readonly property color information: dark ? "#75BEFF" : "#005FB8"
    readonly property color selection: dark ? "#1B5C7D" : "#CFE7FF"
    readonly property color shadow: dark ? "#99000000" : "#26000000"

    readonly property int space2xs: 2
    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 16
    readonly property int spaceXl: 24
    readonly property int radiusXs: 4
    readonly property int radiusSm: 6
    readonly property int radiusMd: 8
    readonly property int radiusLg: 12
    readonly property int radiusXl: 16
    readonly property int controlHeight: 32
    readonly property int touchHeight: 40

    readonly property int fontMeta: 11
    readonly property int fontCaption: 12
    readonly property int fontBody: 13
    readonly property int fontBodyLarge: 15
    readonly property int fontSection: 17
    readonly property int fontPage: 24
    readonly property int fontMetric: 20
    readonly property string fontMono: "Consolas, Cascadia Mono, monospace"

    function statusColor(status) {
        switch (String(status || "").toLowerCase()) {
        case "downloading": case "active": return success
        case "completed": return information
        case "queued": case "waiting": case "scheduled": return warning
        case "error": case "failed": case "cancelled": return danger
        case "paused": return textSecondary
        default: return textMuted
        }
    }
    function statusSymbol(status) {
        switch (String(status || "").toLowerCase()) {
        case "downloading": case "active": return "↓"
        case "completed": return "✓"
        case "queued": case "waiting": return "⋯"
        case "paused": return "Ⅱ"
        case "error": case "failed": return "!"
        case "cancelled": return "×"
        case "scheduled": return "◷"
        default: return "•"
        }
    }
}
