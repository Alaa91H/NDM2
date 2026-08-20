#include "SettingsService.h"
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QLocale>
#include <QPalette>
#include <QStandardPaths>

namespace {
QString normalizedTheme(const QString &value) {
    const auto normalized = value.trimmed().toLower();
    return normalized == "dark" || normalized == "light" || normalized == "system" ? normalized : QStringLiteral("system");
}

QString normalizedDensity(const QString &value) {
    const auto normalized = value.trimmed().toLower();
    return normalized == "compact" || normalized == "comfortable" ? normalized : QStringLiteral("comfortable");
}

QString normalizedLanguage(const QString &value) {
    const auto code = value.trimmed().left(2).toLower();
    if (code.size() != 2 || !code.at(0).isLetter() || !code.at(1).isLetter()) return QStringLiteral("en");
    return code;
}

QString normalizedCategory(const QString &value) {
    const auto category = value.trimmed().toLower();
    return category == "video" || category == "audio" || category == "document" || category == "compressed" || category == "program" ? category : QStringLiteral("other");
}

QString categoryLabel(const QString &category) {
    const auto normalized = normalizedCategory(category);
    if (normalized == "video") return QStringLiteral("Video");
    if (normalized == "audio") return QStringLiteral("Audio");
    if (normalized == "document") return QStringLiteral("Documents");
    if (normalized == "compressed") return QStringLiteral("Archives");
    if (normalized == "program") return QStringLiteral("Programs");
    return QStringLiteral("Other");
}

QString portableCleanPath(const QString &value) {
    return QDir::cleanPath(QDir::fromNativeSeparators(value.trimmed()));
}
}

SettingsService::SettingsService(QObject *parent) : QObject(parent), m_settings("NOVA", "NDM2") {
    QGuiApplication::setLayoutDirection(rightToLeft() ? Qt::RightToLeft : Qt::LeftToRight);
}

QString SettingsService::theme() const { return normalizedTheme(m_settings.value("ui/theme", "system").toString()); }
QString SettingsService::language() const { return normalizedLanguage(m_settings.value("ui/language", QLocale::system().name().left(2)).toString()); }
QString SettingsService::density() const { return normalizedDensity(m_settings.value("ui/density", "comfortable").toString()); }
bool SettingsService::rightToLeft() const { const auto code = language(); return code == "ar" || code == "he" || code == "fa" || code == "ur"; }
bool SettingsService::dark() const { if (theme() == "dark") return true; if (theme() == "light") return false; return QGuiApplication::palette().color(QPalette::Window).lightness() < 128; }
bool SettingsService::notificationsEnabled() const { return m_settings.value("ui/notificationsEnabled", true).toBool(); }

QString SettingsService::defaultDownloadFolder() const {
    const auto configured = portableCleanPath(m_settings.value("downloads/defaultFolder").toString());
    if (!configured.isEmpty() && configured != ".") return configured;
    auto downloads = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
    if (downloads.isEmpty()) downloads = QDir::homePath();
    return QDir(downloads).filePath(QStringLiteral("NOVA"));
}

QString SettingsService::categoryDownloadFolder(const QString &category) const {
    const auto normalized = normalizedCategory(category);
    const auto configured = portableCleanPath(m_settings.value("downloads/categoryFolders/" + normalized).toString());
    if (!configured.isEmpty() && configured != ".") return configured;
    return QDir(defaultDownloadFolder()).filePath(categoryLabel(normalized));
}

void SettingsService::setNotificationsEnabled(bool value) { if (notificationsEnabled() == value) return; m_settings.setValue("ui/notificationsEnabled", value); m_settings.sync(); emit notificationsChanged(); }
void SettingsService::setTheme(const QString &value) { const auto normalized = normalizedTheme(value); if (theme() == normalized) return; m_settings.setValue("ui/theme", normalized); m_settings.sync(); emit themeChanged(); }
void SettingsService::setLanguage(const QString &value) { const auto normalized = normalizedLanguage(value); if (language() == normalized) return; m_settings.setValue("ui/language", normalized); m_settings.sync(); QGuiApplication::setLayoutDirection(rightToLeft() ? Qt::RightToLeft : Qt::LeftToRight); emit languageChanged(); }
void SettingsService::setDensity(const QString &value) { const auto normalized = normalizedDensity(value); if (density() == normalized) return; m_settings.setValue("ui/density", normalized); m_settings.sync(); emit densityChanged(); }

void SettingsService::setDefaultDownloadFolder(const QString &folder) {
    const auto normalized = portableCleanPath(folder);
    if (normalized.isEmpty() || normalized == ".") m_settings.remove("downloads/defaultFolder");
    else m_settings.setValue("downloads/defaultFolder", normalized);
    m_settings.sync();
    emit downloadPathsChanged();
}

void SettingsService::setCategoryDownloadFolder(const QString &category, const QString &folder) {
    const auto normalizedCategoryName = normalizedCategory(category);
    const auto normalizedFolder = portableCleanPath(folder);
    const auto key = QStringLiteral("downloads/categoryFolders/") + normalizedCategoryName;
    if (normalizedFolder.isEmpty() || normalizedFolder == ".") m_settings.remove(key);
    else m_settings.setValue(key, normalizedFolder);
    m_settings.sync();
    emit downloadPathsChanged();
}

QString SettingsService::suggestedDownloadFolder(const QString &category) const { return categoryDownloadFolder(category); }

QString SettingsService::suggestedDownloadPath(const QString &category, const QString &fileName) const {
    const auto cleanName = QFileInfo(fileName.trimmed()).fileName();
    return cleanName.isEmpty() || cleanName == "." ? categoryDownloadFolder(category) : QDir(categoryDownloadFolder(category)).filePath(cleanName);
}

QString SettingsService::composeDownloadPath(const QString &folder, const QString &fileName) const {
    const auto normalizedFolder = portableCleanPath(folder);
    const auto cleanName = QFileInfo(fileName.trimmed()).fileName();
    if (normalizedFolder.isEmpty() || normalizedFolder == ".") return cleanName;
    return cleanName.isEmpty() || cleanName == "." ? normalizedFolder : QDir(normalizedFolder).filePath(cleanName);
}
