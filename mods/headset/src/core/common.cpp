#include "core/common.hpp"

#include <windows.h>

#include <atomic>
#include <cstdarg>
#include <cstdio>

namespace hs
{
namespace
{
std::atomic<LogSink> g_sink{nullptr};
}

void SetLogSink(LogSink aSink)
{
    g_sink.store(aSink);
}

void Logf(int aLevel, const char* aFormat, ...)
{
    const LogSink sink = g_sink.load();
    if (!sink)
    {
        return;
    }
    char buffer[1024];
    va_list args;
    va_start(args, aFormat);
    vsnprintf(buffer, sizeof(buffer), aFormat, args);
    va_end(args);
    sink(aLevel, buffer);
}

double NowMs()
{
    static const double msPerTick = [] {
        LARGE_INTEGER frequency;
        QueryPerformanceFrequency(&frequency);
        return 1000.0 / static_cast<double>(frequency.QuadPart);
    }();
    LARGE_INTEGER now;
    QueryPerformanceCounter(&now);
    return static_cast<double>(now.QuadPart) * msPerTick;
}
} // namespace hs
