#include "models/DownloadFilterProxyModel.h"
#include "models/DownloadModel.h"
#include "services/SettingsService.h"

#include <QSettings>
#include <QStandardPaths>
#include <QtTest>

namespace {
DownloadRecord record(const QString &id, const QString &name, const QString &status, qint64 size, qint64 downloaded, double speed, const QString &category, const QString &queue) {
    DownloadRecord value;
    value.id = id; value.name = name; value.status = status; value.sizeBytes = size; value.downloadedBytes = downloaded; value.speedBytesPerSec = speed; value.category = category; value.queueId = queue;
    value.dateAdded = QDateTime::fromString("2026-08-19T12:00:00Z", Qt::ISODate);
    return value;
}

void clearSettings() {
    QSettings settings("NOVA", "NDM2");
    settings.clear();
    settings.sync();
}
}

class DownloadModelTest final : public QObject {
    Q_OBJECT
private slots:
    void initTestCase();
    void cleanup();
    void filtersByNameUrlCategoryAndState();
    void sortsBySpeedAndMaintainsIncrementalDelta();
    void settingsPersistAndNormalizeSafeValues();
};

void DownloadModelTest::initTestCase() {
    QStandardPaths::setTestModeEnabled(true);
    clearSettings();
}

void DownloadModelTest::cleanup() {
    clearSettings();
}

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

void DownloadModelTest::settingsPersistAndNormalizeSafeValues() {
    SettingsService initial;
    QCOMPARE(initial.theme(), QStringLiteral("system"));
    QCOMPARE(initial.density(), QStringLiteral("comfortable"));

    initial.setTheme("dark");
    initial.setDensity("compact");
    initial.setLanguage("ar");
    initial.setNotificationsEnabled(false);

    SettingsService restored;
    QCOMPARE(restored.theme(), QStringLiteral("dark"));
    QCOMPARE(restored.density(), QStringLiteral("compact"));
    QCOMPARE(restored.language(), QStringLiteral("ar"));
    QVERIFY(restored.rightToLeft());
    QVERIFY(restored.dark());
    QVERIFY(!restored.notificationsEnabled());

    restored.setTheme("unsupported-theme");
    restored.setDensity("spacious");
    restored.setLanguage("@@");

    SettingsService normalized;
    QCOMPARE(normalized.theme(), QStringLiteral("system"));
    QCOMPARE(normalized.density(), QStringLiteral("comfortable"));
    QCOMPARE(normalized.language(), QStringLiteral("en"));
    QVERIFY(!normalized.rightToLeft());
}

QTEST_MAIN(DownloadModelTest)
#include "DownloadModelTest.moc"
