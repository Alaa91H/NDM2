#include "CoreAdapter.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QNetworkReply>
#include <QUrlQuery>

namespace {
qint64 integer(const QJsonObject &object, const char *key) { return object.value(QLatin1String(key)).toVariant().toLongLong(); }
double number(const QJsonObject &object, const char *key) { return object.value(QLatin1String(key)).toDouble(); }
QString string(const QJsonObject &object, const char *key) { return object.value(QLatin1String(key)).toString(); }
QVariantMap map(const QJsonObject &object) { return object.toVariantMap(); }
QVariantList list(const QJsonArray &array) { return array.toVariantList(); }
}

CoreAdapter::CoreAdapter(QString endpoint, QString token, QObject *parent)
    : QObject(parent), m_endpoint(QUrl::fromUserInput(endpoint)), m_token(std::move(token)), m_downloads(this) {
    if (!safeLoopbackEndpoint(m_endpoint)) {
        m_endpoint = QUrl();
        setError(tr("The configured daemon endpoint is not a permitted loopback address."));
        return;
    }
    m_endpoint.setPath(QString());
    m_refreshTimer.setInterval(10000);
    m_refreshTimer.setSingleShot(false);
    connect(&m_refreshTimer, &QTimer::timeout, this, &CoreAdapter::refreshAll);
    connect(&m_eventReconnectTimer, &QTimer::timeout, this, &CoreAdapter::startEventStream);
    m_eventReconnectTimer.setSingleShot(true);
    m_refreshTimer.start();
    refreshAll();
    startEventStream();
}

bool CoreAdapter::safeLoopbackEndpoint(const QUrl &endpoint) {
    if (!endpoint.isValid() || (endpoint.scheme() != "http" && endpoint.scheme() != "https")) return false;
    const auto host = endpoint.host().toLower();
    return host == "127.0.0.1" || host == "localhost" || host == "::1";
}

QUrl CoreAdapter::endpointFor(const QString &path) const {
    if (!m_endpoint.isValid()) return {};
    const auto queryStart = path.indexOf('?');
    QUrl url(m_endpoint);
    url.setPath(queryStart < 0 ? path : path.left(queryStart));
    if (queryStart >= 0) url.setQuery(path.mid(queryStart + 1));
    return url;
}

QNetworkRequest CoreAdapter::requestFor(const QString &path) const {
    QNetworkRequest request(endpointFor(path));
    request.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    request.setRawHeader("Accept", "application/json");
    if (!m_token.isEmpty()) request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
    return request;
}

void CoreAdapter::setConnected(bool connected) { if (m_connected == connected) return; m_connected = connected; emit connectionChanged(); }
void CoreAdapter::setError(const QString &message) { if (m_lastError == message) return; m_lastError = message; emit lastErrorChanged(); }

DownloadRecord CoreAdapter::parseDownload(const QJsonObject &item) const {
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
    return record;
}

void CoreAdapter::refresh() {
    if (!m_endpoint.isValid()) return;
    auto *reply = m_network.get(requestFor("/api/downloads"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        const auto body = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) {
            setConnected(false); setError(tr("Unable to refresh downloads: %1").arg(status > 0 ? QString::number(status) : tr("daemon unavailable"))); return;
        }
        loadDownloads(body); setConnected(true); setError({});
    });
}

void CoreAdapter::refreshAll() { refresh(); refreshQueue(); refreshBandwidth(); refreshProfiles(); refreshStatistics(); refreshLogs(100); }

void CoreAdapter::loadDownloads(const QByteArray &data) {
    const auto document = QJsonDocument::fromJson(data);
    if (!document.isArray()) { setError(tr("The daemon returned an invalid download collection.")); return; }
    QVector<DownloadRecord> records; const auto items = document.array(); records.reserve(items.size());
    for (const auto &value : items) records.push_back(parseDownload(value.toObject()));
    m_downloads.replace(std::move(records));
}

void CoreAdapter::loadDownloadDelta(const QByteArray &data) {
    const auto document = QJsonDocument::fromJson(data);
    if (!document.isObject()) return;
    const auto delta = document.object(); QVector<DownloadRecord> changed;
    const auto changes = delta.value("changed").toArray(); changed.reserve(changes.size());
    for (const auto &value : changes) changed.push_back(parseDownload(value.toObject()));
    QStringList removed; for (const auto &value : delta.value("removed").toArray()) removed.push_back(value.toString());
    m_downloads.applyDelta(std::move(changed), removed);
}

void CoreAdapter::startEventStream() {
    if (!m_endpoint.isValid() || m_eventReply) return;
    QUrl url = endpointFor("/api/downloads/events");
    QUrlQuery query(url); if (!m_token.isEmpty()) query.addQueryItem("token", m_token); url.setQuery(query);
    QNetworkRequest request(url); request.setRawHeader("Accept", "text/event-stream");
    if (!m_token.isEmpty()) request.setRawHeader("Authorization", "Bearer " + m_token.toUtf8());
    auto *reply = m_network.get(request); m_eventReply = reply;
    connect(reply, &QNetworkReply::readyRead, this, [this, reply] { if (m_eventReply == reply) { m_eventBuffer.append(reply->readAll()); consumeEventStream(); } });
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        if (m_eventReply != reply) { reply->deleteLater(); return; }
        m_eventBuffer.append(reply->readAll()); consumeEventStream();
        const auto error = reply->error(); m_eventReply = nullptr; reply->deleteLater();
        if (error != QNetworkReply::NoError) setError(tr("Live update stream reconnecting."));
        scheduleEventReconnect();
    });
}

void CoreAdapter::consumeEventStream() {
    m_eventBuffer.replace("\r\n", "\n");
    while (true) {
        const auto separator = m_eventBuffer.indexOf("\n\n");
        if (separator < 0) return;
        const auto block = m_eventBuffer.left(separator); m_eventBuffer.remove(0, separator + 2);
        QByteArray event; QList<QByteArray> dataParts;
        for (const auto &line : block.split('\n')) {
            if (line.startsWith("event:")) event = line.mid(6).trimmed();
            else if (line.startsWith("data:")) dataParts.push_back(line.mid(5).trimmed());
        }
        const auto data = dataParts.join("\n");
        if (event == "downloads") { loadDownloads(data); setConnected(true); setError({}); }
        else if (event == "downloads-delta") { loadDownloadDelta(data); setConnected(true); setError({}); }
    }
}

void CoreAdapter::scheduleEventReconnect() { if (!m_eventReconnectTimer.isActive()) m_eventReconnectTimer.start(1200); }

void CoreAdapter::send(const QString &action, const QString &path, const QByteArray &verb, const QJsonObject &body, const QString &id) {
    if (!m_endpoint.isValid()) { emit operationFailed(action, m_lastError); return; }
    QNetworkReply *reply = nullptr; const auto request = requestFor(path); const auto payload = QJsonDocument(body).toJson(QJsonDocument::Compact);
    if (verb == "POST") reply = m_network.post(request, payload);
    else if (verb == "PATCH") reply = m_network.sendCustomRequest(request, "PATCH", payload);
    else if (verb == "DELETE") reply = m_network.deleteResource(request);
    else reply = m_network.get(request);
    connect(reply, &QNetworkReply::finished, this, [this, reply, action, id] {
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); const auto response = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) {
            QString message = tr("The core rejected the operation."); const auto doc = QJsonDocument::fromJson(response);
            if (doc.isObject()) message = doc.object().value("error").toString(message); setError(message); emit operationFailed(action, message); return;
        }
        emit operationSucceeded(action, id); refreshAll();
    });
}

void CoreAdapter::createDownload(const QVariantMap &payload) { send("create", "/api/downloads", "POST", QJsonObject::fromVariantMap(payload)); }
void CoreAdapter::updateDownload(const QString &id, const QVariantMap &patch) { send("update", "/api/downloads/" + QUrl::toPercentEncoding(id), "PATCH", QJsonObject::fromVariantMap(patch), id); }
void CoreAdapter::pause(const QString &id) { send("pause", "/api/downloads/" + QUrl::toPercentEncoding(id) + "/pause", "POST", {}, id); }
void CoreAdapter::pauseAll() { for (const auto &id : m_downloads.idsForStatuses({"downloading", "pausing"})) pause(id); }
void CoreAdapter::resumeAll() { for (const auto &id : m_downloads.idsForStatuses({"paused", "queued"})) resume(id); }
void CoreAdapter::resume(const QString &id) { send("resume", "/api/downloads/" + QUrl::toPercentEncoding(id) + "/resume", "POST", {}, id); }
void CoreAdapter::cancel(const QString &id) { send("cancel", "/api/downloads/" + QUrl::toPercentEncoding(id), "DELETE", {}, id); }
void CoreAdapter::retry(const QString &id) { send("retry", "/api/downloads/" + QUrl::toPercentEncoding(id) + "/redownload", "POST", {}, id); }
void CoreAdapter::deleteDownload(const QString &id, bool deleteFiles) { send("delete", "/api/downloads/" + QUrl::toPercentEncoding(id) + (deleteFiles ? "?deleteFiles=true" : ""), "DELETE", {}, id); }
void CoreAdapter::setQueuePriority(const QString &id, int priority) { send("queue-priority", "/api/engine/queue", "POST", {{"task_id", id}, {"priority", priority}}, id); }
void CoreAdapter::setBandwidthLimit(int kbps) { send("bandwidth", "/api/engine/bandwidth", "POST", {{"global_limit_kbps", kbps}}); }
void CoreAdapter::updateSchedulerRule(const QVariantMap &rule) { send("scheduler", "/api/engine/scheduler/update", "POST", {{"rule", QJsonObject::fromVariantMap(rule)}}); }
void CoreAdapter::setActiveProfile(const QString &profileId) { send("profile", "/api/engine/profiles", "POST", {{"profile_id", profileId}}); }

void CoreAdapter::fetchCapabilities() {
    if (!m_endpoint.isValid()) return;
    auto *reply = m_network.get(requestFor("/api/engines/capabilities"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] {
        const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); const auto data = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) return;
        const auto doc = QJsonDocument::fromJson(data); if (!doc.isObject()) return;
        const auto values = map(doc.object()); if (m_capabilities == values) return; m_capabilities = values; emit capabilitiesChanged();
    });
}

void CoreAdapter::refreshQueue() {
    if (!m_endpoint.isValid()) return; auto *reply = m_network.get(requestFor("/api/engine/queue"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] { const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); const auto data = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) return; const auto doc = QJsonDocument::fromJson(data); if (!doc.isObject()) return;
        const auto object = doc.object(); const auto entries = list(object.value("entries").toArray()); QVariantMap summary = map(object); summary.remove("entries");
        if (m_queueEntries != entries || m_queueSummary != summary) { m_queueEntries = entries; m_queueSummary = summary; emit queueChanged(); }
    });
}

void CoreAdapter::refreshBandwidth() {
    if (!m_endpoint.isValid()) return; auto *reply = m_network.get(requestFor("/api/engine/bandwidth"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] { const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); const auto data = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) return; const auto doc = QJsonDocument::fromJson(data); if (!doc.isObject()) return;
        const auto values = map(doc.object()); if (m_bandwidth != values) { m_bandwidth = values; emit bandwidthChanged(); }
    });
}

void CoreAdapter::refreshProfiles() {
    if (!m_endpoint.isValid()) return; auto *reply = m_network.get(requestFor("/api/engine/profiles"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] { const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); const auto data = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) return; const auto doc = QJsonDocument::fromJson(data); if (!doc.isObject()) return;
        const auto object = doc.object(); const auto profiles = list(object.value("profiles").toArray()); const auto active = object.value("active_profile").toString();
        if (m_profiles != profiles || m_activeProfile != active) { m_profiles = profiles; m_activeProfile = active; emit profilesChanged(); }
    });
}

void CoreAdapter::refreshStatistics() {
    if (!m_endpoint.isValid()) return; auto *reply = m_network.get(requestFor("/api/stats"));
    connect(reply, &QNetworkReply::finished, this, [this, reply] { const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); const auto data = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) return; const auto doc = QJsonDocument::fromJson(data); if (!doc.isObject()) return;
        const auto values = map(doc.object()); if (m_statistics != values) { m_statistics = values; emit statisticsChanged(); }
    });
}

void CoreAdapter::refreshLogs(int limit) {
    if (!m_endpoint.isValid()) return; auto *reply = m_network.get(requestFor("/api/logs?limit=" + QString::number(qBound(1, limit, 1000))));
    connect(reply, &QNetworkReply::finished, this, [this, reply] { const auto status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt(); const auto data = reply->readAll(); const auto error = reply->error(); reply->deleteLater();
        if (error != QNetworkReply::NoError || status < 200 || status >= 300) return; const auto doc = QJsonDocument::fromJson(data); if (!doc.isObject()) return;
        const auto values = list(doc.object().value("entries").toArray()); if (m_logs != values) { m_logs = values; emit logsChanged(); }
    });
}
