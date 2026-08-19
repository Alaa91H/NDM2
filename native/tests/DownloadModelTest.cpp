#include "models/DownloadFilterProxyModel.h"
#include "models/DownloadModel.h"
#include <QtTest>

namespace {
DownloadRecord record(const QString &id, const QString &name, const QString &status, qint64 size, qint64 downloaded, double speed, const QString &category, const QString &queue) {
    DownloadRecord value;
    value.id = id; value.name = name; value.status = status; value.sizeBytes = size; value.downloadedBytes = downloaded; value.speedBytesPerSec = speed; value.category = category; value.queueId = queue;
    value.dateAdded = QDateTime::fromString("2026-08-19T12:00:00Z", Qt::ISODate);
    return value;
}
}

class DownloadModelTest final : public QObject {
    Q_OBJECT
private slots:
    void filtersByNameUrlCategoryAndState();
    void sortsBySpeedAndMaintainsIncrementalDelta();
};

void DownloadModelTest::filtersByNameUrlCategoryAndState() {
    DownloadModel model;
    model.replace({
        record("a", "archive.zip", "completed", 100, 100, 0, "compressed", "main"),
        record("b", "movie.mp4", "downloading", 200, 80, 120, "video", "main"),
        record("c", "paper.pdf", "error", 300, 0, 0, "document", "secondary")
    });
    DownloadFilterProxyModel proxy;
    proxy.setSourceModel(&model);
    QCOMPARE(proxy.rowCount(), 3);
    proxy.setFilters("movie", "downloading", "video", "main");
    QCOMPARE(proxy.rowCount(), 1);
    QCOMPARE(proxy.data(proxy.index(0, 0), DownloadModel::IdRole).toString(), QStringLiteral("b"));
    proxy.setFilters("", "", "document", "secondary");
    QCOMPARE(proxy.rowCount(), 1);
    QCOMPARE(proxy.data(proxy.index(0, 0), DownloadModel::NameRole).toString(), QStringLiteral("paper.pdf"));
}

void DownloadModelTest::sortsBySpeedAndMaintainsIncrementalDelta() {
    DownloadModel model;
    model.replace({
        record("a", "slow", "downloading", 100, 10, 10, "other", "main"),
        record("b", "fast", "downloading", 100, 20, 100, "other", "main")
    });
    DownloadFilterProxyModel proxy;
    proxy.setSourceModel(&model);
    proxy.sortBy("speed", true);
    QCOMPARE(proxy.data(proxy.index(0, 0), DownloadModel::IdRole).toString(), QStringLiteral("b"));
    model.applyDelta({record("a", "slow", "completed", 100, 100, 0, "other", "main")}, {"b"});
    QCOMPARE(model.rowCount(), 1);
    QCOMPARE(proxy.rowCount(), 1);
    QCOMPARE(proxy.data(proxy.index(0, 0), DownloadModel::StatusRole).toString(), QStringLiteral("completed"));
}

QTEST_MAIN(DownloadModelTest)
#include "DownloadModelTest.moc"
