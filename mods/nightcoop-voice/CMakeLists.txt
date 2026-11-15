cmake_minimum_required(VERSION 3.25)

set(CMAKE_POLICY_DEFAULT_CMP0091 NEW)
set(CMAKE_POLICY_VERSION_MINIMUM 3.5)

# version.txt holds the last release's number, and release-please raises it when it opens a release.
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/version.txt" NCV_RELEASE_VERSION LIMIT_COUNT 1)
project(NightCoopVoice VERSION ${NCV_RELEASE_VERSION} LANGUAGES C CXX)
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/version.txt")

# Static C runtime: the mod has to load on Bleack's Proton setup too, where the system's C++ runtime may be older than
# the one this was built against.
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

add_compile_definitions(WIN32_LEAN_AND_MEAN NOMINMAX UNICODE _UNICODE)

# Shared between the mods, in the repo's deps folder (tools/fetch-red4ext-sdk.ps1 at the root).
set(RED4EXT_SDK_DIR "${CMAKE_SOURCE_DIR}/../../deps/RED4ext.SDK" CACHE PATH "Path to a RED4ext.SDK checkout")

# ---- libraries, fetched by tools/fetch_deps.ps1
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_PROGRAMS OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_PKG_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL_CMAKE_CONFIG_MODULE OFF CACHE BOOL "" FORCE)
add_subdirectory(deps/opus EXCLUDE_FROM_ALL)

set(NO_TESTS ON CACHE BOOL "" FORCE)
set(NO_SERVER ON CACHE BOOL "" FORCE)
add_subdirectory(deps/libjuice EXCLUDE_FROM_ALL)

add_library(rnnoise STATIC
    deps/rnnoise/src/celt_lpc.c
    deps/rnnoise/src/denoise.c
    deps/rnnoise/src/kiss_fft.c
    deps/rnnoise/src/pitch.c
    deps/rnnoise/src/rnn.c
    deps/rnnoise/src/rnn_data.c
    deps/rnnoise/src/rnn_reader.c)
target_include_directories(rnnoise PUBLIC deps/rnnoise/include PRIVATE deps/rnnoise/src)
target_compile_definitions(rnnoise PRIVATE _USE_MATH_DEFINES _CRT_SECURE_NO_WARNINGS)
target_compile_options(rnnoise PRIVATE /W0)

# Only the echo canceller of speexdsp.
file(WRITE "${CMAKE_BINARY_DIR}/speexdsp_gen/speex/speexdsp_config_types.h"
"#ifndef SPEEXDSP_CONFIG_TYPES_H\n#define SPEEXDSP_CONFIG_TYPES_H\n#include <stdint.h>\n"
"typedef int16_t spx_int16_t;\ntypedef uint16_t spx_uint16_t;\ntypedef int32_t spx_int32_t;\ntypedef uint32_t spx_uint32_t;\n#endif\n")
add_library(speexecho STATIC
    deps/speexdsp/libspeexdsp/mdf.c
    deps/speexdsp/libspeexdsp/fftwrap.c
    deps/speexdsp/libspeexdsp/smallft.c)
target_include_directories(speexecho PUBLIC deps/speexdsp/include "${CMAKE_BINARY_DIR}/speexdsp_gen" PRIVATE deps/speexdsp/libspeexdsp)
target_compile_definitions(speexecho PRIVATE FLOATING_POINT USE_SMALLFT "EXPORT=" _USE_MATH_DEFINES)
target_compile_options(speexecho PRIVATE /W0)

add_library(monocypher STATIC deps/monocypher/src/monocypher.c)
target_include_directories(monocypher PUBLIC deps/monocypher/src)

# ---- the mod without the game, shared by the plugin and the test program
add_library(voicecore STATIC
    src/core/common.cpp
    src/core/settings.cpp
    src/net/packet.cpp
    src/net/link.cpp
    src/audio/acoustics.cpp
    src/audio/automix.cpp
    src/audio/car.cpp
    src/audio/dsp.cpp
    src/audio/headset_link.cpp
    src/audio/spatial.cpp
    src/audio/jitter.cpp
    src/audio/mic.cpp
    src/audio/mixer.cpp
    src/audio/radio.cpp
    src/audio/wasapi.cpp
    src/engine.cpp)
target_include_directories(voicecore PUBLIC src "${CMAKE_SOURCE_DIR}/../headset/src") # headset_api.h: what the Headset mod offers
target_link_libraries(voicecore PUBLIC opus rnnoise speexecho monocypher juice-static ole32 bcrypt)
target_compile_options(voicecore PRIVATE /W4 /utf-8 /permissive-)

add_executable(voice_test tools/voice_test.cpp)
target_link_libraries(voice_test PRIVATE voicecore)
target_compile_options(voice_test PRIVATE /W3 /utf-8)

# ---- for trying the headset clamp on recordings of the game (RECORD.md, 2026-11-07); not part of the mod
add_executable(record_game tools/record_game.cpp)
target_link_libraries(record_game PRIVATE ole32 winmm user32)
target_compile_options(record_game PRIVATE /W4 /utf-8)
add_executable(headset_clamp tools/headset_clamp.cpp)
target_compile_options(headset_clamp PRIVATE /W4 /utf-8)
target_compile_definitions(record_game PRIVATE _CRT_SECURE_NO_WARNINGS)
target_compile_definitions(headset_clamp PRIVATE _CRT_SECURE_NO_WARNINGS)

# ---- the plugin
if(EXISTS "${RED4EXT_SDK_DIR}/CMakeLists.txt")
    set(RED4EXT_HEADER_ONLY ON CACHE BOOL "" FORCE)
    add_subdirectory("${RED4EXT_SDK_DIR}" red4ext_sdk EXCLUDE_FROM_ALL)

    add_library(NightCoopVoice SHARED src/plugin/main.cpp src/plugin/keys.cpp)
    add_custom_target(NightCoopVoiceBuildTime
        COMMAND "${CMAKE_COMMAND}" "-DOUT=${CMAKE_BINARY_DIR}/generated/build_time.h" -DNAME=NCV_BUILT -P "${CMAKE_SOURCE_DIR}/../../tools/build-time.cmake"
        BYPRODUCTS "${CMAKE_BINARY_DIR}/generated/build_time.h"
        VERBATIM)
    add_dependencies(NightCoopVoice NightCoopVoiceBuildTime)
    target_include_directories(NightCoopVoice PRIVATE src "${CMAKE_SOURCE_DIR}/../../vendor/nightcoop-sdk/include" "${CMAKE_BINARY_DIR}/generated")
    target_link_libraries(NightCoopVoice PRIVATE voicecore RED4ext::SDK user32)
    target_compile_definitions(NightCoopVoice PRIVATE
        NCV_VERSION="${PROJECT_VERSION}"
        NCV_VERSION_MAJOR=${PROJECT_VERSION_MAJOR}
        NCV_VERSION_MINOR=${PROJECT_VERSION_MINOR}
        NCV_VERSION_PATCH=${PROJECT_VERSION_PATCH})
    # The SDK headers don't build cleanly at /W4.
    target_compile_options(NightCoopVoice PRIVATE /W3 /utf-8 /permissive-)

    install(TARGETS NightCoopVoice RUNTIME DESTINATION "red4ext/plugins/NightCoopVoice")
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/game/scripts/" DESTINATION "red4ext/plugins/NightCoopVoice/scripts")
    install(DIRECTORY "${CMAKE_SOURCE_DIR}/game/cet/"
            DESTINATION "bin/x64/plugins/cyber_engine_tweaks/mods/NightCoopVoice")
else()
    message(WARNING "RED4ext.SDK not found at ${RED4EXT_SDK_DIR}; only the test program will be built.")
endif()
