import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

Item {
    id: root
    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    property var theme: null
    property string activePane: "rules"
    property string ruleValidation: ""
    property string schedulerValidation: ""
    function ruleId(prefix) { return prefix + "-" + Date.now() }
    function safeJson(text) { try { return JSON.parse(text) } catch (e) { return null } }
    function schedulerTrigger() {
        if (schedulerTriggerBox.currentText === "TimeWindow") return { "type": "TimeWindow", "start_hour": startHour.value, "start_minute": startMinute.value, "end_hour": endHour.value, "end_minute": endMinute.value }
        if (schedulerTriggerBox.currentText === "BandwidthBelow") return { "type": "BandwidthBelow", "threshold_kbps": schedulerNumber.value }
        return { "type": schedulerTriggerBox.currentText }
    }
    function schedulerAction() {
        var ids = schedulerTaskIds.text.trim().split(",").filter(function(x) { return x.trim().length > 0 })
        if (schedulerActionBox.currentText === "StartDownload" || schedulerActionBox.currentText === "PauseDownload") return { "type": schedulerActionBox.currentText, "task_ids": ids }
        if (schedulerActionBox.currentText === "SetBandwidthLimit") return { "type": "SetBandwidthLimit", "kbps": schedulerNumber.value }
        if (schedulerActionBox.currentText === "SetPriority") return { "type": "SetPriority", "task_ids": ids, "priority": schedulerPriority.currentText }
        if (schedulerActionBox.currentText === "Notify") return { "type": "Notify", "message": schedulerMessage.text.trim() || schedulerName.text.trim() }
        return { "type": schedulerActionBox.currentText }
    }
    function addGuidedScheduler() {
        if (schedulerName.text.trim().length === 0) { schedulerValidation = qsTr("A schedule name is required."); return }
        taskController.addSchedulerRule({ "id": root.ruleId("schedule"), "name": schedulerName.text.trim(), "enabled": true, "trigger": schedulerTrigger(), "action": schedulerAction() })
        schedulerValidation = ""
        schedulerName.clear()
    }
    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        SectionHeader { title: qsTr("Automation & sources"); subtitle: qsTr("Every payload is sent to NOVA Core. Raw editors use the exact tagged enum schema exposed by Core."); actionText: qsTr("Refresh"); theme: root.theme; onActionRequested: taskController.refreshAll() }
        TabBar { id: tabs; Layout.fillWidth: true; currentIndex: root.activePane === "rules" ? 0 : root.activePane === "scheduler" ? 1 : 2
            TabButton { text: qsTr("Rules") }
            TabButton { text: qsTr("Scheduler") }
            TabButton { text: qsTr("Mirrors") }
            onCurrentIndexChanged: root.activePane = currentIndex === 0 ? "rules" : currentIndex === 1 ? "scheduler" : "mirrors"
        }
        StackLayout { Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: tabs.currentIndex
            Item { ColumnLayout { anchors.fill: parent; spacing: 10
                SplitView { Layout.fillWidth: true; Layout.preferredHeight: 250; orientation: Qt.Horizontal
                    Rectangle { SplitView.preferredWidth: parent.width * .45; color: Qt.rgba(1,1,1,.035); radius: 10; border.color: Qt.rgba(1,1,1,.08)
                        GridLayout { anchors.fill: parent; anchors.margins: 14; columns: 2; columnSpacing: 10; rowSpacing: 8
                            TextField { id: ruleName; Layout.fillWidth: true; placeholderText: qsTr("Rule name") }
                            SpinBox { id: rulePriority; from: 0; to: 9999; value: 100; editable: true; Layout.fillWidth: true }
                            TextField { id: ruleNeedle; Layout.fillWidth: true; placeholderText: qsTr("URL contains") }
                            TextField { id: ruleCategory; Layout.fillWidth: true; placeholderText: qsTr("Set category") }
                            Label { Layout.columnSpan: 2; Layout.fillWidth: true; text: qsTr("Guided rule: UrlContains → SetCategory. Use the Core-schema editor for UrlMatches, extension, size, hostname, header and every supported action."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 10 }
                            Button { Layout.columnSpan: 2; text: qsTr("Add guided rule"); enabled: ruleName.text.trim().length > 0 && ruleNeedle.text.trim().length > 0 && ruleCategory.text.trim().length > 0; onClicked: { taskController.addRule({ "id": root.ruleId("rule"), "name": ruleName.text.trim(), "enabled": true, "priority": rulePriority.value, "conditions": [{ "type": "UrlContains", "text": ruleNeedle.text.trim() }], "action": { "type": "SetCategory", "category": ruleCategory.text.trim() } }); ruleName.clear(); ruleNeedle.clear(); ruleCategory.clear() } }
                        }
                    }
                    Rectangle { SplitView.preferredWidth: parent.width * .55; color: Qt.rgba(1,1,1,.035); radius: 10; border.color: Qt.rgba(1,1,1,.08)
                        ColumnLayout { anchors.fill: parent; anchors.margins: 14; spacing: 7
                            Label { text: qsTr("Core schema editor"); color: root.textColor; font.weight: Font.DemiBold; font.pixelSize: 12 }
                            TextArea { id: ruleJson; Layout.fillWidth: true; Layout.fillHeight: true; selectByMouse: true; wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 10; text: '{\n  "id": "rule-example",\n  "name": "Host category",\n  "enabled": true,\n  "priority": 100,\n  "conditions": [{"type":"HostnameContains","text":"example.org"}],\n  "action": {"type":"SetCategory","category":"Documents"}\n}' }
                            RowLayout { Layout.fillWidth: true; Label { Layout.fillWidth: true; text: root.ruleValidation; color: root.theme ? root.theme.danger : "#FF8794"; font.pixelSize: 10; elide: Text.ElideRight } Button { text: qsTr("Add Core rule"); onClicked: { var value = root.safeJson(ruleJson.text); if (!value || !value.id || !value.action || !value.conditions) root.ruleValidation = qsTr("Enter a complete Core DownloadRule JSON object."); else { root.ruleValidation = ""; taskController.addRule(value) } } } }
                        }
                    }
                }
                Label { Layout.fillWidth: true; text: qsTr("The audited Core API supports list, add and delete. It has no update/enable endpoint; NDM2 therefore does not simulate those mutations. Recreate a rule only after reviewing its Core payload."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 10 }
                ListView { id: rulesList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.rules
                    delegate: Rectangle { required property var modelData; width: rulesList.width; height: 74; radius: 9; color: Qt.rgba(1,1,1,.025); border.color: Qt.rgba(1,1,1,.06)
                        RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 10
                            ColumnLayout { Layout.fillWidth: true; spacing: 3; Label { Layout.fillWidth: true; text: modelData.name || modelData.id; color: root.textColor; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight } Label { Layout.fillWidth: true; text: JSON.stringify(modelData); color: root.muted; font.pixelSize: 9; elide: Text.ElideRight } }
                            Label { text: modelData.enabled ? qsTr("Enabled") : qsTr("Disabled"); color: modelData.enabled ? (root.theme ? root.theme.success : "#6ED2A7") : (root.theme ? root.theme.warning : "#FFBE69"); font.pixelSize: 11 }
                            Button { text: qsTr("Copy payload"); onClicked: ruleJson.text = JSON.stringify(modelData, null, 2) }
                            Button { text: qsTr("Delete"); onClicked: taskController.deleteRule(modelData.id) }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            } }
            Item { ColumnLayout { anchors.fill: parent; spacing: 10
                SplitView { Layout.fillWidth: true; Layout.preferredHeight: 280; orientation: Qt.Horizontal
                    Rectangle { SplitView.preferredWidth: parent.width * .50; color: Qt.rgba(1,1,1,.035); radius: 10; border.color: Qt.rgba(1,1,1,.08)
                        GridLayout { anchors.fill: parent; anchors.margins: 14; columns: 4; columnSpacing: 9; rowSpacing: 7
                            TextField { id: schedulerName; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Schedule name") }
                            ComboBox { id: schedulerTriggerBox; Layout.fillWidth: true; model: ["TimeWindow", "BandwidthBelow", "QueueEmpty", "AllComplete"] }
                            ComboBox { id: schedulerActionBox; Layout.fillWidth: true; model: ["StartDownload", "PauseDownload", "SetBandwidthLimit", "SetPriority", "Notify", "Shutdown", "Sleep"] }
                            SpinBox { id: startHour; from: 0; to: 23; value: 0; editable: true; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow" }
                            SpinBox { id: startMinute; from: 0; to: 59; value: 0; editable: true; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow" }
                            SpinBox { id: endHour; from: 0; to: 23; value: 23; editable: true; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow" }
                            SpinBox { id: endMinute; from: 0; to: 59; value: 59; editable: true; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow" }
                            SpinBox { id: schedulerNumber; from: 0; to: 1000000; value: 0; editable: true; Layout.fillWidth: true }
                            TextField { id: schedulerTaskIds; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Task IDs, comma separated (for start/pause/priority)") }
                            ComboBox { id: schedulerPriority; Layout.fillWidth: true; model: ["critical", "high", "normal", "low", "background"] }
                            TextField { id: schedulerMessage; Layout.fillWidth: true; placeholderText: qsTr("Notification message") }
                            CheckBox { id: powerCommands; Layout.columnSpan: 2; text: qsTr("Permit Core power commands"); onToggled: taskController.setSchedulerPowerCommands(checked) }
                            Label { Layout.columnSpan: 2; Layout.fillWidth: true; text: root.schedulerValidation; color: root.theme ? root.theme.danger : "#FF8794"; font.pixelSize: 10; elide: Text.ElideRight }
                            Button { Layout.columnSpan: 4; text: qsTr("Add guided schedule"); onClicked: root.addGuidedScheduler() }
                        }
                    }
                    Rectangle { SplitView.preferredWidth: parent.width * .50; color: Qt.rgba(1,1,1,.035); radius: 10; border.color: Qt.rgba(1,1,1,.08)
                        ColumnLayout { anchors.fill: parent; anchors.margins: 14; spacing: 7
                            Label { text: qsTr("Core scheduler schema editor"); color: root.textColor; font.weight: Font.DemiBold; font.pixelSize: 12 }
                            TextArea { id: schedulerJson; Layout.fillWidth: true; Layout.fillHeight: true; selectByMouse: true; wrapMode: Text.WrapAnywhere; font.family: "monospace"; font.pixelSize: 10; text: '{\n  "id": "schedule-example",\n  "name": "Night limit",\n  "enabled": true,\n  "trigger": {"type":"TimeWindow","start_hour":22,"start_minute":0,"end_hour":6,"end_minute":0},\n  "action": {"type":"SetBandwidthLimit","kbps":256}\n}' }
                            RowLayout { Layout.fillWidth: true; Label { Layout.fillWidth: true; text: root.schedulerValidation; color: root.theme ? root.theme.danger : "#FF8794"; font.pixelSize: 10; elide: Text.ElideRight } Button { text: qsTr("Add"); onClicked: { var value = root.safeJson(schedulerJson.text); if (!value || !value.id || !value.trigger || !value.action) root.schedulerValidation = qsTr("Enter a complete Core SchedulerRule JSON object."); else { root.schedulerValidation = ""; taskController.addSchedulerRule(value) } } } Button { text: qsTr("Update"); onClicked: { var value = root.safeJson(schedulerJson.text); if (!value || !value.id || !value.trigger || !value.action) root.schedulerValidation = qsTr("Enter a complete Core SchedulerRule JSON object."); else { root.schedulerValidation = ""; taskController.updateSchedulerRule(value) } } } }
                        }
                    }
                }
                Label { Layout.fillWidth: true; text: qsTr("Core supports TimeWindow, BandwidthBelow, QueueEmpty and AllComplete triggers; plus start/pause, bandwidth, priority, notify, shutdown and sleep actions. Recurring days, queue selection and simultaneous limits are not in the audited Core SchedulerRule schema."); color: root.muted; wrapMode: Text.Wrap; font.pixelSize: 10 }
                ListView { id: schedulerList; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; model: taskController.schedulerRules
                    delegate: Rectangle { required property var modelData; width: schedulerList.width; height: 72; radius: 9; color: Qt.rgba(1,1,1,.025); border.color: Qt.rgba(1,1,1,.06)
                        RowLayout { anchors.fill: parent; anchors.margins: 12; spacing: 10
                            ColumnLayout { Layout.fillWidth: true; spacing: 3; Label { Layout.fillWidth: true; text: modelData.name || modelData.id; color: root.textColor; font.pixelSize: 13; font.weight: Font.Medium; elide: Text.ElideRight } Label { Layout.fillWidth: true; text: JSON.stringify(modelData); color: root.muted; font.pixelSize: 9; elide: Text.ElideRight } }
                            Switch { checked: modelData.enabled; onToggled: taskController.updateSchedulerRule({ "id": modelData.id, "name": modelData.name, "enabled": checked, "trigger": modelData.trigger, "action": modelData.action }) }
                            Button { text: qsTr("Edit payload"); onClicked: schedulerJson.text = JSON.stringify(modelData, null, 2) }
                            Button { text: qsTr("Delete"); onClicked: taskController.deleteSchedulerRule(modelData.id) }
                        }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            } }
            Item { ColumnLayout { anchors.fill: parent; spacing: 12
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
                        ColumnLayout { anchors.fill: parent; anchors.margins: 12; spacing: 4; Label { Layout.fillWidth: true; text: modelData.task_id || qsTr("Task"); color: root.textColor; font.pixelSize: 12; font.weight: Font.Medium; elide: Text.ElideMiddle } Label { Layout.fillWidth: true; text: qsTr("Active: ") + (modelData.active_url || "—"); color: root.muted; font.pixelSize: 10; elide: Text.ElideMiddle } Label { Layout.fillWidth: true; text: qsTr("Mirrors: ") + (modelData.mirrors || []).map(function(x) { return x.url }).join(" · "); color: root.theme ? root.theme.information : "#8CB4EE"; font.pixelSize: 10; elide: Text.ElideMiddle } }
                    }
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                }
            } }
        }
    }
}
