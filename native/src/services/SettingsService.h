#pragma once
#include <QSettings>

class SettingsService final : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString theme READ theme WRITE setTheme NOTIFY themeChanged)
    Q_PROPERTY(QString language READ language WRITE setLanguage NOTIFY languageChanged)
    Q_PROPERTY(QString density READ density WRITE setDensity NOTIFY densityChanged)
    Q_PROPERTY(bool rightToLeft READ rightToLeft NOTIFY languageChanged)
    Q_PROPERTY(bool dark READ dark NOTIFY themeChanged)
    Q_PROPERTY(bool notificationsEnabled READ notificationsEnabled WRITE setNotificationsEnabled NOTIFY notificationsChanged)
public:
    explicit SettingsService(QObject *parent = nullptr);
    QString theme() const; QString language() const; QString density() const;
    bool rightToLeft() const; bool dark() const; bool notificationsEnabled() const;
    Q_INVOKABLE void setNotificationsEnabled(bool value);
    Q_INVOKABLE void setTheme(const QString &value); Q_INVOKABLE void setLanguage(const QString &value); Q_INVOKABLE void setDensity(const QString &value);
signals:
    void themeChanged(); void languageChanged(); void densityChanged(); void notificationsChanged();
private:
    QSettings m_settings;
};
