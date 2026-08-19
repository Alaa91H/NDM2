#pragma once
#include <QObject>
class DesktopService final : public QObject {
    Q_OBJECT
public:
    explicit DesktopService(QObject *parent = nullptr) : QObject(parent) {}
    Q_INVOKABLE bool openFile(const QString &path) const;
    Q_INVOKABLE bool revealFile(const QString &path) const;
    Q_INVOKABLE QString chooseFolder() const;
};
