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

public:
    explicit TaskController(CoreAdapter *adapter, QObject *parent = nullptr);
    DownloadModel *downloads() const;
    bool connected() const;
    QString lastError() const;
    QString selectedId() const { return m_selectedId; }
    QVariantMap selectedDownload() const;
    QVariantList speedSamples() const { return m_speedSamples; }

    Q_INVOKABLE void add(const QString &url, const QString &name, const QString &destination, const QString &category, const QString &profile, int priority, int connections, int bandwidthKbps, bool startImmediately);
    Q_INVOKABLE void pauseSelected(); Q_INVOKABLE void resumeSelected(); Q_INVOKABLE void cancelSelected(); Q_INVOKABLE void retrySelected(); Q_INVOKABLE void deleteSelected(bool files = false);
    Q_INVOKABLE void refresh(); Q_INVOKABLE void setBandwidthLimit(int kbps); Q_INVOKABLE void setSelectedPriority(int priority);
    void setSelectedId(const QString &id);

signals:
    void connectionChanged(); void lastErrorChanged(); void selectedChanged(); void speedSamplesChanged(); void notice(QString message, bool error);

private:
    CoreAdapter *m_adapter;
    QString m_selectedId;
    QVariantList m_speedSamples;
    void sampleSelectedSpeed();
};
