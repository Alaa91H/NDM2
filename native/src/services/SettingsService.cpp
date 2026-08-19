#include "SettingsService.h"
#include <QGuiApplication>
#include <QLocale>
#include <QPalette>

SettingsService::SettingsService(QObject *parent) : QObject(parent), m_settings("NOVA", "NDM2") {
    QGuiApplication::setLayoutDirection(rightToLeft() ? Qt::RightToLeft : Qt::LeftToRight);
}
QString SettingsService::theme() const { return m_settings.value("ui/theme", "system").toString(); }
QString SettingsService::language() const { return m_settings.value("ui/language", QLocale::system().name().left(2)).toString(); }
QString SettingsService::density() const { return m_settings.value("ui/density", "comfortable").toString(); }
bool SettingsService::rightToLeft() const { const auto code = language().left(2).toLower(); return code == "ar" || code == "he" || code == "fa" || code == "ur"; }
bool SettingsService::dark() const { if (theme() == "dark") return true; if (theme() == "light") return false; return QGuiApplication::palette().color(QPalette::Window).lightness() < 128; }
void SettingsService::setTheme(const QString &value) { if (theme() == value) return; m_settings.setValue("ui/theme", value); emit themeChanged(); }
void SettingsService::setLanguage(const QString &value) { if (language() == value) return; m_settings.setValue("ui/language", value); QGuiApplication::setLayoutDirection(rightToLeft() ? Qt::RightToLeft : Qt::LeftToRight); emit languageChanged(); }
void SettingsService::setDensity(const QString &value) { if (density() == value) return; m_settings.setValue("ui/density", value); emit densityChanged(); }
