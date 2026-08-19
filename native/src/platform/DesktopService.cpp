#include "DesktopService.h"
#include <QDesktopServices>
#include <QFileDialog>
#include <QFileInfo>
#include <QUrl>

bool DesktopService::openFile(const QString &path) const {
    const QFileInfo info(path); if (!info.exists() || !info.isFile()) return false;
    return QDesktopServices::openUrl(QUrl::fromLocalFile(info.absoluteFilePath()));
}
bool DesktopService::revealFile(const QString &path) const {
    const QFileInfo info(path); if (!info.exists()) return false;
    return QDesktopServices::openUrl(QUrl::fromLocalFile(info.isDir() ? info.absoluteFilePath() : info.absolutePath()));
}
QString DesktopService::chooseFolder() const { return QFileDialog::getExistingDirectory(nullptr, tr("Select download folder")); }
