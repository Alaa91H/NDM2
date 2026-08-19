#pragma once

#include "models/DownloadModel.h"
#include <QJsonObject>
#include <QNetworkAccessManager>
#include <QTimer>

class CoreAdapter final : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectionChanged)
    Q_PROPERTY(QString endpoint READ endpoint NOTIFY endpointChanged)
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    Q_PROPERTY(QVariantMap capabilities READ capabilities NOTIFY capabilitiesChanged)
    Q_PROPERTY(DownloadModel *downloads READ downloads CONSTANT)

public:
    explicit CoreAdapter(QString endpoint, QString token, QObject *parent = nullptr);
    bool connected() const { return m_connected; }
    QString endpoint() const { return m_endpoint.toString(); }
    QString lastError() const { return m_lastError; }
    QVariantMap capabilities() const { return m_capabilities; }
    DownloadModel *downloads() { return &m_downloads; }

    Q_INVOKABLE void refresh();
    Q_INVOKABLE void createDownload(const QVariantMap &payload);
    Q_INVOKABLE void pause(const QString &id);
    Q_INVOKABLE void resume(const QString &id);
    Q_INVOKABLE void cancel(const QString &id);
    Q_INVOKABLE void retry(const QString &id);
    Q_INVOKABLE void deleteDownload(const QString &id, bool deleteFiles = false);
    Q_INVOKABLE void setQueuePriority(const QString &id, int priority);
    Q_INVOKABLE void setBandwidthLimit(int kbps);
    Q_INVOKABLE void updateSchedulerRule(const QVariantMap &rule);
    Q_INVOKABLE void fetchCapabilities();

signals:
    void connectionChanged();
    void endpointChanged();
    void lastErrorChanged();
    void capabilitiesChanged();
    void operationSucceeded(QString action, QString id);
    void operationFailed(QString action, QString message);

private:
    QUrl endpointFor(const QString &path) const;
    QNetworkRequest requestFor(const QString &path) const;
    void send(const QString &action, const QString &path, const QByteArray &verb = "GET", const QJsonObject &body = {}, const QString &id = {});
    void setError(const QString &message);
    void setConnected(bool connected);
    void loadDownloads(const QByteArray &data);
    static bool safeLoopbackEndpoint(const QUrl &endpoint);

    QNetworkAccessManager m_network;
    QUrl m_endpoint;
    QString m_token;
    bool m_connected = false;
    QString m_lastError;
    QVariantMap m_capabilities;
    DownloadModel m_downloads;
    QTimer m_refreshTimer;
};
