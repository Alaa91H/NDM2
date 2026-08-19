#pragma once

#include "models/DownloadModel.h"
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QPointer>
#include <QTimer>

class CoreAdapter final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(QString endpoint READ endpoint NOTIFY endpointChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantMap capabilities READ capabilities NOTIFY capabilitiesChanged)
    Q_PROPERTY(DownloadModel *downloads READ downloads CONSTANT)
    Q_PROPERTY(QVariantList queueEntries READ queueEntries NOTIFY queueChanged)
    Q_PROPERTY(QVariantMap queueSummary READ queueSummary NOTIFY queueChanged)
    Q_PROPERTY(QVariantMap bandwidth READ bandwidth NOTIFY bandwidthChanged)
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(QString activeProfile READ activeProfile NOTIFY profilesChanged)
    Q_PROPERTY(QVariantMap statistics READ statistics NOTIFY statisticsChanged)
    Q_PROPERTY(QVariantList logs READ logs NOTIFY logsChanged)

public:
    explicit CoreAdapter(QString endpoint, QString token, QObject *parent = nullptr);
    bool connected() const { return m_connected; }
    QString endpoint() const { return m_endpoint.toString(); }
    QString lastError() const { return m_lastError; }
    QVariantMap capabilities() const { return m_capabilities; }
    DownloadModel *downloads() { return &m_downloads; }
    QVariantList queueEntries() const { return m_queueEntries; }
    QVariantMap queueSummary() const { return m_queueSummary; }
    QVariantMap bandwidth() const { return m_bandwidth; }
    QVariantList profiles() const { return m_profiles; }
    QString activeProfile() const { return m_activeProfile; }
    QVariantMap statistics() const { return m_statistics; }
    QVariantList logs() const { return m_logs; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void refreshAll();
    Q_INVOKABLE void createDownload(const QVariantMap &payload);
    Q_INVOKABLE void updateDownload(const QString &id, const QVariantMap &patch);
    Q_INVOKABLE void pause(const QString &id);
    Q_INVOKABLE void pauseAll();
    Q_INVOKABLE void resumeAll();
    Q_INVOKABLE void resume(const QString &id);
    Q_INVOKABLE void cancel(const QString &id);
    Q_INVOKABLE void retry(const QString &id);
    Q_INVOKABLE void deleteDownload(const QString &id, bool deleteFiles = false);
    Q_INVOKABLE void setQueuePriority(const QString &id, int priority);
    Q_INVOKABLE void setBandwidthLimit(int kbps);
    Q_INVOKABLE void updateSchedulerRule(const QVariantMap &rule);
    Q_INVOKABLE void fetchCapabilities();
    Q_INVOKABLE void refreshQueue();
    Q_INVOKABLE void refreshBandwidth();
    Q_INVOKABLE void refreshProfiles();
    Q_INVOKABLE void setActiveProfile(const QString &profileId);
    Q_INVOKABLE void refreshStatistics();
    Q_INVOKABLE void refreshLogs(int limit = 100);

signals:
    void connectionChanged();
    void endpointChanged();
    void lastErrorChanged();
    void capabilitiesChanged();
    void queueChanged();
    void bandwidthChanged();
    void profilesChanged();
    void statisticsChanged();
    void logsChanged();
    void operationSucceeded(QString action, QString id);
    void operationFailed(QString action, QString message);

private:
    QUrl endpointFor(const QString &path) const;
    QNetworkRequest requestFor(const QString &path) const;
    void send(const QString &action, const QString &path, const QByteArray &verb = "GET", const QJsonObject &body = {}, const QString &id = {});
    void setError(const QString &message);
    void setConnected(bool connected);
    void loadDownloads(const QByteArray &data);
    void loadDownloadDelta(const QByteArray &data);
    void startEventStream();
    void consumeEventStream();
    void scheduleEventReconnect();
    DownloadRecord parseDownload(const QJsonObject &item) const;
    static bool safeLoopbackEndpoint(const QUrl &endpoint);

    QNetworkAccessManager m_network;
    QUrl m_endpoint;
    QString m_token;
    bool m_connected = false;
    QString m_lastError;
    QVariantMap m_capabilities;
    DownloadModel m_downloads;
    QVariantList m_queueEntries;
    QVariantMap m_queueSummary;
    QVariantMap m_bandwidth;
    QVariantList m_profiles;
    QString m_activeProfile;
    QVariantMap m_statistics;
    QVariantList m_logs;
    QTimer m_refreshTimer;
    QTimer m_eventReconnectTimer;
    QPointer<QNetworkReply> m_eventReply;
    QByteArray m_eventBuffer;
};
