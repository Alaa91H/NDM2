import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    property string activePane: "rules"
    function ruleId(prefix) { return prefix + "-" + Date.now() }
    function readable(value) { return value === undefined || value === null ? "—" : String(value) }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        RowLayout {
            Layout.fillWidth: true
            ColumnLayout { Layout.fillWidth: true; spacing: 2
                Label { text: qsTr("Automation & sources"); color: root.textColor; font.pixelSize: 20; font.weight: Font.DemiBold }
                Label { text: qsTr("Every operation is submitted to NOVA Core; unsupported mutations are not simulated."); color: root.muted; font.pixelSize: 11 }
            }
            Button { text: qsTr("Refresh"); onClicked: taskController.refreshAll() }
        }
        TabBar {
            id: tabs
            Layout.fillWidth: true
            currentIndex: root.activePane === "rules" ? 0 : root.activePane === "scheduler" ? 1 : 2
            TabButton { text: qsTr("Rules") }
            TabButton { text: qsTr("Scheduler") }
            TabButton { text: qsTr("Mirrors") }
            onCurrentIndexChanged: root.activePane = currentIndex === 0 ? "rules" : currentIndex === 1 ? "scheduler" : "mirrors"
        }
        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex
            Item {
                ColumnLayout { anchors.fill: parent; spacing: 12
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 126; radius: 10; color: Qt.rgba(1,1,1,.035); border.color: Qt.rgba(1,1,1,.08)
                        GridLayout { anchors.fill: parent; anchors.margins: 14; columns: 4; columnSpacing: 10; rowSpacing: 8
                            TextField { id: ruleName; Layout.fillWidth: true; placeholderText: qsTr("Rule name") }
                            TextField { id: ruleNeedle; Layout.fillWidth: true; placeholderText: qsTr("URL contains") }
                            TextField { id: ruleCategory; Layout.fillWidth: true; placeholderText: qsTr("Apply category") }
                            SpinBox { id: rulePriority; from: 0; to: 9999; value: 100; editable: true; Layout.fillWidth: true }
                            Label { Layout.columnSpan: 3; Layout.fillWidth: true; text: qsTr("Creates the Core-supported UrlContains → SetCategory rule. Additional typed conditions/actions remain visible in the legacy UI until native editors are expanded."); color: root.muted; font.pixelSize: 10; wrapMode: Text.Wrap }
                            Button { text: qsTr("Add rule"); enabled: ruleName.text.trim().length > 0 && ruleNeedle.text.trim().length > 0 && ruleCategory.text.trim().length > 0; onClicked: { taskController.addRule({ "id": root.ruleId("rule"), "name": ruleName.text.trim(), "enabled": true, "priority": rulePriority.value, "conditions": [{ "type": "UrlContains", "text": ruleNeedle.text.trim() }], "action": { "type": "SetCategory", "category": ruleCategory.text.trim() } }); ruleName.clear(); ruleNeedle.clear(); ruleCategory.clear() } }
                        }
                    }
                    ListView { id: rulesList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.rules
                        delegate: Rectangle { required property var modelData; width: rulesList.width; height: 70; radius: 9; color: Qt.rgba(1,1,1,.025); border.color: Qt.rgba(1,1,1,.06)
                            RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 10
                                ColumnLayout { Layout.fillWidth: true; spacing: 3; Label { Layout.fillWidth: true; text: modelData.name || modelData.id; color: root.textColor; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight } Label { Layout.fillWidth: true; text: qsTr("Priority %1 · %2 conditions · %3").arg(modelData.priority).arg((modelData.conditions || []).length).arg(modelData.action ? modelData.action.type : "—"); color: root.muted; font.pixelSize: 10; elide: Text.ElideRight } }
                                Label { text: modelData.enabled ? qsTr("Enabled") : qsTr("Disabled"); color: modelData.enabled ? "#6ED2A7" : "#FFBE69"; font.pixelSize: 11 }
                                Button { text: qsTr("Delete"); onClicked: taskController.deleteRule(modelData.id) }
                            }
                        }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                    Label { visible: rulesList.count === 0; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: qsTr("No Core download rules are configured."); color: root.muted }
                }
            }
            Item {
                ColumnLayout { anchors.fill: parent; spacing: 12
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 150; radius: 10; color: Qt.rgba(1,1,1,.035); border.color: Qt.rgba(1,1,1,.08)
                        GridLayout { anchors.fill: parent; anchors.margins: 14; columns: 4; columnSpacing: 10; rowSpacing: 8
                            TextField { id: scheduleName; Layout.fillWidth: true; placeholderText: qsTr("Schedule name") }
                            ComboBox { id: triggerBox; Layout.fillWidth: true; model: ["QueueEmpty", "AllComplete", "BandwidthBelow"] }
                            ComboBox { id: actionBox; Layout.fillWidth: true; model: ["SetBandwidthLimit", "Notify"] }
                            SpinBox { id: scheduleValue; Layout.fillWidth: true; from: 0; to: 1000000; value: 0; editable: true }
                            CheckBox { id: powerCommands; Layout.columnSpan: 2; text: qsTr("Permit Core power commands"); checked: false; onToggled: taskController.setSchedulerPowerCommands(checked) }
                            Label { Layout.columnSpan: 2; Layout.fillWidth: true; text: qsTr("Supported triggers: QueueEmpty, AllComplete, BandwidthBelow. Actions: SetBandwidthLimit or Notify."); color: root.muted; font.pixelSize: 10; wrapMode: Text.Wrap }
                            Button { Layout.columnSpan: 4; text: qsTr("Add scheduler rule"); enabled: scheduleName.text.trim().length > 0; onClicked: { var trigger = triggerBox.currentText === "BandwidthBelow" ? { "type": "BandwidthBelow", "threshold_kbps": scheduleValue.value } : { "type": triggerBox.currentText } var action = actionBox.currentText === "Notify" ? { "type": "Notify", "message": scheduleName.text.trim() } : { "type": "SetBandwidthLimit", "kbps": scheduleValue.value } taskController.addSchedulerRule({ "id": root.ruleId("schedule"), "name": scheduleName.text.trim(), "enabled": true, "trigger": trigger, "action": action }); scheduleName.clear() } }
                        }
                    }
                    ListView { id: schedulerList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.schedulerRules
                        delegate: Rectangle { required property var modelData; width: schedulerList.width; height: 70; radius: 9; color: Qt.rgba(1,1,1,.025); border.color: Qt.rgba(1,1,1,.06)
                            RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 10
                                ColumnLayout { Layout.fillWidth: true; spacing: 3; Label { Layout.fillWidth: true; text: modelData.name || modelData.id; color: root.textColor; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight } Label { Layout.fillWidth: true; text: (modelData.trigger ? modelData.trigger.type : "—") + " → " + (modelData.action ? modelData.action.type : "—"); color: root.muted; font.pixelSize: 10; elide: Text.ElideRight } }
                                Switch { checked: modelData.enabled; onToggled: taskController.updateSchedulerRule({ "id": modelData.id, "name": modelData.name, "enabled": checked, "trigger": modelData.trigger, "action": modelData.action }) }
                                Button { text: qsTr("Delete"); onClicked: taskController.deleteSchedulerRule(modelData.id) }
                            }
                        }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                    Label { visible: schedulerList.count === 0; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: qsTr("No Core scheduler rules are configured."); color: root.muted }
                }
            }
            Item {
                ColumnLayout { anchors.fill: parent; spacing: 12
                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 106; radius: 10; color: Qt.rgba(1,1,1,.035); border.color: Qt.rgba(1,1,1,.08)
                        RowLayout { anchors.fill: parent; anchors.margins: 14; spacing: 10
                            ColumnLayout { Layout.fillWidth: true; spacing: 3; Label { text: qsTr("Selected task"); color: root.muted; font.pixelSize: 10 } Label { Layout.fillWidth: true; text: taskController.selectedDownload.name || qsTr("Select a download from the library"); color: root.textColor; elide: Text.ElideRight; font.pixelSize: 12 } }
                            TextField { id: mirrorUrl; Layout.preferredWidth: 280; placeholderText: "https://mirror.example/file" }
                            SpinBox { id: mirrorPriority; from: 0; to: 99; value: 0; editable: true; Layout.preferredWidth: 80 }
                            Button { text: qsTr("Add mirror"); enabled: taskController.selectedId.length > 0 && mirrorUrl.text.trim().length > 0; onClicked: { taskController.addSelectedMirror(mirrorUrl.text, mirrorPriority.value); mirrorUrl.clear() } }
                            Button { text: qsTr("Failover"); enabled: taskController.selectedId.length > 0; onClicked: taskController.triggerSelectedMirrorFailover() }
                        }
                    }
                    ListView { id: mirrorList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.mirrors
                        delegate: Rectangle { required property var modelData; width: mirrorList.width; height: 82; radius: 9; color: Qt.rgba(1,1,1,.025); border.color: Qt.rgba(1,1,1,.06)
                            ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 4
                                Label { Layout.fillWidth: true; text: modelData.task_id || qsTr("Task"); color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideMiddle }
                                Label { Layout.fillWidth: true; text: qsTr("Active: ") + (modelData.active_url || "—"); color: root.muted; font.pixelSize: 10; elide: Text.ElideMiddle }
                                Label { Layout.fillWidth: true; text: qsTr("Mirrors: ") + (modelData.mirrors || []).map(function(x) { return x.url }).join(" · "); color: "#8CB4EE"; font.pixelSize: 10; elide: Text.ElideMiddle }
                            }
                        }
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                    }
                    Label { visible: mirrorList.count === 0; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: qsTr("No Core mirror managers have been created."); color: root.muted }
                }
            }
        }
    }
}
