#include "TaskController.h"

TaskController::TaskController(CoreAdapter *adapter, QObject *parent) : QObject(parent), m_adapter(adapter) {
    connect(m_adapter, &CoreAdapter::connectionChanged, this, &TaskController::connectionChanged);
    connect(m_adapter, &CoreAdapter::lastErrorChanged, this, &TaskController::lastErrorChanged);
    connect(m_adapter, &CoreAdapter::operationSucceeded, this, [this](const QString &action, const QString &) { emit notice(tr("Core operation completed: %1").arg(action), false); });
    connect(m_adapter, &CoreAdapter::operationFailed, this, [this](const QString &, const QString &message) { emit notice(message, true); });
    connect(m_adapter->downloads(), &QAbstractItemModel::modelReset, this, [this] { sampleSelectedSpeed(); emit selectedChanged(); });
}
DownloadModel *TaskController::downloads() const { return m_adapter->downloads(); }
bool TaskController::connected() const { return m_adapter->connected(); }
QString TaskController::lastError() const { return m_adapter->lastError(); }
QVariantMap TaskController::selectedDownload() const { return m_adapter->downloads()->get(m_selectedId); }
void TaskController::setSelectedId(const QString &id) { if (m_selectedId == id) return; m_selectedId = id; sampleSelectedSpeed(); emit selectedChanged(); }

void TaskController::sampleSelectedSpeed() {
    const auto task = selectedDownload();
    if (task.isEmpty()) { if (!m_speedSamples.isEmpty()) { m_speedSamples.clear(); emit speedSamplesChanged(); } return; }
    m_speedSamples.append(task.value("speed").toDouble());
    constexpr int maxSamples = 48;
    while (m_speedSamples.size() > maxSamples) m_speedSamples.removeFirst();
    emit speedSamplesChanged();
}
void TaskController::refresh() { m_adapter->refresh(); }
void TaskController::add(const QString &url, const QString &name, const QString &destination, const QString &category, const QString &profile, int priority, int connections, int bandwidthKbps, bool startImmediately) {
    const auto cleanUrl = url.trimmed();
    if (cleanUrl.isEmpty()) { emit notice(tr("A download URL is required."), true); return; }
    QVariantMap payload{{"url", cleanUrl}, {"name", name.trimmed()}, {"savePath", destination.trimmed()}, {"category", category}, {"startImmediately", startImmediately}};
    if (!profile.isEmpty()) payload.insert("profile", profile);
    if (priority >= 0) payload.insert("priority", priority);
    if (connections > 0) payload.insert("connections", connections);
    if (bandwidthKbps > 0) payload.insert("bandwidthLimitKbps", bandwidthKbps);
    m_adapter->createDownload(payload);
}
void TaskController::pauseSelected() { if (m_selectedId.isEmpty()) return; m_adapter->pause(m_selectedId); }
void TaskController::resumeSelected() { if (m_selectedId.isEmpty()) return; m_adapter->resume(m_selectedId); }
void TaskController::cancelSelected() { if (m_selectedId.isEmpty()) return; m_adapter->cancel(m_selectedId); }
void TaskController::retrySelected() { if (m_selectedId.isEmpty()) return; m_adapter->retry(m_selectedId); }
void TaskController::deleteSelected(bool files) { if (m_selectedId.isEmpty()) return; m_adapter->deleteDownload(m_selectedId, files); }
void TaskController::setBandwidthLimit(int kbps) { m_adapter->setBandwidthLimit(kbps); }
void TaskController::setSelectedPriority(int priority) { if (!m_selectedId.isEmpty()) m_adapter->setQueuePriority(m_selectedId, priority); }
