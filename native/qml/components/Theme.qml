import QtQuick

QtObject {
    id: theme
    property bool dark: true

    readonly property color background: dark ? "#0B1220" : "#F3F6FA"
    readonly property color sidebar: dark ? "#0F1A2D" : "#F8FAFD"
    readonly property color surface: dark ? "#121F34" : "#FFFFFF"
    readonly property color surfaceRaised: dark ? "#172741" : "#FFFFFF"
    readonly property color surfaceSubtle: dark ? "#0E192B" : "#F1F5FA"
    readonly property color textPrimary: dark ? "#F0F5FF" : "#172235"
    readonly property color textSecondary: dark ? "#9AABC3" : "#64748B"
    readonly property color textMuted: dark ? "#71829B" : "#7B8798"
    readonly property color border: dark ? "#243651" : "#D8E1EC"
    readonly property color borderStrong: dark ? "#365579" : "#B9CADB"
    readonly property color accent: dark ? "#5C9EFF" : "#2563EB"
    readonly property color accentHover: dark ? "#78B1FF" : "#1D4ED8"
    readonly property color accentSoft: dark ? "#19365E" : "#E3EEFF"
    readonly property color success: dark ? "#58D6A3" : "#0F9F6E"
    readonly property color successSoft: dark ? "#113B37" : "#DDF8EC"
    readonly property color warning: dark ? "#FFC56A" : "#C98000"
    readonly property color warningSoft: dark ? "#3C311A" : "#FFF3D8"
    readonly property color danger: dark ? "#FF8493" : "#D93850"
    readonly property color dangerSoft: dark ? "#452431" : "#FFE6EA"
    readonly property color information: dark ? "#8DBDFF" : "#276AC3"
    readonly property color selection: dark ? "#193A67" : "#DDEBFF"

    readonly property int spaceXs: 4
    readonly property int spaceSm: 8
    readonly property int spaceMd: 12
    readonly property int spaceLg: 18
    readonly property int spaceXl: 26
    readonly property int radiusSm: 7
    readonly property int radiusMd: 11
    readonly property int radiusLg: 15

    readonly property int fontMeta: 10
    readonly property int fontCaption: 11
    readonly property int fontBody: 12
    readonly property int fontBodyLarge: 14
    readonly property int fontSection: 16
    readonly property int fontPage: 22
    readonly property int fontMetric: 18
    readonly property string fontMono: "monospace"

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
