#include "adapter/CoreAdapter.h"
#include "platform/DesktopService.h"
#include "services/SettingsService.h"
#include "services/TaskController.h"

#include <QCommandLineOption>
#include <QCommandLineParser>
#include <QAction>
#include <QGuiApplication>
#include <QIcon>
#include <QMenu>
#include <QSettings>
#include <QSystemTrayIcon>
#include <QWindow>
#include <QQmlApplicationEngine>
#include <QQmlContext>

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setOrganizationName("NOVA"); app.setOrganizationDomain("nova.download"); app.setApplicationName("NDM2");

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
    engine.load(QUrl(QStringLiteral("qrc:/NDM/qml/Main.qml")));
    if (engine.rootObjects().isEmpty()) return 1;

    auto *mainWindow = qobject_cast<QWindow *>(engine.rootObjects().constFirst());
    auto *windowSettings = new QSettings(&app);
    if (mainWindow) {
        mainWindow->setWidth(windowSettings->value("window/width", 1440).toInt());
        mainWindow->setHeight(windowSettings->value("window/height", 900).toInt());
        mainWindow->setX(windowSettings->value("window/x", mainWindow->x()).toInt());
        mainWindow->setY(windowSettings->value("window/y", mainWindow->y()).toInt());
        QObject::connect(&app, &QCoreApplication::aboutToQuit, mainWindow, [mainWindow, windowSettings] {
            windowSettings->setValue("window/width", mainWindow->width());
            windowSettings->setValue("window/height", mainWindow->height());
            windowSettings->setValue("window/x", mainWindow->x());
            windowSettings->setValue("window/y", mainWindow->y());
        });
    }

    if (QSystemTrayIcon::isSystemTrayAvailable()) {
        auto *tray = new QSystemTrayIcon(QIcon::fromTheme("folder-download"), &app);
        if (tray->icon().isNull()) tray->setIcon(QIcon::fromTheme("applications-internet"));
        auto *menu = new QMenu;
        auto *showAction = menu->addAction(QObject::tr("Show NDM2"));
        menu->addSeparator();
        auto *quitAction = menu->addAction(QObject::tr("Quit"));
        tray->setContextMenu(menu);
        QObject::connect(showAction, &QAction::triggered, mainWindow, [mainWindow] { if (mainWindow) { mainWindow->show(); mainWindow->raise(); mainWindow->requestActivate(); } });
        QObject::connect(quitAction, &QAction::triggered, &app, &QCoreApplication::quit);
        QObject::connect(tray, &QSystemTrayIcon::activated, mainWindow, [mainWindow](QSystemTrayIcon::ActivationReason reason) { if (reason == QSystemTrayIcon::Trigger && mainWindow) { mainWindow->show(); mainWindow->raise(); mainWindow->requestActivate(); } });
        tray->show();
    }
    return app.exec();
}
