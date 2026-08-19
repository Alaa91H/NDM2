#pragma once

#include "adapter/CoreAdapter.h"

class TaskController final : public QObject {
    Q_OBJECT
    Q_PROPERTY(DownloadModel *downloads READ downloads CONSTANT)
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
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

public:
    explicit TaskController(CoreAdapter *adapter, QObject *parent = nullptr);
    DownloadModel *downloads() const; bool connected() const; QString lastError() const;
    QString selectedId() const { return m_selectedId; }
    QVariantMap selectedDownload() const;
    QVariantList speedSamples() const { return m_speedSamples; }
    QVariantList queueEntries() const; QVariantMap queueSummary() const; QVariantMap bandwidth() const;
    QVariantList profiles() const; QString activeProfile() const; QVariantMap statistics() const; QVariantList logs() const;

    Q_INVOKABLE void add(const QString &url, const QString &name, const QString &destination, const QString &category, int connections, int bandwidthKbps, bool startImmediately);
    Q_INVOKABLE void updateSelected(const QString &name, const QString &url);
    Q_INVOKABLE void pauseSelected(); Q_INVOKABLE void resumeSelected(); Q_INVOKABLE void pauseAll(); Q_INVOKABLE void resumeAll(); Q_INVOKABLE void cancelSelected(); Q_INVOKABLE void retrySelected(); Q_INVOKABLE void deleteSelected(bool files = false);
    Q_INVOKABLE void refresh(); Q_INVOKABLE void refreshAll(); Q_INVOKABLE void setBandwidthLimit(int kbps); Q_INVOKABLE void setSelectedPriority(int priority); Q_INVOKABLE void setActiveProfile(const QString &profileId);
    void setSelectedId(const QString &id);

signals:
    void connectionChanged(); void lastErrorChanged(); void selectedChanged(); void speedSamplesChanged();
    void queueChanged(); void bandwidthChanged(); void profilesChanged(); void statisticsChanged(); void logsChanged();
    void notice(QString message, bool error);

private:
    CoreAdapter *m_adapter;
    QString m_selectedId;
    QVariantList m_speedSamples;
    void sampleSelectedSpeed();
};
