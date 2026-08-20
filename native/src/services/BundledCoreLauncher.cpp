#include "BundledCoreLauncher.h"

#include <QCoreApplication>
#include <QDir>
#include <QFileInfo>
#include <QHostAddress>
#include <QTcpServer>
#include <QUuid>

namespace {
constexpr auto kDefaultCorePort = 3199;
}

BundledCoreLauncher::BundledCoreLauncher(QString endpoint, QString token, bool externalConnectionRequested, QObject *parent)
    : QObject(parent), m_endpoint(QUrl::fromUserInput(endpoint)), m_token(std::move(token)) {
    if (!isPermittedLoopbackEndpoint(m_endpoint)) return;

    // A caller that explicitly supplies an endpoint or a bearer token owns that
    // connection. NDM2 must never start a second Core or replace those values.
    if (externalConnectionRequested) return;

    const auto port = m_endpoint.port(kDefaultCorePort);
    if (port != kDefaultCorePort) return;

    m_corePath = bundledCorePath();
    if (m_corePath.isEmpty()) return;

    m_shouldLaunch = true;
    if (m_token.isEmpty()) m_token = newSessionToken();

    connect(&m_process, &QProcess::started, this, &BundledCoreLauncher::coreStarted);
    connect(&m_process, &QProcess::errorOccurred, this, [this](QProcess::ProcessError error) {
        if (m_stopping || error == QProcess::Crashed) return;
        reportStartFailure(m_process.errorString());
    });
    connect(&m_process, qOverload<int, QProcess::ExitStatus>(&QProcess::finished), this,
        [this](int exitCode, QProcess::ExitStatus exitStatus) {
            if (m_stopping) return;
            const QString reason = exitStatus == QProcess::CrashExit
                ? tr("The bundled NOVA Core crashed while starting.")
                : tr("The bundled NOVA Core stopped unexpectedly (exit code %1).").arg(exitCode);
            emit managedCoreExited(reason);
        });
}

BundledCoreLauncher::~BundledCoreLauncher() {
    stop();
}

QString BundledCoreLauncher::endpoint() const {
    return m_endpoint.toString();
}

QString BundledCoreLauncher::token() const {
    return m_token;
}

void BundledCoreLauncher::start() {
    if (!m_shouldLaunch || m_process.state() != QProcess::NotRunning) return;

    const auto port = m_endpoint.port(kDefaultCorePort);
    if (!loopbackPortAvailable(port)) {
        // A process already owns the normal port. Do not kill or interfere with
        // it; the authenticated adapter will report its real connection state.
        return;
    }

    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    environment.insert("NOVA_INTEGRATION_API_TOKEN", m_token);
    environment.insert("NOVA_DAEMON_PORT", QString::number(port));
    m_process.setProcessEnvironment(environment);
    m_process.setProgram(m_corePath);
    m_process.setArguments({QStringLiteral("--integration")});
    m_process.setProcessChannelMode(QProcess::MergedChannels);
    m_process.start();
}

void BundledCoreLauncher::stop() {
    m_stopping = true;
    if (m_process.state() == QProcess::NotRunning) return;
    m_process.terminate();
    if (!m_process.waitForFinished(2000)) {
        m_process.kill();
        m_process.waitForFinished(1000);
    }
}

bool BundledCoreLauncher::isPermittedLoopbackEndpoint(const QUrl &endpoint) {
    if (!endpoint.isValid() || endpoint.scheme() != QStringLiteral("http")) return false;
    const auto host = endpoint.host().toLower();
    return host == QStringLiteral("127.0.0.1") || host == QStringLiteral("localhost") || host == QStringLiteral("::1");
}

bool BundledCoreLauncher::loopbackPortAvailable(quint16 port) {
    QTcpServer probe;
    return probe.listen(QHostAddress::LocalHost, port);
}

QString BundledCoreLauncher::bundledCorePath() {
    QDir directory(QCoreApplication::applicationDirPath());
#ifdef Q_OS_WIN
    const auto candidate = directory.filePath(QStringLiteral("nova-core.exe"));
#else
    const auto candidate = directory.filePath(QStringLiteral("nova-core"));
#endif
    const QFileInfo file(candidate);
    return file.exists() && file.isFile() && file.isExecutable() ? file.absoluteFilePath() : QString();
}

QString BundledCoreLauncher::newSessionToken() {
    return QUuid::createUuid().toString(QUuid::WithoutBraces).remove('-')
        + QUuid::createUuid().toString(QUuid::WithoutBraces).remove('-');
}

void BundledCoreLauncher::reportStartFailure(const QString &reason) {
    emit coreLaunchFailed(tr("NDM2 could not start its bundled NOVA Core: %1").arg(reason));
}
