#include "DownloadFilterProxyModel.h"

#include <QDateTime>

DownloadFilterProxyModel::DownloadFilterProxyModel(QObject *parent) : QSortFilterProxyModel(parent) {
    setDynamicSortFilter(true);
    setSortRole(DownloadModel::DateAddedRole);
    sort(0, Qt::DescendingOrder);
}

void DownloadFilterProxyModel::setSearchText(const QString &value) { const auto normalized = value.trimmed(); if (m_searchText == normalized) return; m_searchText = normalized; invalidateFilter(); emit filtersChanged(); }
void DownloadFilterProxyModel::setStatusFilter(const QString &value) { if (m_statusFilter == value) return; m_statusFilter = value; invalidateFilter(); emit filtersChanged(); }
void DownloadFilterProxyModel::setCategoryFilter(const QString &value) { if (m_categoryFilter == value) return; m_categoryFilter = value; invalidateFilter(); emit filtersChanged(); }
void DownloadFilterProxyModel::setQueueFilter(const QString &value) { if (m_queueFilter == value) return; m_queueFilter = value; invalidateFilter(); emit filtersChanged(); }
void DownloadFilterProxyModel::setFilters(const QString &search, const QString &status, const QString &category, const QString &queue) { m_searchText = search.trimmed(); m_statusFilter = status; m_categoryFilter = category; m_queueFilter = queue; invalidateFilter(); emit filtersChanged(); }

int DownloadFilterProxyModel::roleForField() const {
    if (m_sortField == "name") return DownloadModel::NameRole;
    if (m_sortField == "status") return DownloadModel::StatusRole;
    if (m_sortField == "size") return DownloadModel::SizeBytesRole;
    if (m_sortField == "progress") return DownloadModel::ProgressRole;
    if (m_sortField == "speed") return DownloadModel::SpeedRole;
    if (m_sortField == "eta") return DownloadModel::EtaRole;
    if (m_sortField == "category") return DownloadModel::CategoryRole;
    if (m_sortField == "queue") return DownloadModel::QueueIdRole;
    return DownloadModel::DateAddedRole;
}

void DownloadFilterProxyModel::sortBy(const QString &field, bool descending) {
    const auto allowed = QStringList{"name", "status", "size", "progress", "speed", "eta", "category", "queue", "date"};
    const auto normalized = allowed.contains(field) ? field : QStringLiteral("date");
    if (m_sortField == normalized && m_sortDescending == descending) return;
    m_sortField = normalized; m_sortDescending = descending; setSortRole(roleForField()); sort(0, descending ? Qt::DescendingOrder : Qt::AscendingOrder); emit sortChanged();
}

bool DownloadFilterProxyModel::filterAcceptsRow(int row, const QModelIndex &parent) const {
    const auto *source = sourceModel(); if (!source) return false;
    const auto index = source->index(row, 0, parent);
    const auto name = source->data(index, DownloadModel::NameRole).toString();
    const auto url = source->data(index, DownloadModel::UrlRole).toString();
    const auto status = source->data(index, DownloadModel::StatusRole).toString();
    const auto category = source->data(index, DownloadModel::CategoryRole).toString();
    const auto queue = source->data(index, DownloadModel::QueueIdRole).toString();
    if (!m_statusFilter.isEmpty() && status != m_statusFilter) return false;
    if (!m_categoryFilter.isEmpty() && category != m_categoryFilter) return false;
    if (!m_queueFilter.isEmpty() && queue != m_queueFilter) return false;
    if (m_searchText.isEmpty()) return true;
    return name.contains(m_searchText, Qt::CaseInsensitive) || url.contains(m_searchText, Qt::CaseInsensitive) || category.contains(m_searchText, Qt::CaseInsensitive) || queue.contains(m_searchText, Qt::CaseInsensitive);
}

bool DownloadFilterProxyModel::lessThan(const QModelIndex &left, const QModelIndex &right) const {
    const auto l = sourceModel()->data(left, roleForField()); const auto r = sourceModel()->data(right, roleForField());
    if (roleForField() == DownloadModel::NameRole || roleForField() == DownloadModel::StatusRole || roleForField() == DownloadModel::CategoryRole || roleForField() == DownloadModel::QueueIdRole) return QString::localeAwareCompare(l.toString(), r.toString()) < 0;
    if (roleForField() == DownloadModel::DateAddedRole) return l.toDateTime() < r.toDateTime();
    return l.toDouble() < r.toDouble();
}
