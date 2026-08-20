#pragma once

#include <QObject>
#include <QProcess>
#include <QUrl>

class BundledCoreLauncher final : public QObject {
    Q_OBJECT

public:
    BundledCoreLauncher(QString endpoint, QString token, bool externalConnectionRequested, QObject *parent = nullptr);
    ~BundledCoreLauncher() override;

    QString endpoint() const;
    QString token() const;
    bool managesBundledCore() const { return m_shouldLaunch; }
    void start();
    void stop();

signals:
    void coreStarted();
    void coreLaunchFailed(QString message);
    void managedCoreExited(QString message);

private:
    static bool isPermittedLoopbackEndpoint(const QUrl &endpoint);
    static bool loopbackPortAvailable(quint16 port);
    static QString bundledCorePath();
    static QString newSessionToken();
    void reportStartFailure(const QString &reason);

    QUrl m_endpoint;
    QString m_token;
    QString m_corePath;
    QProcess m_process;
    bool m_shouldLaunch = false;
    bool m_stopping = false;
};
