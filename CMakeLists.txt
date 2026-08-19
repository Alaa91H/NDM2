cmake_minimum_required(VERSION 3.21)
project(NDM2 VERSION 3.0.0 LANGUAGES CXX)

include(CTest)

option(NDM2_BUILD_NATIVE_UI "Build the native Qt Quick desktop UI" ON)
if(NDM2_BUILD_NATIVE_UI)
    add_subdirectory(native)
endif()
