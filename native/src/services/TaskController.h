#pragma once

#include "adapter/CoreAdapter.h"
#include "models/DownloadFilterProxyModel.h"

class TaskController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(DownloadModel *downloads READ downloads CONSTANT)
    Q_PROPERTY(DownloadFilterProxyModel *filteredDownloads READ filteredDownloads CONSTANT)
    Q_PROPERTY(QStringList selectedIds READ selectedIds NOTIFY selectionChanged)
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(QString endpoint READ endpoint NOTIFY connectionChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QString selectedId READ selectedId WRITE setSelectedId NOTIFY selectedChanged)
    Q_PROPERTY(QVariantMap selectedDownload READ selectedDownload NOTIFY selectedChanged)
    Q_PROPERTY(QVariantList speedSamples READ speedSamples NOTIFY speedSamplesChanged)
    Q_PROPERTY(QVariantList queueEntries READ queueEntries NOTIFY queueChanged)
    Q_PROPERTY(QVariantMap queueSummary READ queueSummary NOTIFY queueChanged)
    Q_PROPERTY(QVariantMap bandwidth READ bandwidth NOTIFY bandwidthChanged)
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(QString activeProfile READ activeProfile NOTIFY profilesChanged)
    Q_PROPERTY(QVariantMap statistics READ statistics NOTIFY statisticsChanged)
    Q_PROPERTY(QVariantList logs READ logs NOTIFY logsChanged)
    Q_PROPERTY(QVariantList rules READ rules NOTIFY rulesChanged)
    Q_PROPERTY(QVariantList schedulerRules READ schedulerRules NOTIFY schedulerChanged)
    Q_PROPERTY(QVariantList schedulerActiveIds READ schedulerActiveIds NOTIFY schedulerChanged)
    Q_PROPERTY(QVariantList mirrors READ mirrors NOTIFY mirrorsChanged)
    Q_PROPERTY(QVariantMap taskTrace READ taskTrace NOTIFY taskTraceChanged)
    Q_PROPERTY(QVariantMap health READ health NOTIFY healthChanged)
    Q_PROPERTY(QString logLevel READ logLevel NOTIFY logLevelChanged)
    Q_PROPERTY(QVariantMap browserHealth READ browserHealth NOTIFY browserHealthChanged)
    Q_PROPERTY(QVariantMap mediaProbe READ mediaProbe NOTIFY mediaProbeChanged)
    Q_PROPERTY(QString mediaProbeError READ mediaProbeError NOTIFY mediaProbeChanged)
    Q_PROPERTY(QVariantMap ffmpegStatus READ ffmpegStatus NOTIFY ffmpegStatusChanged)
    Q_PROPERTY(QVariantMap capabilities READ capabilities NOTIFY capabilitiesChanged)
    Q_PROPERTY(QVariantMap retryPolicy READ retryPolicy NOTIFY retryPolicyChanged)

public:
    explicit TaskController(CoreAdapter *adapter, QObject *parent = nullptr);
    DownloadModel *downloads() const; DownloadFilterProxyModel *filteredDownloads() { return &m_filteredDownloads; } bool connected() const; QString endpoint() const { return m_adapter->endpoint(); } QString lastError() const;
    QStringList selectedIds() const { return m_selectedIds; }
    QString selectedId() const { return m_selectedId; }
    QVariantMap selectedDownload() const;
    QVariantList speedSamples() const { return m_speedSamples; }
    QVariantList queueEntries() const; QVariantMap queueSummary() const; QVariantMap bandwidth() const;
    QVariantList profiles() const; QString activeProfile() const; QVariantMap statistics() const; QVariantList logs() const;
    QVariantList rules() const; QVariantList schedulerRules() const; QVariantList schedulerActiveIds() const; QVariantList mirrors() const;
    QVariantMap taskTrace() const; QVariantMap health() const; QString logLevel() const; QVariantMap browserHealth() const; QVariantMap mediaProbe() const; QString mediaProbeError() const; QVariantMap ffmpegStatus() const; QVariantMap capabilities() const; QVariantMap retryPolicy() const;

    Q_INVOKABLE void add(const QString &url, const QString &name, const QString &destination, const QString &category, int connections, int bandwidthKbps, bool startImmediately);
    Q_INVOKABLE void updateSelected(const QString &name, const QString &url);
    Q_INVOKABLE void pauseSelected(); Q_INVOKABLE void resumeSelected(); Q_INVOKABLE void pauseAll(); Q_INVOKABLE void resumeAll(); Q_INVOKABLE void cancelSelected(); Q_INVOKABLE void retrySelected(); Q_INVOKABLE void deleteSelected(bool files = false);
    Q_INVOKABLE void refresh(); Q_INVOKABLE void refreshAll(); Q_INVOKABLE void setBandwidthLimit(int kbps); Q_INVOKABLE void setSelectedPriority(int priority); Q_INVOKABLE void setActiveProfile(const QString &profileId);
    Q_INVOKABLE void addRule(const QVariantMap &rule); Q_INVOKABLE void deleteRule(const QString &id);
    Q_INVOKABLE void addSchedulerRule(const QVariantMap &rule); Q_INVOKABLE void updateSchedulerRule(const QVariantMap &rule); Q_INVOKABLE void deleteSchedulerRule(const QString &id); Q_INVOKABLE void setSchedulerPowerCommands(bool enabled);
    Q_INVOKABLE void addSelectedMirror(const QString &url, int priority = 0); Q_INVOKABLE void setSelectedMirrorFailover(bool enabled); Q_INVOKABLE void triggerSelectedMirrorFailover();
    Q_INVOKABLE void setLogLevel(const QString &level); Q_INVOKABLE void setRetryPolicyPreset(const QString &preset); Q_INVOKABLE void probeMedia(const QString &url); Q_INVOKABLE void createMediaDownload(const QString &url, const QString &name, const QString &destination, const QString &formatId, bool audioOnly = false); Q_INVOKABLE void refreshLogsFiltered(int limit, const QString &level);
    Q_INVOKABLE void setLibraryFilters(const QString &search, const QString &status, const QString &category, const QString &queue);
    Q_INVOKABLE void setLibrarySort(const QString &field, bool descending = false);
    Q_INVOKABLE bool isSelected(const QString &id) const;
    Q_INVOKABLE void toggleSelection(const QString &id, bool exclusive = false);
    Q_INVOKABLE void selectAllFiltered(); Q_INVOKABLE void clearSelection();
    Q_INVOKABLE void bulkPause(); Q_INVOKABLE void bulkResume(); Q_INVOKABLE void bulkRetry(); Q_INVOKABLE void bulkDelete(bool files = false); Q_INVOKABLE void bulkSetPriority(int priority);
    void setSelectedId(const QString &id);

signals:
    void connectionChanged(); void lastErrorChanged(); void selectedChanged(); void speedSamplesChanged();
    void queueChanged(); void bandwidthChanged(); void profilesChanged(); void statisticsChanged(); void logsChanged();
    void rulesChanged(); void schedulerChanged(); void mirrorsChanged(); void taskTraceChanged(); void healthChanged(); void logLevelChanged(); void browserHealthChanged(); void mediaProbeChanged(); void ffmpegStatusChanged(); void capabilitiesChanged(); void retryPolicyChanged(); void selectionChanged();
    void notice(QString message, bool error);

private:
    CoreAdapter *m_adapter;
    QString m_selectedId;
    QVariantList m_speedSamples;
    DownloadFilterProxyModel m_filteredDownloads;
    QStringList m_selectedIds;
    void sampleSelectedSpeed();
};
