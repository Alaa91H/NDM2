find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Network Quick QuickControls2 Widgets)
qt_standard_project_setup(REQUIRES 6.4)

qt_add_executable(NDM2
    src/main.cpp
    src/adapter/CoreAdapter.cpp
    src/models/DownloadModel.cpp
    src/services/TaskController.cpp
    src/services/SettingsService.cpp
    src/platform/DesktopService.cpp
)

target_include_directories(NDM2 PRIVATE src)
target_link_libraries(NDM2 PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Quick Qt6::QuickControls2 Qt6::Widgets
)

qt_add_qml_module(NDM2
    URI NDM
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/NavItem.qml
        qml/components/DownloadRow.qml
        qml/components/EmptyState.qml
        qml/components/SpeedGraph.qml
        qml/dialogs/AddDownloadDialog.qml
        qml/dialogs/DetailsDrawer.qml
        qml/dialogs/SettingsDialog.qml
        qml/pages/QueuePage.qml
        qml/pages/DiagnosticsPage.qml
)

set_target_properties(NDM2 PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
)

include(GNUInstallDirs)
install(TARGETS NDM2
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
