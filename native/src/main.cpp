#include "adapter/CoreAdapter.h"
#include "platform/DesktopService.h"
#include "services/SettingsService.h"
#include "services/TaskController.h"

#include <QAction>
#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QDebug>
#include <QGuiApplication>
#include <QHash>
#include <QIcon>
#include <QMenu>
#include <QScreen>
#include <QSettings>
#include <QSystemTrayIcon>
#include <QTimer>
#include <QWindow>
#include <QQmlApplicationEngine>
#include <QQmlContext>

namespace {
QRect preferredWindowGeometry(QWindow *window, QSettings *settings) {
    const auto *screen = window && window->screen() ? window->screen() : QGuiApplication::primaryScreen();
    const QRect available = screen ? screen->availableGeometry() : QRect(0, 0, 1280, 800);
    const int maximumWidth = qMax(820, available.width() - 48);
    const int maximumHeight = qMax(560, available.height() - 48);
    const int defaultWidth = qMin(1180, maximumWidth);
    const int defaultHeight = qMin(760, maximumHeight);
    const int width = qBound(820, settings->value("window/width", defaultWidth).toInt(), maximumWidth);
    const int height = qBound(560, settings->value("window/height", defaultHeight).toInt(), maximumHeight);
    const QPoint savedPosition(settings->value("window/x", available.center().x() - width / 2).toInt(), settings->value("window/y", available.center().y() - height / 2).toInt());
    QRect restored(savedPosition, QSize(width, height));
    const QRect visibleArea = restored.intersected(available);
    if (!available.intersects(restored) || visibleArea.width() < 160 || visibleArea.height() < 120) restored.moveCenter(available.center());
    if (restored.left() < available.left()) restored.moveLeft(available.left());
    if (restored.top() < available.top()) restored.moveTop(available.top());
    if (restored.right() > available.right()) restored.moveRight(available.right());
    if (restored.bottom() > available.bottom()) restored.moveBottom(available.bottom());
    return restored;
}
}

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setOrganizationName("NOVA"); app.setOrganizationDomain("nova.download"); app.setApplicationName("NDM2");
    app.setApplicationVersion(QStringLiteral(NDM2_VERSION));
    const QIcon applicationIcon(QStringLiteral(":/branding/app-icon.png"));
    if (!applicationIcon.isNull()) app.setWindowIcon(applicationIcon);

    QCommandLineParser parser;
    parser.setApplicationDescription("NDM2 native Qt Quick desktop user interface"); parser.addHelpOption();
    QCommandLineOption endpointOption({"e", "daemon-endpoint"}, "Loopback NOVA daemon URL.", "url", qEnvironmentVariable("NOVA_DAEMON_URL", "http://127.0.0.1:3199"));
    QCommandLineOption tokenOption({"t", "daemon-token"}, "Daemon bearer token. Prefer NOVA_DAEMON_TOKEN in non-interactive environments.", "token", qEnvironmentVariable("NOVA_DAEMON_TOKEN"));
    parser.addOption(endpointOption); parser.addOption(tokenOption); parser.process(app);

    CoreAdapter adapter(parser.value(endpointOption), parser.value(tokenOption));
    TaskController controller(&adapter); SettingsService settings; DesktopService desktop;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty("taskController", &controller);
    engine.rootContext()->setContextProperty("settingsService", &settings);
    engine.rootContext()->setContextProperty("desktopService", &desktop);
    engine.rootContext()->setContextProperty("ndm2Version", app.applicationVersion());
    engine.load(QUrl(QStringLiteral("qrc:/NDM/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) {
        qCritical() << "NDM2 startup error: the native interface could not be loaded.";
        return 1;
    }

    auto *mainWindow = qobject_cast<QWindow *>(engine.rootObjects().constFirst());
    auto *windowSettings = new QSettings(&app);
    if (mainWindow) {
        if (!applicationIcon.isNull()) mainWindow->setIcon(applicationIcon);
        mainWindow->setGeometry(preferredWindowGeometry(mainWindow, windowSettings));
        QObject::connect(&app, &QCoreApplication::aboutToQuit, mainWindow, [mainWindow, windowSettings] {
            windowSettings->setValue("window/width", mainWindow->width());
            windowSettings->setValue("window/height", mainWindow->height());
            windowSettings->setValue("window/x", mainWindow->x());
            windowSettings->setValue("window/y", mainWindow->y());
            windowSettings->sync();
        });
    }

    if (QSystemTrayIcon::isSystemTrayAvailable()) {
        app.setQuitOnLastWindowClosed(false);
        const QIcon trayIcon = !applicationIcon.isNull() ? applicationIcon : QIcon::fromTheme("folder-download");
        auto *tray = new QSystemTrayIcon(trayIcon, &app);
        auto *menu = new QMenu;
        auto *summaryAction = menu->addAction(QObject::tr("NOVA Core: loading…"));
        summaryAction->setEnabled(false);
        auto *showAction = menu->addAction(QObject::tr("Open NDM2"));
        auto *pauseAllAction = menu->addAction(QObject::tr("Pause active downloads"));
        auto *resumeAllAction = menu->addAction(QObject::tr("Resume queued and paused downloads"));
        menu->addSeparator();
        auto *quitAction = menu->addAction(QObject::tr("Quit"));
        tray->setContextMenu(menu);
        auto updateTray = [&controller, tray, summaryAction, pauseAllAction, resumeAllAction] {
            const int active = controller.downloads()->countForStatus("downloading");
            const int paused = controller.downloads()->countForStatus("paused") + controller.downloads()->countForStatus("queued");
            const QString status = controller.connected() ? QObject::tr("NOVA Core online") : QObject::tr("NOVA Core unavailable");
            summaryAction->setText(QObject::tr("%1 · %2 active · %3 paused/queued").arg(status).arg(active).arg(paused));
            pauseAllAction->setEnabled(controller.connected() && active > 0);
            resumeAllAction->setEnabled(controller.connected() && paused > 0);
            tray->setToolTip(QObject::tr("NDM2 — %1 active, %2 paused/queued").arg(active).arg(paused));
        };
        auto *trayTimer = new QTimer(&app);
        trayTimer->setInterval(1500);
        QObject::connect(trayTimer, &QTimer::timeout, &app, updateTray);
        auto *priorStatuses = new QHash<QString, QString>();
        QObject::connect(&app, &QCoreApplication::aboutToQuit, &app, [priorStatuses] { delete priorStatuses; });
        auto *initialStatusSnapshot = new bool(false);
        auto notifyTransitions = [&controller, &settings, tray, priorStatuses, initialStatusSnapshot] {
            QHash<QString, QString> current;
            for (int row = 0; row < controller.downloads()->rowCount(); ++row) {
                const auto index = controller.downloads()->index(row, 0);
                const auto id = controller.downloads()->data(index, DownloadModel::IdRole).toString();
                const auto name = controller.downloads()->data(index, DownloadModel::NameRole).toString();
                const auto status = controller.downloads()->data(index, DownloadModel::StatusRole).toString();
                current.insert(id, status);
                if (!*initialStatusSnapshot || !settings.notificationsEnabled() || !priorStatuses->contains(id) || priorStatuses->value(id) == status) continue;
                QString title;
                QSystemTrayIcon::MessageIcon icon = QSystemTrayIcon::Information;
                if (status == "completed") title = QObject::tr("Download completed");
                else if (status == "error") { title = QObject::tr("Download failed"); icon = QSystemTrayIcon::Critical; }
                else if (status == "paused") title = QObject::tr("Download paused");
                else if (status == "downloading" && priorStatuses->value(id) == "paused") title = QObject::tr("Download resumed");
                if (!title.isEmpty()) tray->showMessage(title, name, icon, 5000);
            }
            *priorStatuses = current;
            *initialStatusSnapshot = true;
        };
        QObject::connect(controller.downloads(), &QAbstractItemModel::modelReset, &app, [updateTray, notifyTransitions] { updateTray(); notifyTransitions(); });
        QObject::connect(controller.downloads(), &QAbstractItemModel::dataChanged, &app, [updateTray, notifyTransitions](const QModelIndex &, const QModelIndex &, const QList<int> &) { updateTray(); notifyTransitions(); });
        QObject::connect(&controller, &TaskController::connectionChanged, &app, updateTray);
        QObject::connect(showAction, &QAction::triggered, mainWindow, [mainWindow] { if (mainWindow) { mainWindow->showNormal(); mainWindow->raise(); mainWindow->requestActivate(); } });
        QObject::connect(pauseAllAction, &QAction::triggered, &controller, &TaskController::pauseAll);
        QObject::connect(resumeAllAction, &QAction::triggered, &controller, &TaskController::resumeAll);
        QObject::connect(quitAction, &QAction::triggered, &app, &QCoreApplication::quit);
        QObject::connect(tray, &QSystemTrayIcon::activated, mainWindow, [mainWindow](QSystemTrayIcon::ActivationReason reason) { if (reason == QSystemTrayIcon::Trigger && mainWindow) { mainWindow->showNormal(); mainWindow->raise(); mainWindow->requestActivate(); } });
        updateTray();
        trayTimer->start();
        tray->show();
    }
    return app.exec();
}
