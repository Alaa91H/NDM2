#include "TaskController.h"

TaskController::TaskController(CoreAdapter *adapter, QObject *parent) : QObject(parent), m_adapter(adapter), m_filteredDownloads(this) {
    m_filteredDownloads.setSourceModel(m_adapter->downloads());
    connect(m_adapter, &CoreAdapter::connectionChanged, this, &TaskController::connectionChanged);
    connect(m_adapter, &CoreAdapter::lastErrorChanged, this, &TaskController::lastErrorChanged);
    connect(m_adapter, &CoreAdapter::queueChanged, this, &TaskController::queueChanged);
    connect(m_adapter, &CoreAdapter::bandwidthChanged, this, &TaskController::bandwidthChanged);
    connect(m_adapter, &CoreAdapter::profilesChanged, this, &TaskController::profilesChanged);
    connect(m_adapter, &CoreAdapter::statisticsChanged, this, &TaskController::statisticsChanged);
    connect(m_adapter, &CoreAdapter::logsChanged, this, &TaskController::logsChanged);
    connect(m_adapter, &CoreAdapter::rulesChanged, this, &TaskController::rulesChanged);
    connect(m_adapter, &CoreAdapter::schedulerChanged, this, &TaskController::schedulerChanged);
    connect(m_adapter, &CoreAdapter::mirrorsChanged, this, &TaskController::mirrorsChanged);
    connect(m_adapter, &CoreAdapter::taskTraceChanged, this, &TaskController::taskTraceChanged);
    connect(m_adapter, &CoreAdapter::healthChanged, this, &TaskController::healthChanged);
    connect(m_adapter, &CoreAdapter::logLevelChanged, this, &TaskController::logLevelChanged);
    connect(m_adapter, &CoreAdapter::browserHealthChanged, this, &TaskController::browserHealthChanged);
    connect(m_adapter, &CoreAdapter::mediaProbeChanged, this, &TaskController::mediaProbeChanged);
    connect(m_adapter, &CoreAdapter::ffmpegStatusChanged, this, &TaskController::ffmpegStatusChanged);
    connect(m_adapter, &CoreAdapter::capabilitiesChanged, this, &TaskController::capabilitiesChanged);
    connect(m_adapter, &CoreAdapter::retryPolicyChanged, this, &TaskController::retryPolicyChanged);
    connect(m_adapter, &CoreAdapter::operationSucceeded, this, [this](const QString &action, const QString &) { emit notice(tr("Core operation completed: %1").arg(action), false); });
    connect(m_adapter, &CoreAdapter::operationFailed, this, [this](const QString &, const QString &message) { emit notice(message, true); });
    connect(m_adapter->downloads(), &QAbstractItemModel::modelReset, this, [this] { sampleSelectedSpeed(); emit selectedChanged(); });
}
DownloadModel *TaskController::downloads() const { return m_adapter->downloads(); }
bool TaskController::connected() const { return m_adapter->connected(); }
QString TaskController::lastError() const { return m_adapter->lastError(); }
QVariantMap TaskController::selectedDownload() const { return m_adapter->downloads()->get(m_selectedId); }
QVariantList TaskController::queueEntries() const { return m_adapter->queueEntries(); }
QVariantMap TaskController::queueSummary() const { return m_adapter->queueSummary(); }
QVariantMap TaskController::bandwidth() const { return m_adapter->bandwidth(); }
QVariantList TaskController::profiles() const { return m_adapter->profiles(); }
QString TaskController::activeProfile() const { return m_adapter->activeProfile(); }
QVariantMap TaskController::statistics() const { return m_adapter->statistics(); }
QVariantList TaskController::logs() const { return m_adapter->logs(); }
QVariantList TaskController::rules() const { return m_adapter->rules(); }
QVariantList TaskController::schedulerRules() const { return m_adapter->schedulerRules(); }
QVariantList TaskController::schedulerActiveIds() const { return m_adapter->schedulerActiveIds(); }
QVariantList TaskController::mirrors() const { return m_adapter->mirrors(); }
QVariantMap TaskController::taskTrace() const { return m_adapter->taskTrace(); }
QVariantMap TaskController::health() const { return m_adapter->health(); }
QString TaskController::logLevel() const { return m_adapter->logLevel(); }
QVariantMap TaskController::browserHealth() const { return m_adapter->browserHealth(); }
QVariantMap TaskController::mediaProbe() const { return m_adapter->mediaProbe(); }
QString TaskController::mediaProbeError() const { return m_adapter->mediaProbeError(); }
QVariantMap TaskController::ffmpegStatus() const { return m_adapter->ffmpegStatus(); }
QVariantMap TaskController::capabilities() const { return m_adapter->capabilities(); }
QVariantMap TaskController::retryPolicy() const { return m_adapter->retryPolicy(); }
void TaskController::setSelectedId(const QString &id) { if (m_selectedId == id) return; m_selectedId = id; if (!id.isEmpty() && !m_selectedIds.contains(id)) m_selectedIds = {id}; m_adapter->fetchTaskTrace(id); sampleSelectedSpeed(); emit selectionChanged(); emit selectedChanged(); }
void TaskController::sampleSelectedSpeed() { const auto task = selectedDownload(); if (task.isEmpty()) { if (!m_speedSamples.isEmpty()) { m_speedSamples.clear(); emit speedSamplesChanged(); } return; } m_speedSamples.append(task.value("speed").toDouble()); while (m_speedSamples.size() > 48) m_speedSamples.removeFirst(); emit speedSamplesChanged(); }
void TaskController::refresh() { m_adapter->refresh(); }
void TaskController::refreshAll() { m_adapter->refreshAll(); }
void TaskController::add(const QString &url, const QString &name, const QString &destination, const QString &category, int connections, int bandwidthKbps, bool startImmediately) {
    const auto cleanUrl = url.trimmed(); if (cleanUrl.isEmpty()) { emit notice(tr("A download URL is required."), true); return; }
    QVariantMap payload{{"url", cleanUrl}, {"name", name.trimmed()}, {"savePath", destination.trimmed()}, {"category", category}, {"startImmediately", startImmediately}};
    if (connections > 0) payload.insert("connections", connections);
    if (bandwidthKbps > 0) payload.insert("directOptions", QVariantMap{{"speedLimitKbs", bandwidthKbps}});
    m_adapter->createDownload(payload);
}
void TaskController::updateSelected(const QString &name, const QString &url) { if (m_selectedId.isEmpty()) return; QVariantMap patch; if (!name.trimmed().isEmpty()) patch.insert("name", name.trimmed()); if (!url.trimmed().isEmpty()) patch.insert("url", url.trimmed()); if (patch.isEmpty()) return; m_adapter->updateDownload(m_selectedId, patch); }
void TaskController::pauseSelected() { if (!m_selectedId.isEmpty()) m_adapter->pause(m_selectedId); }
void TaskController::resumeSelected() { if (!m_selectedId.isEmpty()) m_adapter->resume(m_selectedId); }
void TaskController::pauseAll() { m_adapter->pauseAll(); }
void TaskController::resumeAll() { m_adapter->resumeAll(); }
void TaskController::cancelSelected() { if (!m_selectedId.isEmpty()) m_adapter->cancel(m_selectedId); }
void TaskController::retrySelected() { if (!m_selectedId.isEmpty()) m_adapter->retry(m_selectedId); }
void TaskController::deleteSelected(bool files) { if (!m_selectedId.isEmpty()) m_adapter->deleteDownload(m_selectedId, files); }
void TaskController::setBandwidthLimit(int kbps) { m_adapter->setBandwidthLimit(kbps); }
void TaskController::setSelectedPriority(int priority) { if (!m_selectedId.isEmpty()) m_adapter->setQueuePriority(m_selectedId, priority); }
void TaskController::setActiveProfile(const QString &profileId) { if (!profileId.isEmpty()) m_adapter->setActiveProfile(profileId); }

void TaskController::addRule(const QVariantMap &rule) { m_adapter->addRule(rule); }
void TaskController::deleteRule(const QString &id) { m_adapter->deleteRule(id); }
void TaskController::addSchedulerRule(const QVariantMap &rule) { m_adapter->addSchedulerRule(rule); }
void TaskController::updateSchedulerRule(const QVariantMap &rule) { m_adapter->updateSchedulerRule(rule); }
void TaskController::deleteSchedulerRule(const QString &id) { m_adapter->deleteSchedulerRule(id); }
void TaskController::setSchedulerPowerCommands(bool enabled) { m_adapter->setSchedulerPowerCommands(enabled); }
void TaskController::addSelectedMirror(const QString &url, int priority) { if (m_selectedId.isEmpty() || url.trimmed().isEmpty()) { emit notice(tr("Select a task and provide a mirror URL."), true); return; } m_adapter->addMirror(m_selectedId, url.trimmed(), priority); }
void TaskController::setSelectedMirrorFailover(bool enabled) { if (!m_selectedId.isEmpty()) m_adapter->setMirrorFailover(m_selectedId, enabled); }
void TaskController::triggerSelectedMirrorFailover() { if (!m_selectedId.isEmpty()) m_adapter->triggerMirrorFailover(m_selectedId); }
void TaskController::setLogLevel(const QString &level) { m_adapter->setLogLevel(level); }

void TaskController::setLibraryFilters(const QString &search, const QString &status, const QString &category, const QString &queue) { m_filteredDownloads.setFilters(search, status, category, queue); }
void TaskController::setLibrarySort(const QString &field, bool descending) { m_filteredDownloads.sortBy(field, descending); }
bool TaskController::isSelected(const QString &id) const { return m_selectedIds.contains(id); }
void TaskController::toggleSelection(const QString &id, bool exclusive) {
    if (id.isEmpty()) return;
    if (exclusive) m_selectedIds = {id};
    else if (m_selectedIds.contains(id)) m_selectedIds.removeAll(id);
    else m_selectedIds.push_back(id);
    m_selectedId = m_selectedIds.isEmpty() ? QString() : m_selectedIds.last();
    if (!m_selectedId.isEmpty()) m_adapter->fetchTaskTrace(m_selectedId);
    sampleSelectedSpeed(); emit selectionChanged(); emit selectedChanged();
}
void TaskController::selectAllFiltered() { QStringList ids; for (int row = 0; row < m_filteredDownloads.rowCount(); ++row) ids.push_back(m_filteredDownloads.data(m_filteredDownloads.index(row, 0), DownloadModel::IdRole).toString()); m_selectedIds = ids; m_selectedId = ids.isEmpty() ? QString() : ids.last(); emit selectionChanged(); emit selectedChanged(); }
void TaskController::clearSelection() { if (m_selectedIds.isEmpty() && m_selectedId.isEmpty()) return; m_selectedIds.clear(); m_selectedId.clear(); sampleSelectedSpeed(); emit selectionChanged(); emit selectedChanged(); }
void TaskController::bulkPause() { for (const auto &id : m_selectedIds) m_adapter->pause(id); }
void TaskController::bulkResume() { for (const auto &id : m_selectedIds) m_adapter->resume(id); }
void TaskController::bulkRetry() { for (const auto &id : m_selectedIds) m_adapter->retry(id); }
void TaskController::bulkDelete(bool files) { for (const auto &id : m_selectedIds) m_adapter->deleteDownload(id, files); clearSelection(); }
void TaskController::bulkSetPriority(int priority) { for (const auto &id : m_selectedIds) m_adapter->setQueuePriority(id, priority); }

void TaskController::probeMedia(const QString &url) { m_adapter->probeMedia(url); }

void TaskController::createMediaDownload(const QString &url, const QString &name, const QString &destination, const QString &formatId, bool audioOnly) {
    const auto cleanUrl = url.trimmed();
    if (cleanUrl.isEmpty() || formatId.trimmed().isEmpty()) { emit notice(tr("Probe a media URL and select a Core-reported format first."), true); return; }
    QVariantMap media{{"mode", audioOnly ? "audio" : "video"}, {"formatSelector", formatId.trimmed()}, {"ffmpegEnabled", !audioOnly}, {"playlist", false}};
    QVariantMap payload{{"url", cleanUrl}, {"name", name.trimmed().isEmpty() ? QStringLiteral("media-download") : name.trimmed()}, {"fileType", audioOnly ? "audio" : "video"}, {"category", audioOnly ? "audio" : "video"}, {"connections", 1}, {"resumable", true}, {"startImmediately", true}, {"mediaOptions", media}};
    if (!destination.trimmed().isEmpty()) payload.insert("savePath", destination.trimmed());
    m_adapter->createDownload(payload);
}
void TaskController::refreshLogsFiltered(int limit, const QString &level) {
    Q_UNUSED(level);
    // Core currently exposes the full structured log collection through this adapter; filtering is performed by the QML view without altering the daemon contract.
    m_adapter->refreshLogs(limit);
}

void TaskController::setRetryPolicyPreset(const QString &preset) { m_adapter->setRetryPolicyPreset(preset); }
