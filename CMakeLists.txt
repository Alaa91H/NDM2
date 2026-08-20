cmake_minimum_required(VERSION 3.21)
project(NDM2 VERSION 3.0.0 LANGUAGES CXX)

include(CTest)

option(NDM2_BUILD_NATIVE_UI "Build the native Qt Quick desktop UI" ON)
if(NDM2_BUILD_NATIVE_UI)
    add_subdirectory(native)
endif()

# Native release metadata. CPack packages the CMake install tree, whose Qt
# deployment script supplies the runtime and QML dependencies on supported
# desktop platforms. The legacy Tauri frontend is intentionally not a package
# input for NDM2 installers.
set(CPACK_PACKAGE_NAME "NDM2")
set(CPACK_PACKAGE_VENDOR "NOVA Download Manager")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "NOVA Download Manager native Qt client")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_PACKAGE_INSTALL_DIRECTORY "NDM2")
set(CPACK_PACKAGE_EXECUTABLES "NDM2" "NOVA Download Manager")
set(CPACK_NSIS_DISPLAY_NAME "NOVA Download Manager (NDM2)")
set(CPACK_NSIS_PACKAGE_NAME "NOVA Download Manager (NDM2)")
set(CPACK_NSIS_INSTALL_ROOT "$PROGRAMFILES64")
set(CPACK_NSIS_MUI_ICON "${CMAKE_CURRENT_SOURCE_DIR}/src-tauri/icons/icon.ico")
set(CPACK_NSIS_MUI_UNIICON "${CMAKE_CURRENT_SOURCE_DIR}/src-tauri/icons/icon.ico")
set(CPACK_NSIS_INSTALLED_ICON_NAME "bin\\NDM2.exe")
set(CPACK_NSIS_MUI_FINISHPAGE_RUN "bin\\NDM2.exe")
set(CPACK_NSIS_BRANDING_TEXT "NOVA Download Manager")
set(CPACK_NSIS_ENABLE_UNINSTALL_BEFORE_INSTALL ON)
include(CPack)
