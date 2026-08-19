#pragma once

#include "DownloadModel.h"
#include <QSortFilterProxyModel>

class DownloadFilterProxyModel final : public QSortFilterProxyModel {
    Q_OBJECT
    Q_PROPERTY(QString searchText READ searchText WRITE setSearchText NOTIFY filtersChanged)
    Q_PROPERTY(QString statusFilter READ statusFilter WRITE setStatusFilter NOTIFY filtersChanged)
    Q_PROPERTY(QString categoryFilter READ categoryFilter WRITE setCategoryFilter NOTIFY filtersChanged)
    Q_PROPERTY(QString queueFilter READ queueFilter WRITE setQueueFilter NOTIFY filtersChanged)
    Q_PROPERTY(QString sortField READ sortField NOTIFY sortChanged)
    Q_PROPERTY(bool sortDescending READ sortDescending NOTIFY sortChanged)
public:
    explicit DownloadFilterProxyModel(QObject *parent = nullptr);
    QString searchText() const { return m_searchText; }
    QString statusFilter() const { return m_statusFilter; }
    QString categoryFilter() const { return m_categoryFilter; }
    QString queueFilter() const { return m_queueFilter; }
    QString sortField() const { return m_sortField; }
    bool sortDescending() const { return m_sortDescending; }

    void setSearchText(const QString &value);
    void setStatusFilter(const QString &value);
    void setCategoryFilter(const QString &value);
    void setQueueFilter(const QString &value);
    Q_INVOKABLE void setFilters(const QString &search, const QString &status, const QString &category, const QString &queue);
    Q_INVOKABLE void sortBy(const QString &field, bool descending = false);

signals:
    void filtersChanged();
    void sortChanged();

protected:
    bool filterAcceptsRow(int sourceRow, const QModelIndex &sourceParent) const override;
    bool lessThan(const QModelIndex &left, const QModelIndex &right) const override;

private:
    QString m_searchText;
    QString m_statusFilter;
    QString m_categoryFilter;
    QString m_queueFilter;
    QString m_sortField = "date";
    bool m_sortDescending = true;
    int roleForField() const;
};
