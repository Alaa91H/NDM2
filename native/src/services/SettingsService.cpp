#include "SettingsService.h"
#include <QLocale>

SettingsService::SettingsService(QObject *parent) : QObject(parent), m_settings("NOVA", "NDM2") {}
QString SettingsService::theme() const { return m_settings.value("ui/theme", "system").toString(); }
QString SettingsService::language() const { return m_settings.value("ui/language", QLocale::system().name().left(2)).toString(); }
QString SettingsService::density() const { return m_settings.value("ui/density", "comfortable").toString(); }
bool SettingsService::rightToLeft() const { const auto code = language().left(2).toLower(); return code == "ar" || code == "he" || code == "fa" || code == "ur"; }
void SettingsService::setTheme(const QString &value) { if (theme() == value) return; m_settings.setValue("ui/theme", value); emit themeChanged(); }
void SettingsService::setLanguage(const QString &value) { if (language() == value) return; m_settings.setValue("ui/language", value); emit languageChanged(); }
void SettingsService::setDensity(const QString &value) { if (density() == value) return; m_settings.setValue("ui/density", value); emit densityChanged(); }
