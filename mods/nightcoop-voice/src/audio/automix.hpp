// Keeps voices in balance with the game, so no player has to set levels. Voices and the game share one output and one
// volume knob, so only the ratio between them matters, and that's measurable: this listens to what the output plays,
// takes away our own voices, and sets a gain for the voices.
//
// Two measures drive it. "Loud parts" follows how loud this player's game gets, slowly, and says where speech belongs.
// "Level" follows what's playing now, and lifts voices when a fight starts. Until there's anything to measure, or where
// the output can't be measured at all, loud parts comes from the game's Master Volume setting alone.
//
// No devices here, so the test program can feed it directly.
#pragma once

#include "audio/dsp.hpp"

#include <array>
#include <atomic>

namespace nv
{
// Roughly where speech arrives from another player's mic chain, before any gain here. The first real logs put it near
// -24 dB, averaged over talking and the short pauses in it.
constexpr float kNominalSpeechDb = -23.f;

class AutoMix
{
public:
    AutoMix();

    // From any thread.
    void SetGameMaster(float aPercent)
    {
        m_masterWanted.store(aPercent);
    }
    void SetOffsetDb(float aDb)
    {
        m_offsetDb.store(aDb); // the one level a player can still set, for taste
    }

    // From the render thread: what the output played, as mono, and each block we wrote to it (kBlock stereo frames).
    void OnPlayed(const float* aMono, int aCount);
    void OnBlock(const float* aStereo);

    float GainLinear() const
    {
        return m_gainLinear.load();
    }

    // For the log, from any thread.
    float GainDb() const
    {
        return m_gainReport.load();
    }
    float GameDb() const
    {
        return m_gameReport.load();
    }
    float LoudDb() const
    {
        return m_loudReport.load();
    }
    float Master() const
    {
        return m_masterWanted.load();
    }
    // How loud voices actually left this output since the last call, while they were playing.
    float TakeVoicesOutDb();
    bool Measured() const
    {
        return m_measuredReport.load();
    }

private:
    static constexpr int kHistory = 4;

    void EndWindow();
    void StartFromMaster(float aPercent);

    Biquad m_playedFilter;
    Biquad m_ownFilter;

    double m_playedEnergy = 0.0;
    int m_playedCount = 0;
    double m_ownEnergy = 0.0;
    int m_blocks = 0;

    std::array<double, kHistory> m_playedHistory{};
    std::array<double, kHistory> m_ownHistory{};
    int m_historyAt = 0;

    float m_master = -1.f;
    float m_loudFloorDb = 0.f;
    float m_loudDb = 0.f;
    float m_levelDb = 0.f;
    float m_gainDb = 0.f;

    std::atomic<float> m_masterWanted{100.f};
    std::atomic<float> m_offsetDb{0.f};
    std::atomic<float> m_gainLinear{1.f};
    std::atomic<float> m_gainReport{0.f};
    std::atomic<float> m_gameReport{-100.f};
    std::atomic<float> m_loudReport{0.f};
    std::atomic<bool> m_measuredReport{false};
    std::atomic<double> m_outEnergy{0.0};
    std::atomic<int> m_outWindows{0};
};
} // namespace nv
