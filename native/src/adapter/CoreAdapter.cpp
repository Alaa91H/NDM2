#include "CoreAdapter.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>

namespace {
qint64 integer(const QJsonObject &object, const char *key) { return object.value(QLatin1String(key)).toVariant().toLongLong(); }
double number(const QJsonObject &object, const char *key) { return object.value(QLatin1String(key)).toDouble(); }
QString string(const QJsonObject &object, const char *key) { return object.value(QLatin1String(key)).toString(); }
QVariantMap map(const QJsonObject &object) { return object.toVariantMap(); }
}

CoreAdapter::CoreAdapter(QString endpoint, QString token, QObject *parent)
    : QObject(parent), m_endpoint(QUrl::fromUserInput(endpoint)), m_token(std::move(token)), m_downloads(this) {
    if (!safeLoopbackEndpoint(m_endpoint)) {
        m_endpoint = QUrl();
        setError(tr("The configured daemon endpoint is not a permitted loopback address."));
        return;
    }
    m_endpoint.setPath(QString());
    m_refreshTimer.setInterval(1200);
    m_refreshTimer.setSingleShot(false);
    connect(&m_refreshTimer, &QTimer::timeout, this, &CoreAdapter::refresh);
    m_refreshTimer.start();
    refresh();
    fetchCapabilities();
}

bool CoreAdapter::safeLoopbackEndpoint(const QUrl &endpoint) {
    if (!endpoint.isValid() || (endpoint.scheme() != "http" && endpoint.scheme() != "https")) return false;
    const auto host = endpoint.host().toLower();
    return host == "127.0.0.1" || host == "localhost" || host == "::1";
}

QUrl CoreAdapter::endpointFor(const QString &path) const {
    if (!m_endpoint.isValid()) return {};
    QUrl url(m_endpoint);
    url.setPath(path);
    return url;
}

QNetworkRequest CoreAdapter::requestFor(const QString &path) const {
    QNetworkRequest request(endpointFor(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("Accept", "application/json");
    if (!m_token.isEmpty()) request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
    return request;
}

void CoreAdapter::setConnected(bool connected) {
    if (m_connected == connected) return;
    m_connected = connected;
    emit connectionChanged();
}

void CoreAdapter::setError(const QString &message) {
    if (m_lastError == message) return;
    m_lastError = message;
    emit lastErrorChanged();
}

void CoreAdapter::refresh() {
    if (!m_endpoint.isValid()) return;
    auto *reply = m_network.get(requestFor("/api/downloads"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto body = reply->readAll();
        const auto error = reply->error();
        reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) {
            setConnected(false);
            setError(tr("Unable to refresh downloads: %1").arg(status > 0 ? QString::number(status) : tr("daemon unavailable")));
            return;
        }
        loadDownloads(body);
        setConnected(true);
        setError({});
    });
}

void CoreAdapter::loadDownloads(const QByteArray &data) {
    const auto document = QJsonDocument::fromJson(data);
    if (!document.isArray()) { setError(tr("The daemon returned an invalid download collection.")); return; }
    QVector<DownloadRecord> records;
    const auto items = document.array();
    records.reserve(items.size());
    for (const auto &value : items) {
        const auto item = value.toObject();
        DownloadRecord record;
        record.id = string(item, "id"); record.name = string(item, "name"); record.url = string(item, "url");
        record.fileType = string(item, "fileType"); record.status = string(item, "status");
        record.sizeBytes = integer(item, "sizeBytes"); record.downloadedBytes = integer(item, "downloadedBytes");
        record.speedBytesPerSec = number(item, "speedBytesPerSec"); record.timeLeftSeconds = integer(item, "timeLeftSeconds");
        record.elapsedSeconds = integer(item, "elapsedSeconds"); record.dateAdded = QDateTime::fromString(string(item, "dateAdded"), Qt::ISODate);
        record.completedAt = QDateTime::fromString(string(item, "completedAt"), Qt::ISODate); record.category = string(item, "category");
        record.queueId = string(item, "queueId"); record.connections = int(integer(item, "connections"));
        record.resumable = item.value("resumable").toBool(); record.savePath = string(item, "savePath");
        record.description = string(item, "description"); record.engine = string(item, "engine");
        record.engineStatus = string(item, "engineStatus"); record.errorMessage = string(item, "errorMessage");
        record.retries = int(integer(item, "retries"));
        const auto segments = item.value("segments").toArray(); record.totalSegments = segments.size();
        for (const auto &segment : segments) if (segment.toObject().value("progress").toDouble() >= 1.0) ++record.completedSegments;
        records.push_back(std::move(record));
    }
    m_downloads.replace(std::move(records));
}

void CoreAdapter::send(const QString &action, const QString &path, const QByteArray &verb, const QJsonObject &body, const QString &id) {
    if (!m_endpoint.isValid()) { emit operationFailed(action, m_lastError); return; }
    QNetworkReply *reply = nullptr;
    const auto request = requestFor(path);
    const auto payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    if (verb == "POST") reply = m_network.post(request, payload);
    else if (verb == "PATCH") reply = m_network.sendCustomRequest(request, "PATCH", payload);
    else if (verb == "DELETE") reply = m_network.deleteResource(request);
    else reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, action, id] {
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto response = reply->readAll();
        const auto error = reply->error();
        reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) {
            QString message = tr("The core rejected the operation.");
            const auto doc = QJsonDocument::fromJson(response);
            if (doc.isObject()) message = doc.object().value("error").toString(message);
            setError(message); emit operationFailed(action, message); return;
        }
        emit operationSucceeded(action, id); refresh();
    });
}

void CoreAdapter::createDownload(const QVariantMap &payload) { send("create", "/api/downloads", "POST", QJsonObject::fromVariantMap(payload)); }
void CoreAdapter::pause(const QString &id) { send("pause", "/api/downloads/" + QUrl::toPercentEncoding(id) + "/pause", "POST", {}, id); }
void CoreAdapter::resume(const QString &id) { send("resume", "/api/downloads/" + QUrl::toPercentEncoding(id) + "/resume", "POST", {}, id); }
void CoreAdapter::cancel(const QString &id) { send("cancel", "/api/downloads/" + QUrl::toPercentEncoding(id), "DELETE", {}, id); }
void CoreAdapter::retry(const QString &id) { send("retry", "/api/downloads/" + QUrl::toPercentEncoding(id) + "/redownload", "POST", {}, id); }
void CoreAdapter::deleteDownload(const QString &id, bool deleteFiles) { send("delete", "/api/downloads/" + QUrl::toPercentEncoding(id) + (deleteFiles ? "?deleteFiles=true" : ""), "DELETE", {}, id); }
void CoreAdapter::setQueuePriority(const QString &id, int priority) { send("queue-priority", "/api/engine/queue", "POST", {{"task_id", id}, {"priority", priority}}, id); }
void CoreAdapter::setBandwidthLimit(int kbps) { send("bandwidth", "/api/engine/bandwidth", "POST", {{"global_limit_kbps", kbps}}); }
void CoreAdapter::updateSchedulerRule(const QVariantMap &rule) { send("scheduler", "/api/engine/scheduler/update", "POST", {{"rule", QJsonObject::fromVariantMap(rule)}}); }

void CoreAdapter::fetchCapabilities() {
    if (!m_endpoint.isValid()) return;
    auto *reply = m_network.get(requestFor("/api/engines/capabilities"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto data = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) return;
        const auto doc = QJsonDocument::fromJson(data);
        if (!doc.isObject()) return;
        const auto values = map(doc.object());
        if (m_capabilities == values) return;
        m_capabilities = values; emit capabilitiesChanged();
    });
}
