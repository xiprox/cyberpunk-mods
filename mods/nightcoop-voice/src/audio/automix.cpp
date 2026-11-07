#include "audio/automix.hpp"

#include <cmath>

namespace nv
{
namespace
{
constexpr int kWindowBlocks = 10; // 100 ms

// Starting values, to tune by ear and from the levels in the logs.
constexpr float kLoudAtFullMasterDb = -14.f; // a guess until measured: how loud the game gets at Master 100
constexpr float kSpeechBelowLoudDb = 2.f;    // where speech sits against the game's loud parts
constexpr float kSpeechAboveLevelDb = 3.f;   // and how far above whatever's playing right now
constexpr float kMinGainDb = -14.f;
constexpr float kMaxGainDb = 12.f;
constexpr float kLoudFloorBelowMasterDb = 2.f; // calm play mustn't sink voices: the game's loud parts haven't gone away
constexpr double kVoicePlaying = 1e-6;         // -60 dB: below this our output counts as silent, for the log

constexpr float kNoSignalDb = -65.f;      // nothing playing: a menu, or voices and game on different outputs
constexpr double kOwnDominates = 0.5;     // voices are most of the output: what's left isn't worth believing
constexpr float kHighpassHz = 150.f;      // bass is loud on the meter but doesn't cover speech

// Per 100 ms window.
constexpr float kLevelRise = 0.133f;      // about 0.7 s
constexpr float kLevelFall = 0.0124f;     // about 8 s
constexpr float kLoudRise = 0.033f;       // about 3 s, so one grenade doesn't move it far
constexpr float kLoudFall = 0.00017f;     // about 10 min
constexpr float kGainUpDb = 0.6f;         // 6 dB/s: quick when a fight starts
constexpr float kGainDownDb = 0.15f;      // 1.5 dB/s: never a sudden drop

float ToDb(double aPower)
{
    return 10.f * static_cast<float>(std::log10(std::max(aPower, 1e-12)));
}
} // namespace

AutoMix::AutoMix()
{
    m_playedFilter.SetHighpass(kHighpassHz);
    m_ownFilter.SetHighpass(kHighpassHz);
    StartFromMaster(100.f);
    m_gainDb = std::clamp(std::max(m_loudDb - kSpeechBelowLoudDb, m_levelDb + kSpeechAboveLevelDb) - kNominalSpeechDb,
                          kMinGainDb, kMaxGainDb);
}

void AutoMix::StartFromMaster(float aPercent)
{
    m_master = aPercent;
    // The slider's curve isn't known, so this treats it as plain amplitude; measuring corrects it.
    const float start = kLoudAtFullMasterDb + 20.f * std::log10(std::clamp(aPercent, 5.f, 100.f) / 100.f);
    m_loudDb = start;
    m_loudFloorDb = start - kLoudFloorBelowMasterDb;
    m_levelDb = start - kSpeechBelowLoudDb - kSpeechAboveLevelDb;
}

float AutoMix::TakeVoicesOutDb()
{
    const double energy = m_outEnergy.exchange(0.0);
    const int windows = m_outWindows.exchange(0);
    return windows > 0 ? ToDb(energy / windows) : -100.f;
}

void AutoMix::OnPlayed(const float* aMono, int aCount)
{
    for (int i = 0; i < aCount; ++i)
    {
        const float sample = m_playedFilter.Process(aMono[i]);
        m_playedEnergy += static_cast<double>(sample) * sample;
    }
    m_playedCount += aCount;
}

void AutoMix::OnBlock(const float* aStereo)
{
    for (int i = 0; i < kBlock; ++i)
    {
        const float sample = m_ownFilter.Process((aStereo[i * 2] + aStereo[i * 2 + 1]) * 0.5f);
        m_ownEnergy += static_cast<double>(sample) * sample;
    }
    if (++m_blocks >= kWindowBlocks)
    {
        EndWindow();
    }
}

void AutoMix::EndWindow()
{
    const float master = m_masterWanted.load();
    if (master != m_master)
    {
        StartFromMaster(master); // the player moved the slider, so the old measure no longer holds
    }

    const bool measured = m_playedCount > 0;
    m_playedHistory[static_cast<size_t>(m_historyAt)] = measured ? m_playedEnergy / m_playedCount : 0.0;
    const double ownNow = m_ownEnergy / (kBlock * m_blocks);
    m_ownHistory[static_cast<size_t>(m_historyAt)] = ownNow;
    m_historyAt = (m_historyAt + 1) % kHistory;
    if (ownNow > kVoicePlaying)
    {
        m_outEnergy.fetch_add(ownNow);
        m_outWindows.fetch_add(1);
    }
    m_playedEnergy = 0.0;
    m_playedCount = 0;
    m_ownEnergy = 0.0;
    m_blocks = 0;

    // Averaged over 400 ms, so the time our voices take to come back through the output hardly matters.
    double played = 0.0;
    double own = 0.0;
    for (int i = 0; i < kHistory; ++i)
    {
        played += m_playedHistory[static_cast<size_t>(i)] / kHistory;
        own += m_ownHistory[static_cast<size_t>(i)] / kHistory;
    }

    if (measured && own < played * kOwnDominates)
    {
        const float gameDb = ToDb(played - own);
        m_gameReport.store(gameDb);
        // Silence still lets the level fall, or a burst just before a loading screen would hold voices up through it.
        // It says nothing about how loud this game gets, though, so that measure waits.
        const float heardDb = std::max(gameDb, kNoSignalDb);
        m_levelDb += (heardDb - m_levelDb) * (heardDb > m_levelDb ? kLevelRise : kLevelFall);
        if (gameDb > kNoSignalDb)
        {
            m_loudDb += (m_levelDb - m_loudDb) * (m_levelDb > m_loudDb ? kLoudRise : kLoudFall);
            m_loudDb = std::max(m_loudDb, m_loudFloorDb);
        }
    }
    m_measuredReport.store(measured);

    const float speechDb = std::max(m_loudDb - kSpeechBelowLoudDb, m_levelDb + kSpeechAboveLevelDb);
    const float target = std::clamp(speechDb - kNominalSpeechDb, kMinGainDb, kMaxGainDb);
    m_gainDb += std::clamp(target - m_gainDb, -kGainDownDb, kGainUpDb);

    const float total = m_gainDb + m_offsetDb.load();
    m_gainLinear.store(std::pow(10.f, total / 20.f));
    m_gainReport.store(total);
    m_loudReport.store(m_loudDb);
}
} // namespace nv
