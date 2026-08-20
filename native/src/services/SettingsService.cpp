#include "SettingsService.h"
#include <QGuiApplication>
#include <QLocale>
#include <QPalette>

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
void SettingsService::setNotificationsEnabled(bool value) { if (notificationsEnabled() == value) return; m_settings.setValue("ui/notificationsEnabled", value); m_settings.sync(); emit notificationsChanged(); }
void SettingsService::setTheme(const QString &value) { const auto normalized = normalizedTheme(value); if (theme() == normalized) return; m_settings.setValue("ui/theme", normalized); m_settings.sync(); emit themeChanged(); }
void SettingsService::setLanguage(const QString &value) { const auto normalized = normalizedLanguage(value); if (language() == normalized) return; m_settings.setValue("ui/language", normalized); m_settings.sync(); QGuiApplication::setLayoutDirection(rightToLeft() ? Qt::RightToLeft : Qt::LeftToRight); emit languageChanged(); }
void SettingsService::setDensity(const QString &value) { const auto normalized = normalizedDensity(value); if (density() == normalized) return; m_settings.setValue("ui/density", normalized); m_settings.sync(); emit densityChanged(); }
