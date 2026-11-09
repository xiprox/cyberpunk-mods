// Shared basics: logging and the clock.
#pragma once

namespace hs
{
enum LogLevel
{
    LogInfo = 1,
    LogWarn = 2,
};

using LogSink = void (*)(int aLevel, const char* aText);
void SetLogSink(LogSink aSink);
void Logf(int aLevel, const char* aFormat, ...);

// Milliseconds on a steady clock.
double NowMs();
} // namespace hs
