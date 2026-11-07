// Shared basics: audio format, logging, the clock.
#pragma once

#include <cstdint>

namespace nv
{
constexpr int kRate = 48000;
constexpr int kBlock = 480;  // 10 ms: what the mic processor and the mixer work in
constexpr int kFrame = 960;  // 20 ms: one Opus frame

using PeerId = uint32_t;
constexpr PeerId kSelfVoice = 0xFFFFFFF0u; // the hear-yourself test plays through this voice

// Packet flags, sent with every audio packet.
constexpr uint8_t kFlagRadio = 1;  // the talker's radio mic is on
constexpr uint8_t kFlagSpurt = 2;  // first packet after the voice gate opened

struct Vec3
{
    float x = 0.f;
    float y = 0.f;
    float z = 0.f;
};

enum LogLevel
{
    LogTrace = 0,
    LogInfo = 1,
    LogWarn = 2,
    LogError = 3,
};

using LogSink = void (*)(int aLevel, const char* aText);
void SetLogSink(LogSink aSink);
void Logf(int aLevel, const char* aFormat, ...);

// Milliseconds on a steady clock.
double NowMs();
} // namespace nv
