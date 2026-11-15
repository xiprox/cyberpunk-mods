cmake_minimum_required(VERSION 3.25)

set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

# version.txt holds the last release's number, and release-please raises it when it opens a release.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/version.txt" HS_RELEASE_VERSION LIMIT_COUNT 1)
project(Headset VERSION ${HS_RELEASE_VERSION} LANGUAGES CXX)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/version.txt")

# Static C runtime: the mod has to load on Bleack's Proton setup too, where the system's C++ runtime may be older than the
# one this was built against.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_definitions(WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)

# Shared between the mods, in the repo's deps folder (tools/fetch-red4ext-sdk.ps1 at the root).
set(RED4EXT_SDK_DIR "${CMAKE_SOURCE_DIR}/../../deps/RED4ext.SDK" CACHE PATH "Path to a RED4ext.SDK checkout")

# ---- the mod without the game, shared by the plugin and the test program
add_library(headsetcore STATIC
    src/core/common.cpp
    src/core/settings.cpp
    src/headset/clamp.cpp
    src/headset/control.cpp
    src/headset/voices.cpp
    src/wwise/effect.cpp
    src/wwise/install.cpp)
target_include_directories(headsetcore PUBLIC src)
target_compile_options(headsetcore PRIVATE /W4 /utf-8 /permissive-)

add_executable(headset_test tools/headset_test.cpp)
target_link_libraries(headset_test PRIVATE headsetcore)
target_compile_options(headset_test PRIVATE /W3 /utf-8)

# ---- the plugin
if(EXISTS "${RED4EXT_SDK_DIR}/CMakeLists.txt")
    set(RED4EXT_HEADER_ONLY ON CACHE BOOL "" FORCE)
    add_subdirectory("${RED4EXT_SDK_DIR}" red4ext_sdk EXCLUDE_FROM_ALL)

    add_library(Headset SHARED src/plugin/main.cpp src/plugin/keys.cpp)
    # Test builds between releases share a number, so the log also says when each was built.
    add_custom_target(HeadsetBuildTime
        COMMAND "${CMAKE_COMMAND}" "-DOUT=${CMAKE_BINARY_DIR}/generated/build_time.h" -DNAME=HS_BUILT -P "${CMAKE_SOURCE_DIR}/../../tools/build-time.cmake"
        BYPRODUCTS "${CMAKE_BINARY_DIR}/generated/build_time.h"
        VERBATIM)
    add_dependencies(Headset HeadsetBuildTime)
    target_include_directories(Headset PRIVATE src "${CMAKE_BINARY_DIR}/generated")
    target_link_libraries(Headset PRIVATE headsetcore RED4ext::SDK user32)
    target_compile_definitions(Headset PRIVATE
        HS_VERSION="${PROJECT_VERSION}"
        HS_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
        HS_VERSION_MINOR=${PROJECT_VERSION_MINOR}
        HS_VERSION_PATCH=${PROJECT_VERSION_PATCH})
    # The SDK headers don't build cleanly at /W4.
    target_compile_options(Headset PRIVATE /W3 /utf-8 /permissive-)

    install(TARGETS Headset RUNTIME DESTINATION "red4ext/plugins/Headset")
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/game/scripts/" DESTINATION "red4ext/plugins/Headset/scripts")
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/game/archive/" DESTINATION "archive/pc/mod")
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/game/cet/"
            DESTINATION "bin/x64/plugins/cyber_engine_tweaks/mods/Headset")
else()
    message(WARNING "RED4ext.SDK not found at ${RED4EXT_SDK_DIR}; only the test program will be built.")
endif()
