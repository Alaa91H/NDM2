#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QVector>

struct DownloadRecord {
    QString id;
    QString name;
    QString url;
    QString fileType;
    QString status;
    qint64 sizeBytes = 0;
    qint64 downloadedBytes = 0;
    double speedBytesPerSec = 0.0;
    qint64 timeLeftSeconds = 0;
    qint64 elapsedSeconds = 0;
    QDateTime dateAdded;
    QDateTime completedAt;
    QString category;
    QString queueId;
    int connections = 0;
    bool resumable = false;
    QString savePath;
    QString description;
    QString engine;
    QString engineStatus;
    QString errorMessage;
    int retries = 0;
    int totalSegments = 0;
    int completedSegments = 0;
};

class DownloadModel final : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)

public:
    enum Role {
        IdRole = Qt::UserRole + 1, NameRole, UrlRole, FileTypeRole, StatusRole,
        SizeBytesRole, DownloadedBytesRole, SpeedRole, EtaRole, ElapsedRole,
        DateAddedRole, CompletedAtRole, CategoryRole, QueueIdRole, ConnectionsRole,
        ResumableRole, SavePathRole, DescriptionRole, EngineRole, EngineStatusRole,
        ErrorRole, RetriesRole, TotalSegmentsRole, CompletedSegmentsRole, ProgressRole
    };
    Q_ENUM(Role)

    explicit DownloadModel(QObject *parent = nullptr);
    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override;
    QHash<int, QByteArray> roleNames() const override;

    void replace(QVector<DownloadRecord> records);
    Q_INVOKABLE QVariantMap get(const QString &id) const;
    Q_INVOKABLE int countForStatus(const QString &status) const;

signals:
    void countChanged();

private:
    QVector<DownloadRecord> m_records;
};
