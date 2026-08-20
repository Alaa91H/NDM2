import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"

WorkspaceWindow {
    id: root

    pageTitle: qsTr("Automation")
    pageSubtitle: qsTr("Create and manage verified NOVA Core rules, schedules, and mirror failover plans.")
    glyph: "⌘"
    statusText: qsTr("%1 rules · %2 schedules").arg(root.collectionCount(taskController.rules)).arg(root.collectionCount(taskController.schedulerRules))
    actionText: qsTr("Refresh")
    onActionRequested: taskController.refreshAll()

    property color surface: "#142239"
    property color textColor: "#EAF1FF"
    property color muted: "#8D9AB0"
    property string activePane: "rules"
    property string ruleValidation: ""
    property string schedulerValidation: ""

    function ruleId(prefix) { return prefix + "-" + Date.now() }
    function collectionCount(value) { return value && value.length !== undefined ? value.length : (value && value.count !== undefined ? value.count : 0) }
    function safeJson(text) { try { return JSON.parse(text) } catch (e) { return null } }
    function schedulerTrigger() {
        if (schedulerTriggerBox.currentText === "TimeWindow")
            return { "type": "TimeWindow", "start_hour": startHour.value, "start_minute": startMinute.value, "end_hour": endHour.value, "end_minute": endMinute.value }
        if (schedulerTriggerBox.currentText === "BandwidthBelow")
            return { "type": "BandwidthBelow", "threshold_kbps": schedulerNumber.value }
        return { "type": schedulerTriggerBox.currentText }
    }
    function schedulerAction() {
        var ids = schedulerTaskIds.text.trim().split(",").filter(function(x) { return x.trim().length > 0 })
        if (schedulerActionBox.currentText === "StartDownload" || schedulerActionBox.currentText === "PauseDownload")
            return { "type": schedulerActionBox.currentText, "task_ids": ids }
        if (schedulerActionBox.currentText === "SetBandwidthLimit")
            return { "type": "SetBandwidthLimit", "kbps": schedulerNumber.value }
        if (schedulerActionBox.currentText === "SetPriority")
            return { "type": "SetPriority", "task_ids": ids, "priority": schedulerPriority.currentText }
        if (schedulerActionBox.currentText === "Notify")
            return { "type": "Notify", "message": schedulerMessage.text.trim() || schedulerName.text.trim() }
        return { "type": schedulerActionBox.currentText }
    }
    function addGuidedScheduler() {
        if (schedulerName.text.trim().length === 0) {
            schedulerValidation = qsTr("A schedule name is required.")
            return
        }
        taskController.addSchedulerRule({ "id": root.ruleId("schedule"), "name": schedulerName.text.trim(), "enabled": true, "trigger": schedulerTrigger(), "action": schedulerAction() })
        schedulerValidation = ""
        schedulerName.clear()
    }

    component FieldCaption: Label {
        color: root.theme ? root.theme.textMuted : root.muted
        font.pixelSize: root.theme ? root.theme.fontMeta : 10
        font.weight: Font.DemiBold
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: theme ? theme.spaceMd : 12

        InfoCard {
            Layout.fillWidth: true
            Layout.preferredHeight: root.theme ? root.theme.touchHeight : 40
            theme: root.theme
            emphasized: false
            contentPadding: root.theme ? root.theme.space2xs : 2
            RowLayout {
                Layout.fillWidth: true
                spacing: root.theme ? root.theme.spaceXs : 4
                Repeater {
                    model: [
                        ["rules", qsTr("Rules"), "⌘"],
                        ["scheduler", qsTr("Scheduler"), "◷"],
                        ["mirrors", qsTr("Mirrors"), "⇄"]
                    ]
                    delegate: ActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData[2] + "  " + modelData[1]
                        tone: root.activePane === modelData[0] ? "primary" : "quiet"
                        dark: settingsService.dark
                        theme: root.theme
                        onClicked: root.activePane = modelData[0]
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.activePane === "rules" ? 0 : root.activePane === "scheduler" ? 1 : 2

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.theme ? root.theme.spaceMd : 12

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 270
                        spacing: root.theme ? root.theme.spaceMd : 12

                        InfoCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: parent.width * .43
                            theme: root.theme
                            emphasized: true
                            Label { text: qsTr("Quick rule"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                            Label { text: qsTr("Match a URL phrase and set a category. Use the schema editor for advanced Core conditions."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: root.theme ? root.theme.spaceSm : 8
                                rowSpacing: root.theme ? root.theme.spaceXs : 4
                                FieldCaption { text: qsTr("Rule name"); Layout.fillWidth: true }
                                FieldCaption { text: qsTr("Priority"); Layout.fillWidth: true }
                                ThemedTextField { id: ruleName; Layout.fillWidth: true; placeholderText: qsTr("e.g. Course files"); theme: root.theme; dark: settingsService.dark; leadingGlyph: "✦" }
                                ThemedSpinBox { id: rulePriority; Layout.fillWidth: true; from: 0; to: 9999; value: 100; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Rule priority") }
                                FieldCaption { text: qsTr("URL contains"); Layout.fillWidth: true }
                                FieldCaption { text: qsTr("Category"); Layout.fillWidth: true }
                                ThemedTextField { id: ruleNeedle; Layout.fillWidth: true; placeholderText: qsTr("example.org"); theme: root.theme; dark: settingsService.dark; leadingGlyph: "⌕" }
                                ThemedTextField { id: ruleCategory; Layout.fillWidth: true; placeholderText: qsTr("Documents"); theme: root.theme; dark: settingsService.dark; leadingGlyph: "▣" }
                            }
                            Item { Layout.fillHeight: true }
                            ActionButton {
                                Layout.fillWidth: true
                                text: qsTr("Create rule")
                                tone: "primary"
                                dark: settingsService.dark
                                theme: root.theme
                                enabled: ruleName.text.trim().length > 0 && ruleNeedle.text.trim().length > 0 && ruleCategory.text.trim().length > 0
                                onClicked: {
                                    taskController.addRule({ "id": root.ruleId("rule"), "name": ruleName.text.trim(), "enabled": true, "priority": rulePriority.value, "conditions": [{ "type": "UrlContains", "text": ruleNeedle.text.trim() }], "action": { "type": "SetCategory", "category": ruleCategory.text.trim() } })
                                    ruleName.clear()
                                    ruleNeedle.clear()
                                    ruleCategory.clear()
                                }
                            }
                        }

                        InfoCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.preferredWidth: parent.width * .57
                            theme: root.theme
                            Label { text: qsTr("Core schema editor"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                            Label { text: qsTr("Paste an exact DownloadRule payload supported by NOVA Core."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11 }
                            ThemedTextArea {
                                id: ruleJson
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                theme: root.theme
                                dark: settingsService.dark
                                monospace: true
                                text: '{\n  "id": "rule-example",\n  "name": "Host category",\n  "enabled": true,\n  "priority": 100,\n  "conditions": [{"type":"HostnameContains","text":"example.org"}],\n  "action": {"type":"SetCategory","category":"Documents"}\n}'
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; text: root.ruleValidation; color: root.theme ? root.theme.danger : "#FF8794"; font.pixelSize: root.theme ? root.theme.fontCaption : 11; elide: Text.ElideRight }
                                ActionButton {
                                    text: qsTr("Add Core rule")
                                    tone: "primary"
                                    dark: settingsService.dark
                                    theme: root.theme
                                    onClicked: {
                                        var value = root.safeJson(ruleJson.text)
                                        if (!value || !value.id || !value.action || !value.conditions)
                                            root.ruleValidation = qsTr("Enter a complete Core DownloadRule JSON object.")
                                        else {
                                            root.ruleValidation = ""
                                            taskController.addRule(value)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    InfoCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        theme: root.theme
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: qsTr("Saved Core rules"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                            Item { Layout.fillWidth: true }
                            Label { text: qsTr("%1 rules").arg(root.collectionCount(taskController.rules)); color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11 }
                        }
                        ListView {
                            id: rulesList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: root.theme ? root.theme.spaceXs : 4
                            model: taskController.rules
                            delegate: InfoCard {
                                required property var modelData
                                width: rulesList.width
                                height: 76
                                theme: root.theme
                                emphasized: true
                                contentPadding: root.theme ? root.theme.spaceSm : 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle { Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 15; color: root.theme ? root.theme.accentSoft : "#19365E"; Text { anchors.centerIn: parent; text: "⌘"; color: root.theme ? root.theme.accent : "#5C9EFF"; font.pixelSize: 14 } }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Label { Layout.fillWidth: true; text: modelData.name || modelData.id; color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBody : 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                        Label { Layout.fillWidth: true; text: JSON.stringify(modelData); color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontMeta : 10; elide: Text.ElideRight }
                                    }
                                    StatusBadge { status: modelData.enabled ? "active" : "paused"; labelOverride: modelData.enabled ? qsTr("Enabled") : qsTr("Disabled"); dark: settingsService.dark; theme: root.theme }
                                    IconButton { glyph: "⌘"; accessibleLabel: qsTr("Copy rule payload"); dark: settingsService.dark; theme: root.theme; onClicked: ruleJson.text = JSON.stringify(modelData, null, 2) }
                                    IconButton { glyph: "×"; accessibleLabel: qsTr("Delete rule"); tone: "danger"; dark: settingsService.dark; theme: root.theme; onClicked: taskController.deleteRule(modelData.id) }
                                }
                            }
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.theme ? root.theme.spaceMd : 12
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 316
                        spacing: root.theme ? root.theme.spaceMd : 12

                        InfoCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            theme: root.theme
                            emphasized: true
                            Label { text: qsTr("Schedule builder"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                            Label { text: qsTr("Create a real Core scheduler rule from its supported trigger and action types."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11; wrapMode: Text.Wrap; Layout.fillWidth: true }
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 4
                                columnSpacing: root.theme ? root.theme.spaceSm : 8
                                rowSpacing: root.theme ? root.theme.spaceXs : 4
                                ThemedTextField { id: schedulerName; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Schedule name"); theme: root.theme; dark: settingsService.dark; leadingGlyph: "◷" }
                                ThemedComboBox { id: schedulerTriggerBox; Layout.fillWidth: true; model: ["TimeWindow", "BandwidthBelow", "QueueEmpty", "AllComplete"]; theme: root.theme; dark: settingsService.dark }
                                ThemedComboBox { id: schedulerActionBox; Layout.fillWidth: true; model: ["StartDownload", "PauseDownload", "SetBandwidthLimit", "SetPriority", "Notify", "Shutdown", "Sleep"]; theme: root.theme; dark: settingsService.dark }
                                ThemedSpinBox { id: startHour; from: 0; to: 23; value: 0; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow"; theme: root.theme; dark: settingsService.dark }
                                ThemedSpinBox { id: startMinute; from: 0; to: 59; value: 0; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow"; theme: root.theme; dark: settingsService.dark }
                                ThemedSpinBox { id: endHour; from: 0; to: 23; value: 23; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow"; theme: root.theme; dark: settingsService.dark }
                                ThemedSpinBox { id: endMinute; from: 0; to: 59; value: 59; Layout.fillWidth: true; enabled: schedulerTriggerBox.currentText === "TimeWindow"; theme: root.theme; dark: settingsService.dark }
                                ThemedSpinBox { id: schedulerNumber; from: 0; to: 1000000; value: 0; Layout.fillWidth: true; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Bandwidth limit in KB per second") }
                                ThemedTextField { id: schedulerTaskIds; Layout.columnSpan: 2; Layout.fillWidth: true; placeholderText: qsTr("Task IDs, comma separated"); theme: root.theme; dark: settingsService.dark }
                                ThemedComboBox { id: schedulerPriority; Layout.fillWidth: true; model: ["critical", "high", "normal", "low", "background"]; theme: root.theme; dark: settingsService.dark }
                                ThemedTextField { id: schedulerMessage; Layout.fillWidth: true; placeholderText: qsTr("Notification message"); theme: root.theme; dark: settingsService.dark }
                            }
                            ThemedSwitch { id: powerCommands; text: qsTr("Permit Core power commands"); theme: root.theme; dark: settingsService.dark; onToggled: taskController.setSchedulerPowerCommands(checked) }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; text: root.schedulerValidation; color: root.theme ? root.theme.danger : "#FF8794"; font.pixelSize: root.theme ? root.theme.fontCaption : 11; elide: Text.ElideRight }
                                ActionButton { text: qsTr("Add schedule"); tone: "primary"; dark: settingsService.dark; theme: root.theme; onClicked: root.addGuidedScheduler() }
                            }
                        }

                        InfoCard {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            theme: root.theme
                            Label { text: qsTr("Core scheduler schema"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                            Label { text: qsTr("Use the exact SchedulerRule schema when the quick builder is not enough."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11 }
                            ThemedTextArea {
                                id: schedulerJson
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                theme: root.theme
                                dark: settingsService.dark
                                monospace: true
                                text: '{\n  "id": "schedule-example",\n  "name": "Night limit",\n  "enabled": true,\n  "trigger": {"type":"TimeWindow","start_hour":22,"start_minute":0,"end_hour":6,"end_minute":0},\n  "action": {"type":"SetBandwidthLimit","kbps":256}\n}'
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Label { Layout.fillWidth: true; text: root.schedulerValidation; color: root.theme ? root.theme.danger : "#FF8794"; font.pixelSize: root.theme ? root.theme.fontCaption : 11; elide: Text.ElideRight }
                                ActionButton { text: qsTr("Add schedule"); tone: "primary"; dark: settingsService.dark; theme: root.theme; onClicked: { var value = root.safeJson(schedulerJson.text); if (!value || !value.id || !value.trigger || !value.action) root.schedulerValidation = qsTr("Enter a complete Core SchedulerRule JSON object."); else { root.schedulerValidation = ""; taskController.addSchedulerRule(value) } } }
                                ActionButton { text: qsTr("Update"); tone: "quiet"; dark: settingsService.dark; theme: root.theme; onClicked: { var value = root.safeJson(schedulerJson.text); if (!value || !value.id || !value.trigger || !value.action) root.schedulerValidation = qsTr("Enter a complete Core SchedulerRule JSON object."); else { root.schedulerValidation = ""; taskController.updateSchedulerRule(value) } } }
                            }
                        }
                    }

                    InfoCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        theme: root.theme
                        RowLayout {
                            Layout.fillWidth: true
                            Label { text: qsTr("Scheduled actions"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                            Item { Layout.fillWidth: true }
                            Label { text: qsTr("%1 schedules").arg(root.collectionCount(taskController.schedulerRules)); color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11 }
                        }
                        ListView {
                            id: schedulerList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: root.theme ? root.theme.spaceXs : 4
                            model: taskController.schedulerRules
                            delegate: InfoCard {
                                required property var modelData
                                width: schedulerList.width
                                height: 74
                                theme: root.theme
                                emphasized: true
                                contentPadding: root.theme ? root.theme.spaceSm : 8
                                RowLayout {
                                    Layout.fillWidth: true
                                    Rectangle { Layout.preferredWidth: 30; Layout.preferredHeight: 30; radius: 15; color: root.theme ? root.theme.accentSoft : "#19365E"; Text { anchors.centerIn: parent; text: "◷"; color: root.theme ? root.theme.accent : "#5C9EFF"; font.pixelSize: 14 } }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Label { Layout.fillWidth: true; text: modelData.name || modelData.id; color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBody : 12; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                        Label { Layout.fillWidth: true; text: JSON.stringify(modelData); color: root.theme ? root.theme.textMuted : root.muted; font.pixelSize: root.theme ? root.theme.fontMeta : 10; elide: Text.ElideRight }
                                    }
                                    ThemedSwitch { checked: modelData.enabled; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Enable schedule %1").arg(modelData.name || modelData.id); onToggled: taskController.updateSchedulerRule({ "id": modelData.id, "name": modelData.name, "enabled": checked, "trigger": modelData.trigger, "action": modelData.action }) }
                                    IconButton { glyph: "⌘"; accessibleLabel: qsTr("Edit schedule payload"); theme: root.theme; dark: settingsService.dark; onClicked: schedulerJson.text = JSON.stringify(modelData, null, 2) }
                                    IconButton { glyph: "×"; accessibleLabel: qsTr("Delete schedule"); tone: "danger"; theme: root.theme; dark: settingsService.dark; onClicked: taskController.deleteSchedulerRule(modelData.id) }
                                }
                            }
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                    }
                }
            }

            Item {
                ColumnLayout {
                    anchors.fill: parent
                    spacing: root.theme ? root.theme.spaceMd : 12
                    InfoCard {
                        Layout.fillWidth: true
                        theme: root.theme
                        emphasized: true
                        RowLayout {
                            Layout.fillWidth: true
                            Rectangle { Layout.preferredWidth: 36; Layout.preferredHeight: 36; radius: root.theme ? root.theme.radiusSm : 8; color: root.theme ? root.theme.accentSoft : "#19365E"; Text { anchors.centerIn: parent; text: "⇄"; color: root.theme ? root.theme.accent : "#5C9EFF"; font.pixelSize: 17 } }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                Label { text: qsTr("Mirror failover"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                                Label { Layout.fillWidth: true; text: taskController.selectedDownload.name || qsTr("Select a download in the library to manage its mirrors."); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11; elide: Text.ElideRight }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            ThemedTextField { id: mirrorUrl; Layout.fillWidth: true; placeholderText: qsTr("https://mirror.example/file"); theme: root.theme; dark: settingsService.dark; leadingGlyph: "↗" }
                            ThemedSpinBox { id: mirrorPriority; Layout.preferredWidth: 92; from: 0; to: 99; value: 0; theme: root.theme; dark: settingsService.dark; Accessible.name: qsTr("Mirror priority") }
                            ActionButton { text: qsTr("Add mirror"); tone: "secondary"; dark: settingsService.dark; theme: root.theme; enabled: taskController.selectedId.length > 0 && mirrorUrl.text.trim().length > 0; onClicked: { taskController.addSelectedMirror(mirrorUrl.text, mirrorPriority.value); mirrorUrl.clear() } }
                            ActionButton { text: qsTr("Fail over"); tone: "quiet"; dark: settingsService.dark; theme: root.theme; enabled: taskController.selectedId.length > 0; onClicked: taskController.triggerSelectedMirrorFailover() }
                        }
                    }
                    InfoCard {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        theme: root.theme
                        Label { text: qsTr("Mirror status from Core"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBodyLarge : 14; font.weight: Font.DemiBold }
                        ListView {
                            id: mirrorList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: root.theme ? root.theme.spaceXs : 4
                            model: taskController.mirrors
                            delegate: InfoCard {
                                required property var modelData
                                width: mirrorList.width
                                height: 82
                                theme: root.theme
                                emphasized: true
                                contentPadding: root.theme ? root.theme.spaceSm : 8
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Label { Layout.fillWidth: true; text: modelData.task_id || qsTr("Task"); color: root.theme ? root.theme.textPrimary : root.textColor; font.pixelSize: root.theme ? root.theme.fontBody : 12; font.weight: Font.DemiBold; elide: Text.ElideMiddle }
                                    Label { Layout.fillWidth: true; text: qsTr("Active source: ") + (modelData.active_url || "—"); color: root.theme ? root.theme.textSecondary : root.muted; font.pixelSize: root.theme ? root.theme.fontCaption : 11; elide: Text.ElideMiddle }
                                    Label { Layout.fillWidth: true; text: qsTr("Alternates: ") + (modelData.mirrors || []).map(function(x) { return x.url }).join("  ·  "); color: root.theme ? root.theme.information : "#8CB4EE"; font.pixelSize: root.theme ? root.theme.fontCaption : 11; elide: Text.ElideMiddle }
                                }
                            }
                            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                        }
                    }
                }
            }
        }
    }
}
