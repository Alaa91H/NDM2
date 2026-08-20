find_package(Qt6 6.4 REQUIRED COMPONENTS Core Gui Network Quick QuickControls2 Widgets Test)
qt_standard_project_setup(REQUIRES 6.4)

qt_add_executable(NDM2
    src/main.cpp
    src/adapter/CoreAdapter.cpp
    src/models/DownloadModel.cpp
    src/models/DownloadFilterProxyModel.cpp
    src/services/TaskController.cpp
    src/services/SettingsService.cpp
    src/platform/DesktopService.cpp
    $<$<PLATFORM_ID:Windows>:resources/ndm2.rc>
)

target_include_directories(NDM2 PRIVATE src)
target_compile_definitions(NDM2 PRIVATE NDM2_VERSION="${PROJECT_VERSION}")
target_link_libraries(NDM2 PRIVATE
    Qt6::Core Qt6::Gui Qt6::Network Qt6::Quick Qt6::QuickControls2 Qt6::Widgets
)

qt_add_resources(NDM2 "ndm2_branding"
    PREFIX "/branding"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/../branding/source"
    FILES "${CMAKE_CURRENT_SOURCE_DIR}/../branding/source/app-icon.png"
)

qt_add_qml_module(NDM2
    URI NDM
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/components/Theme.qml
        qml/components/InfoCard.qml
        qml/components/WorkspaceWindow.qml
        qml/components/IconButton.qml
        qml/components/ThemedCheckBox.qml
        qml/components/ThemedComboBox.qml
        qml/components/ThemedSpinBox.qml
        qml/components/ThemedSwitch.qml
        qml/components/ThemedTextArea.qml
        qml/components/ThemedTextField.qml
        qml/components/ActionButton.qml
        qml/components/SectionHeader.qml
        qml/components/StatusBadge.qml
        qml/components/NavItem.qml
        qml/components/DownloadRow.qml
        qml/components/EmptyState.qml
        qml/components/SpeedGraph.qml
        qml/dialogs/AddDownloadDialog.qml
        qml/dialogs/DetailsDrawer.qml
        qml/dialogs/SettingsDialog.qml
        qml/pages/QueuePage.qml
        qml/pages/DiagnosticsPage.qml
        qml/pages/AutomationPage.qml
        qml/pages/MediaPage.qml
        qml/pages/IntegrationPage.qml
)

set_target_properties(NDM2 PROPERTIES
    WIN32_EXECUTABLE TRUE
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "NOVA Download Manager"
    MACOSX_BUNDLE_GUI_IDENTIFIER "download.nova.ndm2"
)

if(APPLE)
    set(ndm2_macos_icon "${CMAKE_CURRENT_SOURCE_DIR}/../src-tauri/icons/icon.icns")
    set_source_files_properties("${ndm2_macos_icon}" PROPERTIES MACOSX_PACKAGE_LOCATION "Resources")
    target_sources(NDM2 PRIVATE "${ndm2_macos_icon}")
    set_target_properties(NDM2 PROPERTIES MACOSX_BUNDLE_ICON_FILE "icon.icns")
endif()

include(GNUInstallDirs)
install(TARGETS NDM2
    BUNDLE DESTINATION .
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Produce the platform-appropriate Qt runtime and QML deployment at install time.
# On Windows and macOS this delegates to Qt's deployment tools; on Linux it still
# installs the application's QML module for the release bundle.
qt_generate_deploy_qml_app_script(
    TARGET NDM2
    FILENAME_VARIABLE ndm2_deploy_script
    NO_UNSUPPORTED_PLATFORM_ERROR
    DEPLOY_USER_QML_MODULES_ON_UNSUPPORTED_PLATFORM
)
install(SCRIPT ${ndm2_deploy_script})

if(BUILD_TESTING)
    qt_add_executable(NDM2ModelTests
        tests/DownloadModelTest.cpp
        src/models/DownloadModel.cpp
        src/models/DownloadFilterProxyModel.cpp
        src/services/SettingsService.cpp
    )
    target_include_directories(NDM2ModelTests PRIVATE src)
    target_link_libraries(NDM2ModelTests PRIVATE Qt6::Core Qt6::Gui Qt6::Test)
    add_test(NAME NDM2ModelTests COMMAND NDM2ModelTests)
    set_tests_properties(NDM2ModelTests PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()
