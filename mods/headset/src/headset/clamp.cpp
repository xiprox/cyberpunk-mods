#include "headset/clamp.hpp"

#include <algorithm>
#include <cmath>

namespace hs
{
namespace
{
constexpr float kReleaseMs = 150.f;     // back up after a single bang
constexpr float kReleaseSlowMs = 900.f; // while bangs keep coming, so the world doesn't breathe at the fire rate
constexpr float kBusyRiseMs = 80.f;
constexpr float kBusyFallMs = 2500.f;
constexpr float kPeakHoldMs = 30.f;     // stops the clamp chattering on each cycle of a low rumble

float Coefficient(float aMs, int aRate)
{
    return 1.f - std::exp(-1000.f / (aMs * static_cast<float>(aRate)));
}
} // namespace

void ClampEnvelope::Configure(int aRate)
{
    m_release = Coefficient(kReleaseMs, aRate);
    m_slowRelease = Coefficient(kReleaseSlowMs, aRate);
    m_busyRise = Coefficient(kBusyRiseMs, aRate);
    m_busyFall = Coefficient(kBusyFallMs, aRate);
    m_holdSamples = static_cast<int>(kPeakHoldMs * static_cast<float>(aRate) / 1000.f);
    m_sink = 1.f - Coefficient(kPeakHoldMs, aRate);
}

void ClampEnvelope::Reset()
{
    m_peak = 0.f;
    m_gain = 1.f;
    m_busy = 0.f;
    m_holdLeft = 0;
    m_lastPeak = -1.f;
}

float ClampEnvelope::Track(float aLevel, float aDepthPerDb, float aFloor)
{
    if (aLevel >= m_peak)
    {
        m_peak = aLevel;
        m_holdLeft = m_holdSamples;
    }
    else if (m_holdLeft > 0)
    {
        --m_holdLeft;
    }
    else
    {
        m_peak = std::max(aLevel, m_peak * m_sink);
    }

    if (m_peak != m_lastPeak || aDepthPerDb != m_lastDepth || aFloor != m_lastFloor)
    {
        m_lastPeak = m_peak;
        m_lastDepth = aDepthPerDb;
        m_lastFloor = aFloor;
        m_target = m_peak > 1.f ? std::max(std::pow(m_peak, -aDepthPerDb), aFloor) : 1.f;
    }

    const bool down = m_gain < 0.5f; // over 6 dB
    m_busy += ((down ? 1.f : 0.f) - m_busy) * (down ? m_busyRise : m_busyFall);
    const float release = m_release + (m_slowRelease - m_release) * m_busy;
    m_gain = m_target < m_gain ? m_target : m_gain + (m_target - m_gain) * release;
    return m_gain;
}
} // namespace hs
