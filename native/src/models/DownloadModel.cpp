#include "DownloadModel.h"

#include <QVariantMap>

DownloadModel::DownloadModel(QObject *parent) : QAbstractListModel(parent) {}
int DownloadModel::rowCount(const QModelIndex &parent) const { return parent.isValid() ? 0 : m_records.size(); }

int DownloadModel::indexOf(const QString &id) const {
    for (int i = 0; i < m_records.size(); ++i) if (m_records.at(i).id == id) return i;
    return -1;
}

QVariant DownloadModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_records.size()) return {};
    const auto &d = m_records.at(index.row());
    switch (role) {
    case IdRole: return d.id; case NameRole: return d.name; case UrlRole: return d.url;
    case FileTypeRole: return d.fileType; case StatusRole: return d.status;
    case SizeBytesRole: return d.sizeBytes; case DownloadedBytesRole: return d.downloadedBytes;
    case SpeedRole: return d.speedBytesPerSec; case EtaRole: return d.timeLeftSeconds;
    case ElapsedRole: return d.elapsedSeconds; case DateAddedRole: return d.dateAdded;
    case CompletedAtRole: return d.completedAt; case CategoryRole: return d.category;
    case QueueIdRole: return d.queueId; case ConnectionsRole: return d.connections;
    case ResumableRole: return d.resumable; case SavePathRole: return d.savePath;
    case DescriptionRole: return d.description; case EngineRole: return d.engine;
    case EngineStatusRole: return d.engineStatus; case ErrorRole: return d.errorMessage;
    case RetriesRole: return d.retries; case TotalSegmentsRole: return d.totalSegments;
    case CompletedSegmentsRole: return d.completedSegments;
    case ProgressRole: return d.sizeBytes > 0 ? qBound(0.0, static_cast<double>(d.downloadedBytes) / static_cast<double>(d.sizeBytes), 1.0) : 0.0;
    default: return {};
    }
}

QHash<int, QByteArray> DownloadModel::roleNames() const {
    return {{IdRole, "downloadId"}, {NameRole, "name"}, {UrlRole, "url"}, {FileTypeRole, "fileType"},
        {StatusRole, "status"}, {SizeBytesRole, "sizeBytes"}, {DownloadedBytesRole, "downloadedBytes"},
        {SpeedRole, "speed"}, {EtaRole, "eta"}, {ElapsedRole, "elapsed"}, {DateAddedRole, "dateAdded"},
        {CompletedAtRole, "completedAt"}, {CategoryRole, "category"}, {QueueIdRole, "queueId"},
        {ConnectionsRole, "connections"}, {ResumableRole, "resumable"}, {SavePathRole, "savePath"},
        {DescriptionRole, "description"}, {EngineRole, "engine"}, {EngineStatusRole, "engineStatus"},
        {ErrorRole, "errorMessage"}, {RetriesRole, "retries"}, {TotalSegmentsRole, "totalSegments"},
        {CompletedSegmentsRole, "completedSegments"}, {ProgressRole, "progress"}};
}

void DownloadModel::replace(QVector<DownloadRecord> records) {
    beginResetModel();
    m_records = std::move(records);
    endResetModel();
    emit countChanged();
}

void DownloadModel::applyDelta(QVector<DownloadRecord> changed, const QStringList &removed) {
    bool countChangedNeeded = false;
    for (int row = m_records.size() - 1; row >= 0; --row) {
        if (!removed.contains(m_records.at(row).id)) continue;
        beginRemoveRows({}, row, row);
        m_records.removeAt(row);
        endRemoveRows();
        countChangedNeeded = true;
    }
    for (auto &record : changed) {
        const int row = indexOf(record.id);
        if (row >= 0) {
            m_records[row] = std::move(record);
            emit dataChanged(index(row, 0), index(row, 0));
            continue;
        }
        const int inserted = m_records.size();
        beginInsertRows({}, inserted, inserted);
        m_records.push_back(std::move(record));
        endInsertRows();
        countChangedNeeded = true;
    }
    if (countChangedNeeded) emit countChanged();
}

QVariantMap DownloadModel::get(const QString &id) const {
    const int row = indexOf(id);
    if (row < 0) return {};
    const auto &d = m_records.at(row);
    return {{"id", d.id}, {"name", d.name}, {"url", d.url}, {"fileType", d.fileType}, {"status", d.status},
        {"sizeBytes", d.sizeBytes}, {"downloadedBytes", d.downloadedBytes}, {"speed", d.speedBytesPerSec},
        {"eta", d.timeLeftSeconds}, {"elapsed", d.elapsedSeconds}, {"connections", d.connections}, {"savePath", d.savePath},
        {"category", d.category}, {"queueId", d.queueId}, {"engine", d.engine}, {"engineStatus", d.engineStatus},
        {"errorMessage", d.errorMessage}, {"description", d.description}, {"resumable", d.resumable},
        {"progress", d.sizeBytes > 0 ? static_cast<double>(d.downloadedBytes) / static_cast<double>(d.sizeBytes) : 0.0},
        {"totalSegments", d.totalSegments}, {"completedSegments", d.completedSegments}, {"retries", d.retries}};
}

int DownloadModel::countForStatus(const QString &status) const {
    int count = 0;
    for (const auto &d : m_records) if (d.status == status) ++count;
    return count;
}

QStringList DownloadModel::idsForStatuses(const QStringList &statuses) const {
    QStringList ids;
    for (const auto &record : m_records) if (statuses.contains(record.status)) ids.push_back(record.id);
    return ids;
}
