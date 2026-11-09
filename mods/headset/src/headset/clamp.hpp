// The hearing protection's clamp: how far the world is turned down, sample by sample, from how loud the bangs are.
#pragma once

#include <cstdint>

namespace hs
{
// No look-ahead, like a headset's electronics: it acts on the very sample a peak arrives. Timing is the "headset3" the user
// tuned by ear in NightCoop Voice ("feels fantastic"). Only what's measured changed: there the finished mix, here real bangs.
class ClampEnvelope
{
public:
    void Configure(int aRate);
    void Reset();

    // aLevel: how far over the threshold this sample is, 1 being exactly at it. Returns the gain to apply.
    float Track(float aLevel, float aDepthPerDb, float aFloor);

private:
    float m_release = 0.f, m_slowRelease = 0.f, m_busyRise = 0.f, m_busyFall = 0.f, m_sink = 0.f;
    int m_holdSamples = 0;
    int m_holdLeft = 0;
    float m_peak = 0.f;
    float m_gain = 1.f;
    float m_busy = 0.f;
    float m_lastPeak = -1.f;
    float m_lastDepth = -1.f;
    float m_lastFloor = -1.f;
    float m_target = 1.f;
};
} // namespace hs
