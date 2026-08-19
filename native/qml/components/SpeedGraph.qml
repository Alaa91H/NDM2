import QtQuick

Item {
    id: root
    property var samples: []
    property color lineColor: "#4DA3FF"
    implicitHeight: 140
    Canvas {
        id: canvas; anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d"), w = width, h = height
            ctx.reset(); ctx.clearRect(0, 0, w, h)
            ctx.strokeStyle = "#243653"; ctx.lineWidth = 1
            for (var y = 1; y < 4; ++y) { ctx.beginPath(); ctx.moveTo(0, h * y / 4); ctx.lineTo(w, h * y / 4); ctx.stroke() }
            if (!root.samples || root.samples.length < 2) return
            var maxValue = 1
            for (var i = 0; i < root.samples.length; ++i) maxValue = Math.max(maxValue, Number(root.samples[i]))
            ctx.beginPath()
            for (var j = 0; j < root.samples.length; ++j) {
                var x = j * w / (root.samples.length - 1), yValue = h - (Number(root.samples[j]) / maxValue) * (h - 10) - 5
                if (j === 0) ctx.moveTo(x, yValue); else ctx.lineTo(x, yValue)
            }
            ctx.strokeStyle = root.lineColor; ctx.lineWidth = 2; ctx.stroke()
        }
        Connections { target: root; function onSamplesChanged() { canvas.requestPaint() } }
        Component.onCompleted: requestPaint()
    }
}
